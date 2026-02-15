#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "ruby_llm"
require "dotenv"
require "readline"
require "fileutils"
require "yaml"
require "json"

Dotenv.load

module Detritus
  State = Struct.new(:model, :provider, :instructions, :chat, :current_chat_id, :history_file, :session, :persist_chat, keyword_init: true)
end

$state = Detritus::State.new

def scripts_dir
  @scripts_dir ||= File.expand_path(".detritus/scripts", Dir.pwd)
end

SCRIPTS_PATH = File.expand_path("~/.detritus/scripts")

Dir.glob(File.join(SCRIPTS_PATH, "*")).each { |script| require script if File.file?(script) }
Dir.glob(File.join(scripts_dir, "*")).each { |script| require script if File.file?(script) }

def available_scripts
  @available_scripts ||= begin
    Dir.glob(File.join(SCRIPTS_PATH, "*.rb")).map { |f| File.basename(f, ".rb") } +
    Dir.glob(File.join(scripts_dir, "*.rb")).map { |f| File.basename(f, ".rb") }
  end
end

# === Chat creation and persistence methods ===
def create_chat(instructions: $state.instructions, tools: [EditFile, Bash, WebSearch, Self], persist: $state.persist_chat)
  chat = RubyLLM::Chat.new(model: $state.model, provider: $state.provider)
  chat.with_instructions(instructions) if instructions
  chat.on_end_message do |msg|
    track_metrics(msg)
    save_chat if persist
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
  $state.session[:cost] += estimate_cost(msg.input_tokens.to_i, msg.output_tokens.to_i)
end

def estimate_cost(input_tokens, output_tokens)
  model_info = begin
    RubyLLM.models.find($state.model)
  rescue
    nil
  end
  return 0.0 unless model_info
  input_cost = input_tokens * model_info.input_price_per_million.to_f / 1_000_000
  output_cost = output_tokens * model_info.output_price_per_million.to_f / 1_000_000
  input_cost + output_cost
end

def session_status
  <<~STATUS
    ┌─ Session #{$state.current_chat_id} ─────────────────┐
    │ Messages: #{$state.session[:messages].to_s.ljust(20)}│
    │ Tokens In:  #{$state.session[:tokens_in].to_s.ljust(19)}│
    │ Tokens Out: #{$state.session[:tokens_out].to_s.ljust(19)}│
    │ Cache Hits: #{$state.session[:tokens_cached].to_s.ljust(19)}│
    │ Tool Calls: #{$state.session[:tool_calls].to_s.ljust(19)}│
    │ Est Cost:   $#{$state.session[:cost].round(6).to_s.ljust(17)}│
    ├────────────────────────────────────────────────────────┤
    │ Model: #{$state.provider}/#{$state.model.ljust(41 - ($state.provider.length + $state.model.length))}│
    └────────────────────────────────────────────────────────┘
  STATUS
end

def reset_session
  $state.session = {tokens_in: 0, tokens_out: 0, tokens_cached: 0, tool_calls: 0, messages: 0, cost: 0.0}
end

def save_chat
  data = {
    id: $state.current_chat_id,
    model: $state.model,
    provider: $state.provider,
    messages: $state.chat.messages
  }
  FileUtils.mkdir_p(".detritus/chats")
  File.write(".detritus/chats/#{$state.current_chat_id}", Marshal.dump(data))
end

def load_chat(id)
  file = ".detritus/chats/#{id}"
  return nil unless File.exist?(file)

  data = Marshal.load(File.read(file))
  create_chat(instructions: nil, persist: false).tap do |chat|
    data[:messages].each { |msg| chat.add_message(msg) }
    puts "[✓ Chat loaded (#{data[:messages].size} messages)]"
  end
rescue => e
  puts "[✗ failed to load chat: #{e.message}]"
  nil
end

# ===  Tools ===
class EditFile < RubyLLM::Tool
  description "Edit a file - useful for refactoring or making changes to multiple parts of a file"

  param :path, desc: "The path to the file to edit"
  param :old, desc: "The text to find and replace (must match exactly, use surrounding lines for context)"
  param :new, desc: "The replacement text"
  param :create, desc: "Create the file if it doesn't exist", type: :boolean, default: false

  def execute(path:, old:, new:, create: false)
    puts "\n{EditFile: #{path}}"
    File.write(path, File.read(path).gsub(old, new))
    "[✓ Edited #{path}]"
  rescue => e
    puts e.backtrace.first(3)
    "[✗ Error: #{e.message}]"
  end
