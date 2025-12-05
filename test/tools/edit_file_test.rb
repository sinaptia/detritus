# frozen_string_literal: true

require_relative "../test_helper"

class EditFileTest < DetritusTest
  def setup
    super
    @tool = EditFile.new
  end

  def test_successfully_replaces_text_that_appears_exactly_once
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "Hello world\nThis is a test\nGoodbye world")

    result = @tool.execute(path: test_file, old: "This is a test", new: "This is modified")

    assert_equal "ok", result
    assert_equal "Hello world\nThis is modified\nGoodbye world", File.read(test_file)
  end

  def test_preserves_file_content_around_replacement
    test_file = File.join(@test_dir, "test.txt")
    original_content = "Line 1\nLine 2\nTarget line\nLine 4\nLine 5"
    File.write(test_file, original_content)

    @tool.execute(path: test_file, old: "Target line", new: "Modified line")

    content = File.read(test_file)
    assert_includes content, "Line 1"
    assert_includes content, "Line 2"
    assert_includes content, "Modified line"
    assert_includes content, "Line 4"
    assert_includes content, "Line 5"
    refute_includes content, "Target line"
  end

  def test_handles_newlines_and_whitespace_in_old_new_text
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "Start\n  indented\n  content\nEnd")

    result = @tool.execute(
      path: test_file,
      old: "  indented\n  content",
      new: "  new indented\n  new content"
    )

    assert_equal "ok", result
    assert_equal "Start\n  new indented\n  new content\nEnd", File.read(test_file)
  end

  def test_returns_ok_on_success
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "Some content")

    result = @tool.execute(path: test_file, old: "Some", new: "Other")

    assert_equal "ok", result
  end
end
