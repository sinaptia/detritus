#!/usr/bin/env ruby
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "ruby_llm", "~> 1.13"
  gem "reline"
  gem "ostruct"
  gem "yaml"
  gem "json"
  gem "fileutils"
  gem "set"
  gem "tempfile"
  gem "securerandom"
end

# ===  Skills  ===
def find_skills(name)
  [".detritus/skills", "#{ENV["HOME"]}/.detritus/skills"]
    .flat_map { |dir| Dir.glob(File.join(File.expand_path(dir), "#{name}/SKILL.md")) }
    .uniq { |path| File.basename(File.dirname(path)) }
end

def list_skills
  find_skills("*")
    .reject { |path| File.basename(File.dirname(path)) == "system" }
    .map do |path|
      content = File.read(path)
      frontmatter = YAML.safe_load($1) || {} if content =~ /\A---+\s*\n(.*?)\n---+\s*\n/m
      frontmatter ||= {}
      "- #{File.basename(File.dirname(path))}: #{frontmatter["description"]}"
    end.join("\n")
end

# === Chat creation and persistence methods ===
def create_chat(instructions: $state.instructions, tools: [EditFile, Bash, LoadSkill, InstanceEval, AttachFile], persist: $state.persist_chat)
  chat = RubyLLM::Chat.new(model: $state.model, provider: $state.provider)
  chat.with_instructions(instructions) if instructions
  chat.on_end_message do |msg|
    track_metrics(msg)
    save_state if persist
    compact_conversation
  end
  chat.on_tool_result { $stderr.print "\n#{status_line}\n" }
  chat.with_tools(*tools)
end

def track_metrics(msg)
  return unless msg
  $state.session[:tokens_in] = msg.input_tokens.to_i
  $state.session[:tokens_out] = msg.output_tokens.to_i
  $state.session[:tokens] = $state.session[:tokens_in] + $state.session[:tokens_out]
  $state.session[:tokens_cached] = msg.cached_tokens.to_i
  $state.session[:accumulated_tokens_in] += msg.input_tokens.to_i
  $state.session[:accumulated_tokens_out] += msg.output_tokens.to_i
  $state.session[:accumulated_tokens_cached] += msg.cached_tokens.to_i
end

def status_line = "#{$state.model} [#{($state.session[:tokens].to_f / 1000.0).round(1)}K]"

# ===  Context Compaction  ===
def compact_conversation(focus: nil)
  return false unless $state.compaction
  return false unless $state.compaction.fetch("enabled", false)
  return false unless $state.chat.messages.count > $state.compaction.fetch("keep_message_count", 6)
  return false unless $state.session[:tokens] >= $state.compaction.fetch("trigger_tokens", 80_000)

  archive_message_range = (2...-$state.compaction.fetch("keep_message_count", 6))

  messages = $state.chat.messages.map { |m| "[#{m.role}]: #{m.content}" }[archive_message_range]

  instructions = LoadSkill.new.execute(name: "compact")
  raise "Compact skill not found" if instructions.is_a?(Hash)
  instructions += "\n\nFocus: #{focus}" if focus

  prompt = "#{instructions}\n\n#{messages.join("\n")}"
  compactor = RubyLLM.chat(model: $state.model, provider: $state.provider, assume_model_exists: true)
  summary = compactor.ask(prompt).content

  archive_path = ".detritus/archive/#{SecureRandom.uuid}"
  FileUtils.mkdir_p(".detritus/archive")
  File.write(archive_path, Marshal.dump({
    messages: messages,
    timestamp: Time.now,
    chat_id: $state.current_chat_id
  }))

  $state.chat.messages[archive_message_range] = RubyLLM::Message.new(role: :system, content: "## Previous context\n\n#{summary}\n\nArchive: `#{archive_path}`")
  $state.session[:tokens_in] = $state.session[:tokens_out] = $state.session[:tokens] = 0
  $stderr.puts "[✓ Compacted ]"
  true
end

def reset_session
  $state.session = {tokens_in: 0, tokens_out: 0, tokens_cached: 0, accumulated_tokens_in: 0, accumulated_tokens_out: 0, accumulated_tokens_cached: 0, tool_calls: 0, messages: 0}
end

def save_state
  FileUtils.mkdir_p(".detritus/states")
  data = {
    id: $state.current_chat_id,
    model: $state.model,
    provider: $state.provider,
    messages: $state.chat.messages
      .select { |m| m.content || m.tool_calls }
      .map { |m| {role: m.role.to_s, content: m.content, tool_calls: m.tool_calls} },
    session: $state.session
  }
  File.write(".detritus/states/#{$state.current_chat_id}", Marshal.dump(data), mode: "wb")
end