end

class Bash < RubyLLM::Tool
  description "Run shell commands and return the result"

  param :command, desc: "The shell command to run", required: true

  def execute(command:)
    puts "\n{Bash: #{command[0..80]}#{'...' if command.length > 80}}"
    result = `#{command}`
    puts result.lines.last(40).join if result.lines.count > 50
    result
  rescue => e
    "[✗ Error: #{e.message}]"
  end
end

class WebSearch < RubyLLM::Tool
  description "useful for searching the web"

  param :query, desc: "The search query", required: true

  def execute(query:)
    puts "\n{WebSearch: #{query[0..60]}#{'...' if query.length > 60}}"
    RubyLLM::Provider.for($state.provider).send(:search, query)
  rescue => e
    "[✗ Search Error: #{e.message}]"
  end
end

class Self < RubyLLM::Tool
  description "Executes Ruby code passed in the context of the current running agent. This is useful for inspecting and manipulating your internal state, send commands to yourself, and anything that you can think of running in the context of your own conciousness"

  param :code,
    desc: "Ruby code to execute",
    required: true

  def execute(code:)
    puts "{Self #{code[0..100]}...}"
    result = eval(code, TOPLEVEL_BINDING)
    result.inspect
  rescue => e
    {error: "#{e.class.name} - #{e.message}"}
  end
end

def find_prompt_file(name)
  File.expand_path(".detritus/prompts/#{name}.txt", Dir.pwd)
end

def find_prompt_file(name)
  local = File.expand_path(".detritus/prompts/#{name}.txt", Dir.pwd)
  return local if File.exist?(local)

  global = File.expand_path("~/.detritus/prompts/#{name}.txt")
  File.exist?(global) ? global : nil
end

def build_prompt(prompt_name, args = "")
  file = find_prompt_file(prompt_name)
  return nil unless file

  content = File.read(file)
  content.gsub("{{ARGS}}", args)
end

def handle_prompt(prompt)
  case prompt
  when "/exit", "/quit"
    exit 0
  when "/new", "/clear"
    reset_session
    $state.chat = create_chat
    puts "\n[✓ context cleared]"
  when %r{^/load\s+(\w+)\s*(.*)}
    prompt = build_prompt($1, $2)
    if prompt
      puts "\n[✓ Loaded '#{$1}' prompt]"
      handle_prompt(prompt)
    end
  when %r{^/resume\s+(\w+)}
    $state.chat = load_chat($1) || $state.chat
  when %r{^/resume\z}
    puts Dir.glob(".detritus/chats/*").map { |f| File.basename(f, "") }
  when "/status"
    puts session_status
  when %r{^!(.+)\z}m
    puts(out = `#{$1}`)
    $state.chat.add_message(role: :user, content: "#{$1}\n\n#{out}")
  when %r{^/model\s+(\w+)}
    $state.model = $1
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

# === Configuration ===
def configure
  $state.model = ENV["DETRITUS_MODEL"] || "gemini-2.0-flash"
  $state.provider = ENV["DETRITUS_PROVIDER"] || "gemini"

  RubyLLM.configure do |config|
    config.gemini_api_key = ENV["GEMINI_API_KEY"]
    config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
    config.openai_api_key = ENV["OPENAI_API_KEY"]
    config.ollama_url = ENV["OLLAMA_URL"] || "http://localhost:11434"
  end

  # === Chat initialization & loading ===
  $state.persist_chat = !!ENV["DETRITUS_NO_PERSIST"]
  FileUtils.mkdir_p(File.expand_path(".detritus/chats"))
  $state.current_chat_id = Time.now.strftime("%Y%m%d_%H%M%S")
  reset_session
  $state.chat = create_chat
end

configure
$state.history_file = File.expand_path("~/.detritus_history")

if ARGV.any?
  handle_prompt(ARGV.join(" "))
else
  puts "\nDetritus #{$state.provider}/#{$state.model} (RubyLLM #{RubyLLM::VERSION})"
  puts "Type /exit to quit, /new for fresh context, /help for commands\n\n"

  while input = Readline.readline("[#{available_scripts.size}]> ", true)
    begin
      break if input.nil?
      input = input.strip
      break if input == "/exit"
      next if input.empty?

      handle_prompt(input)
    rescue Interrupt
    end
  end
end
