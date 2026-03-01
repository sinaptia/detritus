# frozen_string_literal: true

require_relative "test_helper"

class NonInteractiveTest < DetritusTest
  def setup
    super
    # Configure for non-interactive tests
    ENV["GEMINI_API_KEY"] ||= "fake-gemini-key-for-testing"
    RubyLLM.configure do |c|
      c.gemini_api_key = ENV["GEMINI_API_KEY"]
    end
    $state.provider = "gemini"
    $state.model = "gemini-2.5-flash"
    $state.instructions = "You are a helpful assistant."
    $state.current_chat_id = "test_non_interactive_#{Time.now.to_i}"
    $state.history_file = File.join(@test_dir, ".detritus", "history")
    $state.chat = create_chat(persist: false)
  end



  def test_regular_message_works_non_interactively
    with_vcr("non_interactive_regular_message") do
      output = capture_io { handle_prompt("What is 1+1? Just say the number.") }.first
      assert output.length > 0
    end
  end

  def test_no_persist_env_var_creates_non_persistent_chat
    # Start fresh with a persisted chat
    $state.chat = create_chat(persist: true)
    old_chat = $state.chat

    # Simulate DETRITUS_NO_PERSIST env var
    ENV["DETRITUS_NO_PERSIST"] = "1"
    $state.chat = create_chat(persist: false)

    # Verify chat was recreated with persist: false
    refute_same old_chat, $state.chat
  ensure
    ENV.delete("DETRITUS_NO_PERSIST")
  end

  private

  def capture_io
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    [$stdout.string]
  ensure
    $stdout = old_stdout
  end
end
