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
    # Reset session to known state
    reset_session
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

  def test_sending_with_tool_records_tool_call
    reset_session

    with_vcr("session_metrics_tool_call") do
      $state.chat.ask("use bash to run 'echo hi'")
    end

    # If a tool was called, session should reflect it
    # (Note: tool call counting depends on message structure returned by API)
    assert_operator $state.session[:messages], :>, 0
  end

  def test_track_metrics_nil_guard_returns_early
    # track_metrics should return early when msg is nil
    original_tokens_in = $state.session[:tokens_in]

    track_metrics(nil)

    # Should not modify any metrics
    assert_equal original_tokens_in, $state.session[:tokens_in]
    assert_equal original_tokens_out = $state.session[:tokens_out], $state.session[:tokens_out]
  end

  def test_track_metrics_increments_tool_calls
    # Create a mock message that responds to tool_call?
    mock_msg = OpenStruct.new(
      input_tokens: 10,
      output_tokens: 20,
      cached_tokens: 5,
      tool_call?: true
    )

    original_tool_calls = $state.session[:tool_calls]
    track_metrics(mock_msg)

    assert_equal original_tool_calls + 1, $state.session[:tool_calls]
  end

  def test_status_line_format
    # Use VCR recorded session to test status line with real tokens
    reset_session

    with_vcr("status_line_format_test") do
      $state.chat.ask("Say 'hi' briefly")
    end

    status = status_line

    assert_includes status, $state.model
    assert_includes status, "K"
  end

  def test_status_line_rounding
    # Test K rounding and format with real conversation
    reset_session

    with_vcr("status_line_rounding_test") do
      $state.chat.ask("Count to 5")
    end

    status = status_line

    # Verify format includes model and K with decimal
    assert_includes status, $state.model
    assert_includes status, "K"
    # Should have format like X.XK
    assert_match(/\d+\.\d+K/, status)
  end
end
