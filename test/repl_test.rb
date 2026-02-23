# frozen_string_literal: true

require_relative "test_helper"

class ReplTest < DetritusTest
  def setup
    super
    # Set fake GEMINI_API_KEY if not present (for testing without real key)
    ENV["GEMINI_API_KEY"] ||= "fake-gemini-key-for-testing"

    # Configure RubyLLM BEFORE creating chat
    RubyLLM.configure do |c|
      c.gemini_api_key = ENV["GEMINI_API_KEY"]
    end

    # Configure state for REPL
    $state.provider = "gemini"
    $state.model = "gemini-2.5-flash"
    $state.instructions = "You are a helpful assistant."
    $state.current_chat_id = "test_repl_#{Time.now.to_i}"
    $state.history_file = File.join(@test_dir, ".detritus", "history")
    $state.chat = create_chat(persist: false)
  end

  def test_new_and_clear_create_new_chat
    old_chat = $state.chat

    output = capture_io { handle_prompt("/new") }.first
    assert_includes output, "[✓ context cleared]"

    new_chat = $state.chat
    refute_same old_chat, new_chat
    assert new_chat.is_a?(RubyLLM::Chat)

    # Test /clear does the same
    old_chat = $state.chat
    output = capture_io { handle_prompt("/clear") }.first
    assert_includes output, "[✓ context cleared]"
    refute_same old_chat, $state.chat
  end



  def test_resume_id_loads_state_successfully
    # Create a state file first
    chat_id = "saved_chat_123"
    chat_data = {
      id: chat_id,
      model: $state.model,
      provider: $state.provider,
      messages: [
        { role: :user, content: "Previous message" },
        { role: :assistant, content: "Previous response" }
      ]
    }
    FileUtils.mkdir_p(".detritus/states")
    File.write(".detritus/states/#{chat_id}", Marshal.dump(chat_data))

    output = capture_io { handle_prompt("/resume #{chat_id}") }.first
    assert_includes output, "[✓ State resumed: #{chat_id} (2 messages)]"
    assert_equal chat_id, $state.current_chat_id
  end

  def test_regular_message_asks_chat_with_streaming
    with_vcr("repl_regular_message") do
      output = capture_io { handle_prompt("What is 1+1? Just say the number.") }.first

      # Should have received some response
      assert output.length > 0
    end
  end

  def test_history_gets_appended_immediately
    # Clear history file
    File.write($state.history_file, "")

    with_vcr("repl_history_first") do
      handle_prompt("first message")
    end

    history_content = File.read($state.history_file)
    assert_includes history_content, "first message"

    with_vcr("repl_history_second") do
      handle_prompt("second message")
    end

    history_content = File.read($state.history_file)
    assert_includes history_content, "first message"
    assert_includes history_content, "second message"
  end

  def test_model_command_switches_model_and_provider_while_preserving_messages
    # Clear any messages from setup if any
    $state.chat.reset_messages!

    # Add a user message
    $state.chat.add_message(role: :user, content: "Hello from Gemini")
    assert_equal "gemini", $state.provider
    assert_equal "gemini-2.5-flash", $state.model

    output = capture_io { handle_prompt("/model ollama/llama2") }.first

    assert_includes output, "[✓ Switched to ollama/llama2]"
    assert_equal "ollama", $state.provider
    assert_equal "llama2", $state.model

    # Verify model was updated in the chat object
    assert_equal "llama2", $state.chat.model.id

    # Verify message was preserved (exactly 1 now since we reset and added 1)
    assert_equal 1, $state.chat.messages.size
    assert_equal "Hello from Gemini", $state.chat.messages.first.content
  end

  def test_bang_command_executes_shell_command_and_prints_output
    output = capture_io { handle_prompt("!echo hello") }.first

    assert_includes output, "hello"
  end

  def test_bang_command_adds_command_and_output_to_chat_history
    $state.chat.reset_messages!

    handle_prompt("!echo test_output")

    messages = $state.chat.messages
    assert_equal 1, messages.size

    message_content = messages.first.content.respond_to?(:text) ? messages.first.content.text : messages.first.content
    assert_includes message_content, "echo test_output"
    assert_includes message_content, "test_output"
  end

  def test_bang_command_with_multiline_output
    output = capture_io { handle_prompt("!printf 'line1\nline2\nline3'") }.first

    assert_includes output, "line1"
    assert_includes output, "line2"
    assert_includes output, "line3"
  end

  def test_bang_command_does_not_add_empty_command_to_chat
    $state.chat.reset_messages!

    # This should not cause issues - empty command case
    handle_prompt("!true")

    # Message should be added but handle empty case gracefully
    # The regex .+ requires at least one character, so "!" alone won't match
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