def load_state(id)
  file = ".detritus/states/#{id}"
  return nil unless File.exist?(file)

  data = Marshal.load(File.read(file))

  $state.session = data[:session] || reset_session
  $state.model = data[:model]
  $state.provider = data[:provider]

  chat = create_chat(instructions: nil, persist: false)

  # Restore messages - support both :messages (new) and :conversation (old)
  raw_messages = data[:messages] || []
  raw_messages.each do |m|
    puts "#{m[:role]}: #{m[:content]}"
    chat.add_message(role: m[:role], content: m[:content], tool_calls: m[:tool_calls])
  end
  $state.current_chat_id = id
  $stderr.puts "[✓ State resumed: #{id} (#{chat.messages.size} messages)]"
  chat
rescue => e
  $stderr.puts "[✗ Failed to load state: #{e.class.name} - #{e.message} : #{e.backtrace.first}]"
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

    $stderr.puts "\n{FileEdit path: #{path}}"

    FileUtils.touch(path) if create
    file_content = File.read(path)
    if file_content.include?(old)
      $stderr.puts diff(old, new)
      content = file_content.sub(old, new)
      File.write(path, content)
      "ok"
    else
      {error: "<old> text not found in file. You might need to re-read the file"}
    end
  rescue => e
    {error: "#{e.class.name} - #{e.message}"}
  end

  def diff(old, new)
    old_file = Tempfile.new("old")
    old_file.write(old)
    old_file.close
    new_file = Tempfile.new("new")
    new_file.write(new)
    new_file.close
    output = `diff --color=always -u -U 3 #{old_file.path} #{new_file.path} 2>/dev/null || true`
    output.empty? ? "\e[33m~ (no changes)\e[0m" : output.lines[3..].reject { |line| line.include?("No newline at end of file") }.join
  ensure
    old_file.unlink
    new_file.unlink
  end
end

class Bash < RubyLLM::Tool
  description "Run shell command"
  param :command, desc: "Command"

  def execute(command: nil, **rest)
    return {error: "Missing required parameter: command"} if command.nil? || command.empty?
    $stderr.puts "\n{Bash #{command[0..100]}...}"
    require "open3"
    stdout, stderr, status = Bundler.with_unbundled_env { Open3.capture3(command) }
    return {error: "Exit code #{status.exitstatus}", stderr: stderr} unless status.success?
    stdout.to_s
  rescue => e
    {error: e.message}
  end
end

class LoadSkill < RubyLLM::Tool
  description "Loads a skill from a SKILL.md file with YAML frontmatter. Skills follow the cascade: local .detritus/skills/ takes precedence over global ~/.detritus/skills/. The skill body has variables interpolated: $ARGUMENTS (all args), $1, $2, etc (positional args)."
  param :name, desc: "Name of the skill to load (e.g., 'research', 'todo')", required: true
  param :arguments, desc: "Arguments for interpolation, space-separated (e.g., 'arg1 arg2')"

  def execute(name: nil, arguments: "")
    return {error: "Missing required parameter: name"} if name.nil? || name.empty?

    skill_file = find_skills(name).last
    return {error: "Skill '#{name}' not found"} unless skill_file
    _, frontmatter, body = File.read(skill_file).split("---", 3)
    return {error: "Invalid skill file format"} if body.nil? || body.empty? || frontmatter.nil? || frontmatter.empty?

    interpolated = body.strip.gsub("$ARGUMENTS", arguments.to_s)
    interpolated = interpolated.gsub(/!`([^`]+)`/) { |_match| Bundler.with_unbundled_env { `#{$1}`.chomp } }

    args = arguments.to_s.strip.split(/\s+/)
    args.each_with_index do |arg, i|
      interpolated = interpolated.gsub("$#{i + 1}", arg)
    end
    $stderr.puts "\n{LoadSkill #{name} #{arguments[0..100]}}" unless ENV["DETRITUS_TEST"]
    interpolated
  rescue => e
    {error: "#{e.class.name} - #{e.message}"}
  end
end

class InstanceEval < RubyLLM::Tool
  param :code, desc: "Ruby code to execute", required: true
  description "Evaluates Ruby code within the agent's own runtime context. Enables: introspection and manipulation of internal state, sending commands to yourself, manipulating the context window. You can think if detritus.rb as a DSL to itself. Ensure to read detritus.rb before creating the code to execute"

  def execute(code: nil)
    return {error: "Missing required parameter: code"} if code.nil?
    $stderr.puts "{InstanceEval #{code[0..100]}...}"
    result = eval(code, TOPLEVEL_BINDING)
    result.inspect
  rescue Exception => e
    {error: "#{e.class.name} - #{e.message}"}
  end
end

