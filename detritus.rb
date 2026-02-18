#!/usr/bin/env ruby
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "ruby_llm", "~> 1.11"
  gem "reline"
  gem "ostruct"
  gem "yaml"
  gem "json"
  gem "fileutils"
end

# === Scripts and Prompts file searches (global ~/.detritus and project-local .detritus) ===
def find_resources(subdir, pattern)
  [".detritus/#{subdir}", "#{ENV["HOME"]}/.detritus/#{subdir}"]
    .flat_map { |dir| Dir.glob(File.join(File.expand_path(dir), pattern)) }
    .uniq { |path| File.basename(path) }
end

def find_prompt_file(name) = find_resources("prompts", "#{name}{,.txt}").first
def find_script(name) = find_resources("scripts", name).find { |path| File.executable?(path) }

def available_prompts
  find_resources("prompts", "*.txt")
    .reject { |path| File.basename(path) == "system.txt" }
    .map { |file| [File.basename(file), File.open(file, &:readline).strip] }
    .map { |file, description| "- `#{file}`: #{description}" }.join("\n")
end

def build_prompt(command, args)
  if (prompt_file = find_prompt_file(command))
    File.read(prompt_file).gsub("{{ARGS}}", args)
  else
    puts "[✘ Error: Prompt '#{command}' not found"
  end
end

def available_scripts
  find_resources("scripts", "*")
    .select { |path| File.executable?(path) && File.file?(path) }
    .map { |file| [file, `#{file} --help 2>&1`.lines.first&.strip || "No description available"] }
    .to_h
    .map { |name, desc| "- `#{name}`: #{desc}" }.join("\n")
end

# === Chat creation and persistence methods ===
def create_chat(instructions: $state.instructions, tools: [EditFile, Bash, WebSearch, InnerEval], persist: $state.persist_chat)
  chat = RubyLLM::Chat.new(model: $state.model, provider: $state.provider)
  chat.with_instructions(instructions) if instructions
  chat.on_end_message do |msg|
    track_metrics(msg)
    save_state if persist
  end
  chat.with_tools(*tools)
end

def track_metrics(msg)
  return unless msg
  $state.session[:tokens_in] += msg.input_tokens.to_i
  $state.session[:tokens_out] += msg.output_tokens.to_i
  $state.session[:tokens_cached] += msg.cached_tokens.to_i
  $state.session[:messages] += 1
  $state.session[:tool_calls] += 1 if msg.tool_call?
end

def session_status
  s = $state.session
  "Session #{$state.current_chat_id}\nMessages: #{s[:messages]}, Tokens: #{s[:tokens_in]}/#{s[:tokens_out]}, Cache: #{s[:tokens_cached]}, Tools: #{s[:tool_calls]}, Model: #{$state.provider}/#{$state.model}"
end

def status_line
  model = $state.model
  branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
  tokens = ($state.session[:tokens_in] + $state.session[:tokens_out]) / 1000
  "[#{model} | #{branch} | #{tokens}k] ∂> "
end

def reset_session
  $state.session = {tokens_in: 0, tokens_out: 0, tokens_cached: 0, tool_calls: 0, messages: 0}
end

def save_state
  FileUtils.mkdir_p(".detritus/states")
  data = {
    id: $state.current_chat_id,
    model: $state.model,
    provider: $state.provider,
    messages: $state.chat.messages,
    session: $state.session,
    scratchpad: $state.scratchpad
  }
  File.write(".detritus/states/#{$state.current_chat_id}", Marshal.dump(data))
end

def load_state(id)
  file = ".detritus/states/#{id}"
  # Fallback to old chats dir for backward compatibility
  file = ".detritus/chats/#{id}" unless File.exist?(file)
  return nil unless File.exist?(file)

  data = Marshal.load(File.read(file))

  # Restore session metrics if they exist
  if data[:session]
    $state.session = data[:session]
    $state.model = data[:model]
    $state.provider = data[:provider]
    $state.scratchpad = data[:scratchpad]
  end

  create_chat(instructions: nil, persist: false).tap do |chat|
    data[:messages].each { |msg| chat.add_message(msg) }
    puts "[✓ State resumed: #{id} (#{data[:messages].size} messages)]"
  end
