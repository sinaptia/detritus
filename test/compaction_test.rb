# frozen_string_literal: true

require_relative "test_helper"

class CompactionTest < DetritusTest
  def setup
    super
    $state.provider = "ollama"
    $state.model = "kimi-k2.5:cloud"
    $state.api_base = "http://host.docker.internal:11434/v1"
    $state.instructions = "You are a helpful assistant."
    $state.current_chat_id = "test_compaction_#{Time.now.to_i}"
    $state.history_file = File.join(@test_dir, ".detritus", "history")
    
    # Create fresh chat for each test
    $state.chat = create_chat(persist: false)
    
    # Default compaction config
    $state.compaction = {
      "enabled" => true,
      "keep_message_count" => 4,
      "trigger_tokens" => 100
    }
    
    reset_session
  end

  def test_returns_false_when_compaction_disabled
    $state.compaction["enabled"] = false
    
    # Add enough messages to trigger
    10.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 500
    
    result = compact_conversation
    
    assert_equal false, result
  end

  def test_returns_false_when_message_count_below_threshold
    # Only 3 messages, threshold is 4+ messages
    3.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 500
    
    result = compact_conversation
    
    assert_equal false, result
  end

  def test_returns_false_when_tokens_below_threshold
    # Enough messages but tokens below 100 threshold
    10.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 50
    
    result = compact_conversation
    
    assert_equal false, result
  end

  def test_returns_false_when_compaction_config_nil
    $state.compaction = nil
    
    10.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 500
    
    result = compact_conversation
    
    assert_equal false, result
  end

  def test_successful_compaction_creates_archive
    # Add a variety of messages
    $state.chat.add_message(role: :system, content: "System instructions")
    $state.chat.add_message(role: :user, content: "Hello, can you help me with Ruby?")
    $state.chat.add_message(role: :assistant, content: "Sure! What do you need help with?")
    $state.chat.add_message(role: :user, content: "I want to learn about blocks")
    $state.chat.add_message(role: :assistant, content: "Blocks are closures in Ruby...")
    $state.chat.add_message(role: :user, content: "Can you show an example?")
    $state.chat.add_message(role: :assistant, content: "Here's an example: [1,2,3].map { |x| x * 2 }")
    $state.chat.add_message(role: :user, content: "That's helpful, thanks!")
    $state.chat.add_message(role: :assistant, content: "You're welcome! Any other questions?")
    $state.chat.add_message(role: :user, content: "No, that's all for now")
    
    $state.session[:tokens] = 500
    
    message_count_before = $state.chat.messages.count
    
    with_vcr("compaction_successful_archiving") do
      compact_conversation
    end
    
    # Verify archive was created
    archive_dir = File.join(@test_dir, ".detritus", "archive")
    assert Dir.exist?(archive_dir), "Archive directory should exist"
    
    archive_files = Dir.glob(File.join(archive_dir, "*"))
    assert_equal 1, archive_files.length, "Should create exactly one archive file"
    
    # Verify archive content structure
    archive_data = Marshal.load(File.read(archive_files.first))
    assert_includes archive_data, :messages
    assert_includes archive_data, :timestamp
    assert_includes archive_data, :chat_id
    assert_equal $state.current_chat_id, archive_data[:chat_id]
  end

  def test_compaction_replaces_messages_with_summary
    # Setup messages
    $state.chat.add_message(role: :system, content: "System instructions")
    8.times { |i| $state.chat.add_message(role: :user, content: "User message #{i}") }
    
    $state.session[:tokens] = 500
    original_messages = $state.chat.messages.dup
    
    with_vcr("compaction_message_replacement") do
      compact_conversation
    end
    
    # Should keep first 2 and last 4, replace middle with summary
    assert_operator $state.chat.messages.count, :<, original_messages.count
    
    # First message should be preserved (system)
    assert_equal :system, $state.chat.messages.first.role
    
    # Last kept messages should be preserved (first preserved after summary)
    # After compaction: [system, user0, SUMMARY, user4, user5, user6, user7
    # user4 is original_messages[5], which is .last(4).first
    last_kept = original_messages.last(4).first
    assert_equal last_kept.content, $state.chat.messages[3].content
  end

  def test_compaction_resets_session_tokens
    $state.chat.add_message(role: :system, content: "System")
    8.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    
    $state.session[:tokens] = 500
    $state.session[:tokens_in] = 100
    $state.session[:tokens_out] = 200
    
    with_vcr("compaction_token_reset") do
      compact_conversation
    end
    
    assert_equal 0, $state.session[:tokens]
    assert_equal 0, $state.session[:tokens_in]
    assert_equal 0, $state.session[:tokens_out]
  end

  def test_compaction_with_focus_parameter
    8.times { |i| $state.chat.add_message(role: :user, content: "Message about Ruby #{i}") }
    $state.session[:tokens] = 500
    
    with_vcr("compaction_with_focus") do
      compact_conversation(focus: "focus on testing patterns")
    end
    
    # Archive should be created
    archive_dir = File.join(@test_dir, ".detritus", "archive")
    assert Dir.exist?(archive_dir)
  end

  def test_slash_compact_command_works
    8.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 500
    
    output = capture_io do
      with_vcr("slash_compact_command") do
        handle_prompt("/compact")
      end
    end.first
    
    assert_includes output, "[✓ Compacted ]"
  end

  def test_slash_compact_with_focus_command
    8.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 500
    
    output = capture_io do
      with_vcr("slash_compact_with_focus") do
        handle_prompt("/compact focused on deployment")
      end
    end.first
    
    assert_includes output, "[✓ Compacted ]"
  end

  def test_keep_message_count_configuration
    # Custom keep count
    $state.compaction["keep_message_count"] = 2
    
    # Add more than threshold (keep 2 + need some to archive)
    $state.chat.add_message(role: :system, content: "System")
    6.times { |i| $state.chat.add_message(role: :user, content: "Message #{i}") }
    $state.session[:tokens] = 500
    
    original_count = $state.chat.messages.count
    
    with_vcr("compaction_custom_keep_count") do
      compact_conversation
    end
    
    # Verify compaction ran (messages reduced)
    assert_operator $state.chat.messages.count, :<, original_count
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
