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
  gem "debug"
end

require "minitest/autorun"
require "vcr"
require "webmock"
require "fileutils"
require "tmpdir"
require "debug"

# Detect if running inside Docker - tests use host.docker.internal which only works in containers
def in_docker?
  File.exist?("/.dockerenv")
rescue
  false
end

# VCR Configuration
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("cassettes", __dir__)
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :path]
  }

  # Filter sensitive data
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<GEMINI_API_KEY>") { ENV["GEMINI_API_KEY"] }
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }

  # Allow localhost connections (for ollama)
  config.ignore_localhost = false
end

# Load the main application code (DETRITUS_TEST env var prevents REPL from starting)
require_relative "../detritus"

# Helper to create a temporary test directory with .detritus structure
def create_test_dir
  root = File.dirname(File.expand_path(__FILE__, "../.."))
  # Use nanoseconds and PID for uniqueness to avoid collisions in fast test runs
  timestamp = "#{Time.now.strftime("%F-%H-%M-%S")}-#{Time.now.nsec}-#{Process.pid}"
  dir = File.join(root, "test", "tmp", timestamp)
  FileUtils.mkdir_p(dir)
  FileUtils.mkdir_p(File.join(dir, ".detritus", "skills"))
  FileUtils.mkdir_p(File.join(dir, ".detritus", "scripts"))
  FileUtils.mkdir_p(File.join(dir, ".detritus", "chats"))
  FileUtils.mkdir_p(File.join(dir, ".detritus", "skills", "system"))
  # Create a basic system skill file for tests with all substitution markers
  # Create a basic system skill file for tests with all substitution markers
  File.write(File.join(dir, ".detritus", "skills", "system", "SKILL.md"), "---\nname: system\ndescription: System skill\n---\n\n%%{available_skills}%%\n")
  dir
end

class DetritusTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @original_stdout = $stdout
    $stdout = StringIO.new unless ENV["DEBUG"]
    @test_dir = create_test_dir
    Dir.chdir(@test_dir)
  end

  def teardown
    $stdout = @original_stdout if @original_stdout
    Dir.chdir(@original_dir) if @original_dir
    FileUtils.rm_rf(@test_dir) if @test_dir && File.exist?(@test_dir)
  end

  # Helper to create a test skill file
  def create_skill(name, content, frontmatter: {})
    skill_dir = File.join(@test_dir, ".detritus", "skills", name)
    FileUtils.mkdir_p(skill_dir)
    path = File.join(skill_dir, "SKILL.md")

    # Build frontmatter YAML with string keys (safe_load doesn't handle symbols)
    fm = frontmatter.transform_keys(&:to_s)
    fm["name"] ||= name
    fm_yaml = fm.to_yaml.strip

    # to_yaml already includes '---' header, so we wrap just the body
    full_content = "#{fm_yaml}\n---\n\n#{content}"
    File.write(path, full_content)
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