rescue => e
  puts "[✗ failed to load state: #{e.message}]"
  nil
end

# ===  Tools ===
class EditFile < RubyLLM::Tool
  description "Changes a specific block of text in a file. To avoid mistakes, the `old` block must appear exactly once in the file."
  param :path, required: true, desc: "The path to the file you want to edit."
  param :old, required: true, desc: "The EXACT lines of text you want to replace. If it appears multiple times, include surrounding lines to make it unique."
  param :new, required: true, desc: "The lines of text you want to use as replacement."
  param :create, type: :boolean, desc: "Optional flag to create the file if it doesn't exist."

  def execute(path: nil, old: nil, new: nil, create: false)
    missing = [(:path if path.nil?), (:old if old.nil?), (:new if new.nil?)].compact
    return {error: "Missing required parameters: #{missing.join(", ")}"} if missing.any?

    puts "\n{FileEdit path: #{path}}"

    FileUtils.touch(path) if create
    if (content = File.read(path).sub!(old, new))
      File.write(path, content)
      "ok"
    else
      {error: "<old> text not found in file. You might need to re-read the file"}
    end
  rescue => e
    {error: "#{e.class.name} - #{e.message}"}
  end
end

class Bash < RubyLLM::Tool
  description "Run shell command"
  param :command, desc: "Command"

  def execute(command: nil, **rest)
    return {error: "Missing required parameter: command"} if command.nil?
    puts "\n{Bash #{command[0..100]}...}"
    Bundler.with_unbundled_env { `#{command}` }
  rescue => e
    {error: e.message}
  end
end

class WebSearch < RubyLLM::Tool
  description "useful for searching the web"
  param :query, desc: "The search query", required: true

  def execute(query: nil)
    return {error: "Missing required parameter: query"} if query.nil?
    puts "{WebSearch query: #{query}}"

    @chat = RubyLLM.chat(model: "gemini-2.5-flash")
    @chat.with_params(tools: [{google_search: {}}])
    @chat.with_instructions("Use your web search capabilities to compile a comprehensive answer to the following query. Use as many searches as possible.")
    @chat.ask(query).content
  rescue => e
    {error: e.message}
  end
end

class InnerEval < RubyLLM::Tool
  description "Evaluates Ruby code within the agent's own runtime context. Enables introspection and manipulation of internal state. Give access to all the methods that make the agent work. The whole detritus code becomes a DSL to itself. Read detritus.rb to know it before creating the code to execute"
  param :code, desc: "Ruby code to execute", required: true

  def execute(code: nil)
    return {error: "Missing required parameter: code"} if code.nil?
    puts "{InnerEval #{code[0..100]}...}"
    result = eval(code, TOPLEVEL_BINDING)
    result.inspect
  rescue Exception => e
    {error: "#{e.class.name} - #{e.message}"}
  end
end

# === REPL ===
def handle_prompt(prompt)
  prompt = prompt.strip
  File.open($state.history_file, "a") { |f| f.puts prompt } # add message to history immediately

  case prompt
  when "/exit", "/quit"
    exit 0
  when "/new", "/clear"
    reset_session
    $state.chat = create_chat
    puts "\n[✓ context cleared]"
  when %r{^/load\s+(\w+)\s*(.*)}
    $state.chat.add_message(role: :user, content: prompt) if (prompt = build_prompt($1, $2))
    puts "[✓ #{$1} loaded]"
  when %r{^/resume\s+(.+)}
    $state.current_chat_id = $1
    $state.chat = load_state($1) || $state.chat
  when %r{^/resume\z}
    puts Dir.glob(".detritus/states/*").map { |f| File.basename(f) }
    puts Dir.glob(".detritus/chats/*").map { |f| File.basename(f) }
  when "/status"
    puts session_status
  when %r{^!(.+)\z}m
    puts(out = `#{$1}`)
    $state.chat.add_message(role: :user, content: "#{$1}\n\n#{out}")
  when %r{^/model\s+([^/]+)/(.+)}
    $state.provider = $1
    $state.model = $2
    $state.chat.with_model($state.model, provider: $state.provider)
    puts "[✓ Switched to #{$state.provider}/#{$state.model}]"
  when %r{^/(\w+)\s*(.*)}
    (rendered_prompt = build_prompt($1, $2)) && stream_response(rendered_prompt)
  else
    stream_response(prompt)
  end
