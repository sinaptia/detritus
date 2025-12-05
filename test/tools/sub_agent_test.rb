# frozen_string_literal: true

require_relative "../test_helper"

class SubAgentTest < DetritusTest
  def setup
    super
    # Configure provider for SubAgent to use
    $state.provider = "gemini"
    $state.model = "gemini-2.5-flash"
    $state.instructions = "You are a helpful assistant."
    RubyLLM.configure do |c|
      c.gemini_api_key = ENV["GEMINI_API_KEY"]
    end
    @tool = SubAgent.new
  end

  def test_executes_task_without_use_prompt_returns_response_content
    with_vcr("sub_agent_basic") do
      result = @tool.execute(task: "What is 2+2? Answer with just the number.")

      assert_match "4", result
    end
  end

  def test_executes_task_with_use_prompt_loads_prompt_drops_first_line
    # Create a prompt with description on first line
    create_prompt("math_helper", "Description: Math helper prompt\nYou are a math expert. Always show your work step by step.")

    with_vcr("sub_agent_with_prompt") do
      result = @tool.execute(task: "What is 3+3?", use_prompt: "math_helper")

      assert_match "3 + 3 = 6", result
    end
  end

  def test_sub_agent_has_edit_file_bash_web_search_tools
    # Verify by reading the SubAgent source - it calls:
    # create_chat(tools: [EditFile, Bash, WebSearch], persist: false)
    source_file = File.read(File.expand_path("../../detritus.rb", __dir__))
    subagent_section = source_file[/class SubAgent.*?^end/m]

    # The SubAgent should create chat with these specific tools
    assert_match(/create_chat\(tools: \[EditFile, Bash, WebSearch\]/, subagent_section)
    # Should NOT include SubAgent itself (no recursion)
    refute_match(/create_chat\(tools:.*SubAgent/, subagent_section)
  end

  def test_chat_is_not_persisted
    # Verify by reading the SubAgent source - it calls create_chat with persist: false
    source_file = File.read(File.expand_path("../../detritus.rb", __dir__))
    subagent_section = source_file[/class SubAgent.*?^end/m]

    # The SubAgent should create chat with persist: false
    assert_match(/persist: false/, subagent_section)
  end
end
