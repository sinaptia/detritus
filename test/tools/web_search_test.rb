# frozen_string_literal: true

require_relative "../test_helper"

class WebSearchTest < DetritusTest
  def setup
    super
    # Configure Gemini API key for WebSearch tool
    RubyLLM.configure do |c|
      c.gemini_api_key = ENV["GEMINI_API_KEY"]
    end
    @tool = WebSearch.new
  end

  def test_successful_search_via_gemini_returns_results
    with_vcr("web_search_success") do
      result = @tool.execute(query: "What is the capital of France?")

      assert result.is_a?(String)
      assert result.length > 0
    end
  end

  def test_returns_response_content_to_caller
    with_vcr("web_search_returns_content") do
      result = @tool.execute(query: "Ruby programming language")

      # Result should be the response.content string
      assert result.is_a?(String)
      refute result.is_a?(Hash)
    end
  end

  def test_displays_search_query_and_truncated_response_in_output
    with_vcr("web_search_display") do
      output = capture_io do
        @tool.execute(query: "test query")
      end.first

      # Should display the query
      assert_includes output, "{WebSearch query: test query}"
      # Should display truncated response (first 100 chars)
      assert_includes output, "{WebSearch "
    end
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