class AttachFile < RubyLLM::Tool
  description "Attach files: adds files as an attachment to the next message sent to the llm. useful for pdf, images and other binary data"
  param :path, desc: "Path", required: true
  def execute(path: nil)
    return {error: "File Not Found: #{path} doesn't exist?"} unless path && File.exist?(path)
    $state.files << path
    "ok"
  end
end

# === REPL ===
def handle_prompt(prompt)
  prompt = prompt.strip
  File.open($state.history_file, "a") { |f| f.puts prompt } # add message to history immediately

  case prompt
  when "/new", "/clear"
    reset_session
    $state.files = Set.new
    $state.chat = create_chat
    $stderr.puts "\n[✓ context cleared]"
  when %r{^/attach\s+(.+)}
    $state.files << $1.strip
    $stderr.puts "[✓ #{$1.strip}]"
  when /^\/compact\s*(.*)/
    compact_conversation focus: $1&.strip
  when "/scrub"
    if $state.chat.messages.any?
      $state.chat.messages.pop
      save_state if $state.persist_chat
      $stderr.puts "[✓ Last message scrubbed]"
    else
      $stderr.puts "[! No messages to scrub]"
    end
  when %r{^/resume\s+(.+)}
    $state.chat = load_state($1) || $state.chat
  when %r{^!(.+)\z}m
    puts(out = `#{$1}`)
    $state.chat.add_message(role: :user, content: "#{$1}\n\n#{out}")
  when %r{^/model\s+([^/]+)/(.+)}
    $state.provider = $1
    $state.model = $2
    $state.chat.with_model($state.model, provider: $state.provider)
    $stderr.puts "[✓ Switched to #{$state.provider}/#{$state.model}]"
  when %r{^/([\w-]+)\s*(.*)}
    rendered_prompt = LoadSkill.new.execute(name: $1, arguments: $2)
    complete(rendered_prompt) if rendered_prompt
  else
    complete(prompt)
  end
end

def complete(prompt)
  if $state.files&.any?
    $state.chat.add_message(role: :user, content: RubyLLM::Content.new(prompt, $state.files.to_a))
    $state.files = Set.new
  else
    $state.chat.add_message(role: :user, content: prompt)
  end

  $state.chat.complete do |chunk|
    $stderr.print "\e[90m#{chunk.thinking.text}\e[0m" if chunk.thinking&.text
    print chunk.content if chunk.content&.strip
  end
  puts
rescue TypeError => e
  $stderr.puts "\n[⚠ Streaming error (provider issue): #{e.message}]"
rescue => e
  $stderr.puts "\n[✗ Unexpected error: #{e.class} - #{e.message} : #{e.backtrace.first}]"
ensure
  $stderr.print "\a" if $state.use_terminal_bell
end

# === Configuration (global config combined with local project config) ===
def configure(resume_id: nil)
  global_config = File.exist?(File.expand_path("~/.detritus/config.yml")) ? YAML.load_file(File.expand_path("~/.detritus/config.yml")) : {}
  local_config = File.exist?(".detritus/config.yml") ? YAML.load_file(".detritus/config.yml") : {}
  $state = OpenStruct.new({}.merge((global_config || {})).merge((local_config || {})))
  $state.files = Set.new

  # Load system skill with proper interpolation
  system_skill_content = LoadSkill.new.execute(name: "system")
  raise "System skill not found" if system_skill_content.is_a?(Hash) && system_skill_content[:error]
  $state.instructions = system_skill_content.gsub("%%{list_skills}%%", list_skills)

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
  # Disable auto-compaction if compact skill not available
  if $state.compaction && find_skills("compact").empty?
    $stderr.puts "[⚠ Auto-compaction disabled: compact skill not found]"
    $state.compaction["enabled"] = false
  end
  
  $state.persist_chat = !ENV["DETRITUS_NO_PERSIST"]
  reset_session
  $state.current_chat_id = Time.now.strftime("%Y%m%d_%H%M%S")
  $state.chat = create_chat
end

configure
return if ENV["DETRITUS_TEST"]

if ARGV.first ## non-interactive mode
  $state.mode = :non_interactive
  handle_prompt(ARGV.join(" "))
else
  $state.mode = :interactive
  loop do # Interactive REPL
    pwd = ENV["HOST_PWD"] ? File.basename(ENV["HOST_PWD"]) : Dir.pwd
    branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
    input = Reline.readline("#{status_line} #{pwd} (#{branch}) -> ", true)
    break if input.nil? # Ctrl+D to exit
    next if input.empty?
    handle_prompt(input)
  rescue => e
    $stderr.puts "\n[✗ Error: #{e.class} - #{e.message} : #{e.backtrace.first}]"
    next
  rescue Interrupt
  end
  $stderr.puts "[✓ Bye!]"
end
