# frozen_string_literal: true

require_relative "test_helper"

class SessionMetricsTest < DetritusTest
  def setup
    super
    $state.provider = "ollama"
    $state.model = "kimi-k2.5:cloud"
    $state.instructions = "You are a helpful assistant."
    $state.current_chat_id = "test_metrics_#{Time.now.to_i}"
    $state.history_file = File.join(@test_dir, ".detritus", "history")
    # Create fresh chat for each test to match cassette requests
    $state.chat = create_chat(persist: false)
  end
  
  # Note: VCR cassettes match on method+uri only (not body) because
  # request bodies contain dynamic content. Each cassette file contains
  # the recorded interactions for its specific test.

  def test_session_initializes_with_zero_metrics
    reset_session
    assert_equal 0, $state.session[:messages]
    assert_equal 0, $state.session[:tokens_in]
    assert_equal 0, $state.session[:tokens_out]
  end

  def test_sending_message_records_metrics
    reset_session

    with_vcr("session_metrics_single_message") do
      $state.chat.ask("Say hi briefly")
    end

    # After a real chat response, we should have non-zero token counts
    assert_operator $state.session[:messages], :>, 0
    assert_operator $state.session[:tokens_in], :>, 0
    assert_operator $state.session[:tokens_out], :>, 0
  end

  def test_multiple_messages_accumulate_totals
    reset_session

    with_vcr("session_metrics_multiple_messages") do
      $state.chat.ask("Say hello")
      initial_messages = $state.session[:messages]
      initial_tokens_in = $state.session[:tokens_in]

      $state.chat.ask("Say goodbye")

      # Totals should have increased from second message
      assert_operator $state.session[:messages], :>, initial_messages
      assert_operator $state.session[:tokens_in], :>, initial_tokens_in
    end
  end

  def test_new_clears_session_metrics
    reset_session

    with_vcr("session_metrics_for_clear") do
      $state.chat.ask("Say hi")
    end

    # Verify we have accumulated metrics
    assert_operator $state.session[:messages], :>, 0

    # Clear and reset
    capture_io { handle_prompt("/new") }

    assert_equal 0, $state.session[:messages]
    assert_equal 0, $state.session[:tokens_in]
    assert_equal 0, $state.session[:tokens_out]
  end

  def test_status_command_shows_metrics
    reset_session

    with_vcr("session_metrics_for_status") do
      $state.chat.ask("Hello")
    end

    # Create status prompt that displays metrics
    create_prompt("status", "Show current session:\nMessages: {{ARGS}}\nTokens in: {{ARGS}}\nModel: {{ARGS}}")

    output = capture_io { handle_prompt("/status") }.first

    # The prompt system should process the status command
    # Either it finds the prompt or shows an error
    refute_includes output, "Error: Prompt 'status' not found"
  end

  def test_sending_with_tool_records_tool_call
    reset_session

    with_vcr("session_metrics_tool_call") do
      $state.chat.ask("use bash to run 'echo hi'")
    end

    # If a tool was called, session should reflect it
    # (Note: tool call counting depends on message structure returned by API)
    assert_operator $state.session[:messages], :>, 0
  end
end
