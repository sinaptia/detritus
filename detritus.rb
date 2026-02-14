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
def create_chat(instructions: $state.instructions, tools: [EditFile, Bash, WebSearch, Self], persist: $state.persist_chat)
  chat = RubyLLM::Chat.new(model: $state.model, provider: $state.provider)
  chat.with_instructions(instructions) if instructions
  chat.on_end_message { |msg| save_chat } if persist
  chat.with_tools(*tools)
end

def save_chat
  data = {
    id: $state.current_chat_id,
    model: $state.model,
    provider: $state.provider,
    messages: $state.chat.messages.map(&:to_h)
  }

  File.write(".detritus/chats/#{$state.current_chat_id}.yml", YAML.dump(data))
end

def load_chat(id)
  file = ".detritus/chats/#{id}.yml"
  return nil unless File.exist?(file)

  data = YAML.unsafe_load(File.read(file))
  create_chat(instructions: nil).tap do |chat|
    data[:messages].each do |message|
      message[:tool_calls]&.transform_values! { |tc| RubyLLM::ToolCall.new(**tc) }
      chat.add_message(RubyLLM::Message.new(message))
    end
    puts "[✓ Chat loaded (#{data[:messages].size} messages)]"
  end
rescue => e
  puts "[✗ Failed to load chat: #{e.message}]"
end

# ===  Tools ===
class EditFile < RubyLLM::Tool
  description "Changes a specific block of text in a file. To avoid mistakes, the `old` block must appear exactly once in the file."
  param :path, required: true, desc: "The path to the file you want to edit."
  param :old, required: true, desc: "The EXACT lines of text you want to replace. If it appears multiple times, include surrounding lines to make it unique."
  param :new, required: true, desc: "The lines of text you want to use as replacement."
  param :create, type: :boolean, desc: "Optional flag to create the file if it doesn't exist."

  def execute(path:, old:, new:, create: false)
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

  def execute(command:)
    puts "\n{Bash #{command[0..100]}...}"
    Bundler.with_unbundled_env { `#{command}` }
  rescue => e
    {error: e.message}
  end
end

class WebSearch < RubyLLM::Tool
  description "useful for searching the web"

  param :query,
    desc: "The search query",
    required: true

  def execute(query:)
    puts "{WebSearch query: #{query}}"

    @chat = RubyLLM.chat(model: "gemini-2.5-flash")
    @chat.with_params(tools: [{google_search: {}}])
    @chat.with_instructions(<<~PROMPT)
      Use your web search capabilities to compile a comprehensive answer to the following query. Use as many searches as possible.
    PROMPT

    @chat.ask(query).content
  rescue => e
    {error: e.message}
  end
end

class Self < RubyLLM::Tool
  description "Executes Ruby code passed in the context of the current running agent. This is useful for inspecting and manipulating your internal state, send commands to yourself, and anything that you can think of running in the context of your own conciousness"

  param :code, desc: "Ruby code to execute", required: true

  def execute(code:)
    puts "{Self #{code[0..100]}...}"
    result = eval(code, TOPLEVEL_BINDING)
    result.inspect
  rescue => e
    {error: e.message, backtrace: e.backtrace.first(3)}
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
    $state.chat = create_chat
    puts "\n[✓ context cleared]"
  when %r{^/load\s+(\w+)\s*(.*)}
    $state.chat.add_message(role: :user, content: prompt) if (prompt = build_prompt($1, $2))
    puts "[✓ #{$1} loaded]"
  when %r{^/resume\s+(.+)}
    $state.current_chat_id = $1
    $state.chat = load_chat($1) || $state.chat
  when %r{^/resume\z}
    puts Dir.glob(".detritus/chats/*").map { |f| File.basename(f, "") }
  when %r{^!(.+)\z}m
    puts(out = `#{$1}`)
    $state.chat.add_message(role: :user, content: "#{$1}\n\n#{out}")
  when %r{^/model\s+([^/]+)/(.+)}
    $state.provider = $1
    $state.model = $2
    $state.chat.with_model($state.model, provider: $state.provider)
    puts "[✓ Switched to #{$state.provider}/#{$state.model}]"
  when %r{^/(\w+)\s*(.*)}
    $state.chat.ask(prompt) if (prompt = build_prompt($1, $2))
  else
    $state.chat.ask(prompt) do |chunk|
      print "\e[90m#{chunk.thinking.text}\e[0m" if chunk.thinking&.text
      print chunk.content if chunk.content&.strip
    end
    puts
  end
end

def configure
  # === Configuration (global config combined with local project config) ===
  global_config = File.exist?(File.expand_path("~/.detritus/config.yml")) ? YAML.load_file(File.expand_path("~/.detritus/config.yml")) : {}
  local_config = File.exist?(".detritus/config.yml") ? YAML.load_file(".detritus/config.yml") : {}
  $state = OpenStruct.new((global_config || {}).merge(local_config || {}))
  $state.instructions = File.read(find_prompt_file("system.txt"))
    .sub("%%{Dir.pwd}%%", Dir.pwd)
    .sub("%%{available_prompts}%%", available_prompts)
    .sub("%%{available_scripts}%%", available_scripts)

  # === RubyLLM configuration ===
  RubyLLM.configure do |c|
    c.request_timeout = 600
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

  # === Chat initialization & loading ===
  FileUtils.mkdir_p(File.expand_path(".detritus/chats"))
  $state.current_chat_id = Time.now.strftime("%Y%m%d_%H%M%S")
  $state.chat = create_chat
end

configure
return if ENV["DETRITUS_TEST"]

if ARGV.first ## non-interactive mode
  handle_prompt(ARGV.join(" "))
else
  loop do # Interactive REPL
    input = Reline.readline("> ", true)
    if input.nil? # Ctrl+D to exit
      puts "[✓ Bye!]"
      break
    end
    next if input.empty?

    handle_prompt(input)
  rescue Interrupt
  end
end
