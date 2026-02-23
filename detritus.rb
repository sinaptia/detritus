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


def find_script(name) = find_resources("scripts", name).find { |path| File.executable?(path) }
def find_skill(name) = find_resources("skills", "#{name}/SKILL.md").first


def available_scripts
  find_resources("scripts", "*")
    .select { |path| File.executable?(path) && File.file?(path) }
    .map { |file| [file, `#{file} --help 2>&1`.lines.first&.strip || "No description available"] }
    .to_h
    .map { |name, desc| "- `#{name}`: #{desc}" }.join("\n")
end

def list_skills
  find_resources("skills", "*/SKILL.md")
    .reject { |path| File.basename(File.dirname(path)) == "system" }
    .map do |path|
      content = File.read(path)
      frontmatter = if content =~ /\A---+\s*\n(.*?)\n---+\s*\n/m
        YAML.safe_load($1) || {}
      else
        {}
      end
      name = frontmatter["name"] || File.basename(File.dirname(path))
      description = frontmatter["description"] || ""
      [name, description]
    end
    .map { |name, desc| "- `#{name}`: #{desc}" }.join("\n")
end

# === Chat creation and persistence methods ===
def create_chat(instructions: $state.instructions, tools: [EditFile, Bash, LoadSkill, Reflect], persist: $state.persist_chat)
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
  $state.session[:tokens_in] = msg.input_tokens.to_i
  $state.session[:tokens_out] = msg.output_tokens.to_i
  $state.session[:tokens_cached] = msg.cached_tokens.to_i
  $state.session[:accumulated_tokens_in] += msg.input_tokens.to_i
  $state.session[:accumulated_tokens_out] += msg.output_tokens.to_i
  $state.session[:messages] += 1
  $state.session[:tool_calls] += 1 if msg.tool_call?
end

def status_line
  total = $state.chat.messages.sum { |msg| (msg.input_tokens || 0) + (msg.output_tokens || 0) }
  current_in = ($state.session[:tokens_in].to_f / 1000).round(1)
  current_out = ($state.session[:tokens_out].to_f / 1000).round(1)
  "[#{$state.model} | #{`git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip} | #{$state.session[:messages]} - #{$state.session[:tool_calls]} | #{(total / 1000.0).round(1)}K (#{current_in}/#{current_out})] > "
end

def reset_session
  $state.session = {tokens_in: 0, tokens_out: 0, tokens_cached: 0, accumulated_tokens_in: 0, accumulated_tokens_out: 0, tool_calls: 0, messages: 0}
end

def save_state
  FileUtils.mkdir_p(".detritus/states")
  data = {
    id: $state.current_chat_id,
    model: $state.model,
    provider: $state.provider,
    messages: $state.chat.messages,
    session: $state.session
  }
  File.write(".detritus/states/#{$state.current_chat_id}", Marshal.dump(data))
end

def load_state(id)
  file = ".detritus/states/#{id}"
  return nil unless File.exist?(file)

  data = Marshal.load(File.read(file))

  # Restore session metrics if they exist
  if data[:session]
    $state.session = data[:session]
    $state.model = data[:model]
    $state.provider = data[:provider]
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

class LoadSkill < RubyLLM::Tool
  description "Loads a skill from a SKILL.md file with YAML frontmatter. Skills follow the cascade: local .detritus/skills/ takes precedence over global ~/.detritus/skills/. The skill body has variables interpolated: $ARGUMENTS (all args), $1, $2, etc (positional args)."
  param :name, desc: "Name of the skill to load (e.g., 'research', 'todo')", required: true
  param :arguments, desc: "Arguments for interpolation, space-separated (e.g., 'arg1 arg2')"

  def execute(name: nil, arguments: "")
    return {error: "Missing required parameter: name"} if name.nil?

    skill_file = find_skill(name)
    return {error: "Skill '#{name}' not found"} unless skill_file

    content = File.read(skill_file)
    
    # Parse YAML frontmatter and body
    if content =~ /\A---+\s*\n(.*?)\n---+\s*\n(.*)\z/m
      frontmatter = YAML.safe_load($1) || {}
      body = $2
    else
      frontmatter = {}
      body = content
    end

    # Interpolate arguments
    args = arguments.to_s.strip.split(/\s+/)
    interpolated = body.gsub("$ARGUMENTS", arguments.to_s)
    args.each_with_index do |arg, i|
      interpolated = interpolated.gsub("$#{i + 1}", arg)
    end

    {
      name: frontmatter["name"] || name,
      description: frontmatter["description"] || "",
      trigger: frontmatter["trigger"] || "",
      type: frontmatter["type"] || "prompt",
      body: interpolated
    }
  rescue => e
    {error: "#{e.class.name} - #{e.message}"}
  end
