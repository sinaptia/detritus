# frozen_string_literal: true

ENV["DETRITUS_TEST"] = "1"

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "ruby_llm"
  gem "reline"
  gem "minitest"
  gem "vcr"
  gem "webmock"
end

require "minitest/autorun"
require "vcr"
require "webmock"
require "fileutils"
require "tmpdir"

# VCR Configuration
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("cassettes", __dir__)
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }

  # Filter sensitive data
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<GEMINI_API_KEY>") { ENV["GEMINI_API_KEY"] }
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }

  # Allow localhost connections (for ollama)
  config.ignore_localhost = true
end

# Load the main application code (DETRITUS_TEST env var prevents REPL from starting)
require_relative "../detritus"

# Helper to create a temporary test directory with .detritus structure
def create_test_dir
  root = File.dirname(File.expand_path(__FILE__, "../.."))
  dir = File.join(root, "tmp", Time.now.strftime("%F-%H-%M-%S"))
  FileUtils.mkdir_p(dir)
  FileUtils.mkdir_p(File.join(dir, ".detritus", "prompts"))
  FileUtils.mkdir_p(File.join(dir, ".detritus", "scripts"))
  FileUtils.mkdir_p(File.join(dir, ".detritus", "chats"))
  dir
end

class DetritusTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @test_dir = create_test_dir
    Dir.chdir(@test_dir)
  end

  def teardown
    Dir.chdir(@original_dir) if @original_dir
    FileUtils.rm_rf(@test_dir) if @test_dir && File.exist?(@test_dir)
  end

  # Helper to create a test prompt file
  def create_prompt(name, content)
    path = File.join(@test_dir, ".detritus", "prompts", "#{name}.txt")
    File.write(path, content)
    path
  end

  # Helper to create a test script
  def create_script(name, content, executable: true)
    path = File.join(@test_dir, ".detritus", "scripts", name)
    File.write(path, content)
    FileUtils.chmod("+x", path) if executable
    path
  end

  # Helper to create a test config
  def create_config(config_hash)
    path = File.join(@test_dir, ".detritus", "config.yml")
    File.write(path, config_hash.to_yaml)
    path
  end

  # VCR wrapper for tests that need API recordings
  def with_vcr(cassette_name)
    VCR.use_cassette(cassette_name) do
      yield
    end
  end
end
