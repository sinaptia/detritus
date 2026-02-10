require_relative "test_helper"

class ChatPersistenceTest < DetritusTest
  def setup
    super

    $state.provider = "gemini"
    $state.model = "gemini-2.5-flash"
    $state.instructions = "You are a helpful assistant."
    $state.current_chat_id = "test_chat_#{Time.now.to_i}"
    RubyLLM.configure do |c|
      c.gemini_api_key = ENV["GEMINI_API_KEY"]
    end
  end

  def test_creates_chat_with_default_tools
    chat = create_chat

    assert_equal 4, chat.tools.size

    tool_classes = chat.tools.values.map(&:class)
    assert_includes tool_classes, EditFile
    assert_includes tool_classes, Bash
    assert_includes tool_classes, WebSearch
    assert_includes tool_classes, SubAgent
  end

  def test_creates_chat_with_custom_tools
    chat = create_chat(tools: [EditFile, Bash])

    assert_equal 2, chat.tools.size

    tool_classes = chat.tools.values.map(&:class)
    assert_includes tool_classes, EditFile
    assert_includes tool_classes, Bash
  end

  def test_saves_chat_to_detritus_chats_as_yaml
    chat = create_chat(persist: false)
    $state.chat = chat
    chat.add_message(role: :user, content: "Hello, this is a test message")
    chat.add_message(role: :assistant, content: "Hello! How can I help you today?")

    save_chat

    chat_file = ".detritus/chats/#{$state.current_chat_id}.yml"
    assert File.exist?(chat_file), "Chat file should exist at #{chat_file}"

    content = YAML.unsafe_load(File.read(chat_file))
    assert_equal $state.current_chat_id, content[:id]
    assert_equal $state.model, content[:model]
    assert_equal $state.provider, content[:provider]

    messages = content[:messages]
    assert_equal 3, messages.size # System + User + Assistant

    system_message = messages.find { |m| m[:role] == :system }
    assert_equal $state.instructions, system_message[:content]

    user_message = messages.find { |m| m[:role] == :user }
    assert_equal "Hello, this is a test message", user_message[:content]

    assistant_message = messages.find { |m| m[:role] == :assistant }
    assert_equal "Hello! How can I help you today?", assistant_message[:content]
  end

  def test_save_and_load_round_trip_preserves_messages_without_duplicates
    # Save a chat
    chat = create_chat(persist: false)
    $state.chat = chat
    chat.add_message(role: :user, content: "First message")
    chat.add_message(role: :assistant, content: "First response")
    chat.add_message(role: :user, content: "Second message")

    original_message_count = chat.messages.size
    save_chat

    # Load it back
    loaded_chat = load_chat($state.current_chat_id)

    assert loaded_chat.is_a?(RubyLLM::Chat)
    assert_equal original_message_count, loaded_chat.messages.size

    # Should have exactly one system message (no duplicates)
    system_messages = loaded_chat.messages.select { |m| m.role == :system }
    assert_equal 1, system_messages.size

    # All messages should be restored
    contents = loaded_chat.messages.map { |m| m.content.respond_to?(:text) ? m.content.text : m.content }
    assert_includes contents, "First message"
    assert_includes contents, "First response"
    assert_includes contents, "Second message"
  end

  def test_load_chat_returns_nil_for_missing_file
    assert_nil load_chat("non_existent_chat_id")
  end
end
