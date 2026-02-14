# frozen_string_literal: true

require_relative "../test_helper"

class SelfToolTest < DetritusTest
  def setup
    super
    @tool = Self.new
  end

  def test_executes_simple_code_and_returns_result
    result = @tool.execute(code: "2 + 2")

    assert_equal "4", result
  end

  def test_executes_code_with_string_output
    result = @tool.execute(code: "'hello'.upcase")

    assert_equal '"HELLO"', result
  end

  def test_has_access_to_global_state
    # Set up some state
    $state.test_value = "foobar"

    result = @tool.execute(code: "$state.test_value")

    assert_equal '"foobar"', result
  ensure
    # Clean up
    $state.delete_field(:test_value) if $state.respond_to?(:test_value)
  end

  def test_can_modify_global_state
    @tool.execute(code: "$state.meta_eval_test = {foo: 'bar'}")

    assert_equal({foo: 'bar'}, $state.meta_eval_test)
  ensure
    $state.delete_field(:meta_eval_test) if $state.respond_to?(:meta_eval_test)
  end

  def test_returns_error_for_undefined_method
    result = @tool.execute(code: "raise NoMethodError, 'undefined method'")

    assert_includes result[:error], "NoMethodError"
  end

  def test_returns_error_for_undefined_variables
    result = @tool.execute(code: "undefined_variable_12345")

    assert_includes result[:error], "NameError"
  end

  def test_shows_truncate_code_in_display
    output = capture_io do
      @tool.execute(code: "1 + 1")
    end.first

    assert_includes output, "{Self 1 + 1...}"
  end

  def test_truncates_long_code_in_display
    long_code = "x = " + "1 + " * 50 + "1"

    output = capture_io do
      @tool.execute(code: long_code)
    end.first

    assert_includes output, "{Self"
    assert_includes output, "...}"
    assert output.length < long_code.length + 20
  end

  def test_prints_for_short_code
    output = capture_io do
      @tool.execute(code: "2 + 2")
    end.first

    assert_includes output, "{Self 2 + 2...}"
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
