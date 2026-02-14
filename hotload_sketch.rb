#!/usr/bin/env ruby
# Hotloading approach for detritus.rb

# === FIRST LOAD ONLY ===
if !defined?(HOTLOADED)
  require "bundler/inline"
  gemfile do
    source "https://rubygems.org"
    gem "ruby_llm", "~> 1.11"
    # ... etc
  end
  HOTLOADED = true
end

# === RELOADABLE SECTION ===
# This module gets completely redefined on each reload
module DetritusCore
  class EditFile < RubyLLM::Tool; end
  class Bash < RubyLLM::Tool; end
  # ... all classes
  
  def self.handle_prompt(prompt)
    # ... all handlers
  end
  
  def self.configure
    # ... setup state
  end
end

# === STATE PRESERVATION ===
$detritus_state ||= OpenStruct.new
old_state = $detritus_state.dup rescue nil

# Reconfigure with preserved values
DetritusCore.configure

# Restore preserved state
$detritus_state.chat = old_state.chat if old_state&.chat
$detritus_state.session = old_state.session if old_state&.session

# === FILE WATCHER ===
$watcher_thread ||= Thread.new do
  mtime = File.mtime(__FILE__)
  loop do
    sleep 1
    if File.mtime(__FILE__) > mtime
      puts "\n[!] Code changed, reloading..."
      load __FILE__  # Re-execute this entire file
      mtime = File.mtime(__FILE__)
    end
  end
end

# === MAIN LOOP ===
# Only run if not running already
unless $repl_running
  $repl_running = true
  loop do
    input = Reline.readline("> ", true)
    break if input.nil?
    next if input.empty?
    DetritusCore.handle_prompt(input)
  end
end