end

class Reflect < RubyLLM::Tool
  param :code, desc: "Ruby code to execute", required: true
  description "Evaluates Ruby code within the agent's own runtime context. Enables: introspection and manipulation of internal state, sending commands to yourself, manipulating the context window. You can think if detritus.rb as a DSL to itself. Ensure to read detritus.rb before creating the code to execute"

  def execute(code: nil)
    return {error: "Missing required parameter: code"} if code.nil?
    puts "{Reflect #{code[0..100]}...}"
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
  when "/new", "/clear"
    reset_session
    $state.chat = create_chat
    puts "\n[✓ context cleared]"
  when %r{^/resume\s+(.+)}
    $state.current_chat_id = $1
    $state.chat = load_state($1) || $state.chat
  when %r{^!(.+)\z}m
    puts(out = `#{$1}`)
    $state.chat.add_message(role: :user, content: "#{$1}\n\n#{out}")
  when %r{^/model\s+([^/]+)/(.+)}
    $state.provider = $1
    $state.model = $2
    $state.chat.with_model($state.model, provider: $state.provider)
    puts "[✓ Switched to #{$state.provider}/#{$state.model}]"
  else
    stream_response(prompt)
  end
end

def stream_response(prompt)
  $state.chat.ask(prompt) do |chunk|
    $stderr.print "\e[90m#{chunk.thinking.text}\e[0m" if chunk.thinking&.text
    print chunk.content if chunk.content&.strip
  end
  puts
rescue => e
  puts "\n[✗ Unexpected error: #{e.class} - #{e.message}]"
end

def configure(resume_id: nil)
  # === Configuration (global config combined with local project config) ===
  global_config = File.exist?(File.expand_path("~/.detritus/config.yml")) ? YAML.load_file(File.expand_path("~/.detritus/config.yml")) : {}
  local_config = File.exist?(".detritus/config.yml") ? YAML.load_file(".detritus/config.yml") : {}
  $state = OpenStruct.new((global_config || {}).merge(local_config || {}))

  $state.instructions = File.read(find_skill("system"))
    .sub("%%{Dir.pwd}%%", Dir.pwd)
    .sub("%%{available_prompts}%%", list_skills)
    .sub("%%{available_scripts}%%", available_scripts)
    .sub("%%{AGENTS.md}%%", (File.exist?("AGENTS.md") ? File.read("AGENTS.md") : ""))

  # === RubyLLM configuration ===
  RubyLLM.configure do |c|
    case $state.provider
    when "anthropic" then c.anthropic_api_key = $state.api_key || ENV["ANTHROPIC_API_KEY"]
    when "ollama" then c.ollama_api_base = $state.api_base || "http://localhost:11434/v1"
    when "openai"
      c.openai_api_key = $state.api_key || ENV["OPENAI_API_KEY"] || "not-needed"
      c.openai_api_base = $state.api_base if $state.api_base
    end
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
  $state.current_chat_id = Time.now.strftime("%Y%m%d_%H%M%S")
  $state.chat = create_chat
  $state.chat.with_tool(LoadSkill)
end

configure
return if ENV["DETRITUS_TEST"]

if ARGV.first ## non-interactive mode
  handle_prompt(ARGV.join(" "))
else
  loop do # Interactive REPL
    input = Reline.readline(status_line, true)
    break if input.nil? # Ctrl+D to exit
    next if input.empty?
    handle_prompt(input)
  rescue => e
    puts "\n[✗ Error: #{e.class} - #{e.message}]"
    next
  rescue Interrupt
  end
  puts "[✓ Bye!]"
end
