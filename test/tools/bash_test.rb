# frozen_string_literal: true

require_relative "../test_helper"

class BashToolTest < DetritusTest
  def setup
    super
    @tool = Bash.new
  end

  def test_executes_simple_commands_and_captures_output
    result = @tool.execute(command: "echo 'hello world'")

    assert_equal "hello world\n", result
  end

  def test_handles_multi_line_output_correctly
    result = @tool.execute(command: "echo 'line1'; echo 'line2'; echo 'line3'")

    assert_equal "line1\nline2\nline3\n", result
  end

  def test_command_display_shows_truncation_for_long_commands
    long_command = "echo " + "a" * 150

    # Capture stdout to verify the truncated display
    output = capture_io do
      @tool.execute(command: long_command)
    end.first

    # The display format is "{Bash <first 100 chars>...}"
    assert_includes output, "{Bash echo "
    assert_includes output, "...}"
    # Verify truncation occurred (output should be shorter than full command)
    assert output.length < long_command.length + 20
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