end

def stream_response(prompt)
  $state.chat.ask(prompt) do |chunk|
    $stderr.print "\e[90m#{chunk.thinking.text}\e[0m" if chunk.thinking&.text
    print chunk.content if chunk.content&.strip
  end
rescue => e
  puts "\n[✗ Unexpected error: #{e.class} - #{e.message}]"
end

def configure(resume_id: nil)
  # === Configuration (global config combined with local project config) ===
  global_config = File.exist?(File.expand_path("~/.detritus/config.yml")) ? YAML.load_file(File.expand_path("~/.detritus/config.yml")) : {}
  local_config = File.exist?(".detritus/config.yml") ? YAML.load_file(".detritus/config.yml") : {}
  $state = OpenStruct.new((global_config || {}).merge(local_config || {}))

  system_prompt_name = ENV["DETRITUS_SYSTEM_PROMPT"] || "system"
  $state.instructions = File.read(find_prompt_file(system_prompt_name))
    .sub("%%{Dir.pwd}%%", Dir.pwd)
    .sub("%%{available_prompts}%%", available_prompts)
    .sub("%%{available_scripts}%%", available_scripts)
    .sub("%%{AGENTS.md}%%", (File.exist?("AGENTS.md") ? File.read("AGENTS.md") : ""))

  # === RubyLLM configuration ===
  RubyLLM.configure do |c|
    c.request_timeout = 600
    c.max_retries = 5
    c.retry_interval = 1
    c.retry_backoff_factor = 2
    c.retry_interval_randomness = 0.5
    case $state.provider
    when "anthropic" then c.anthropic_api_key = $state.api_key || ENV["ANTHROPIC_API_KEY"]
    when "ollama" then c.ollama_api_base = $state.api_base || "http://localhost:11434/v1"
    when "openai"
      c.openai_api_key = $state.api_key || ENV["OPENAI_API_KEY"] || "not-needed"
      c.openai_api_base = $state.api_base if $state.api_base
    end
    # Always configure Gemini for WebSearch tool
    c.gemini_api_key = ($state.provider == "gemini" && $state.api_key) ? $state.api_key : ENV["GEMINI_API_KEY"]
  end

  # === Readline History ====
  $state.history_file = File.expand_path(".detritus/history")
  FileUtils.mkdir_p(File.dirname($state.history_file))
  if File.exist?($state.history_file)
    File.readlines($state.history_file).each { |line| Reline::HISTORY << line.chomp }
  end

  # === Initial State Setup ===
  $state.persist_chat = !ENV["DETRITUS_NO_PERSIST"]
  reset_session

  if resume_id
    $state.current_chat_id = resume_id
    $state.chat = load_state(resume_id)
  end

  # Fallback if no resume_id or resume failed
  unless $state.chat
    $state.current_chat_id = Time.now.strftime("%Y%m%d_%H%M%S")
    $state.chat = create_chat
  end
end

# Check for resume flag in ARGV
resume_idx = ARGV.find_index("--resume")
resume_id = resume_idx ? ARGV.delete_at(resume_idx + 1) : nil
ARGV.delete("--resume") if resume_idx

configure(resume_id: resume_id)
return if ENV["DETRITUS_TEST"]

if ARGV.first ## non-interactive mode
  handle_prompt(ARGV.join(" "))
else
  loop do # Interactive REPL
    input = Reline.readline(status_line, true)
    if input.nil? # Ctrl+D to exit
      puts "[✓ Bye!]"
      break
    end
    next if input.empty?
    handle_prompt(input)
  rescue Interrupt
    # Silently handle Ctrl+C
  rescue => e
    puts "\n[✗ Error: #{e.class} - #{e.message}]"
  end
end
