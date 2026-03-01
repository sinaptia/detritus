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

  def test_returns_error_when_old_text_not_found
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "Hello world")

    result = @tool.execute(path: test_file, old: "nonexistent text", new: "replacement")

    assert result.is_a?(Hash)
    assert_includes result[:error], "not found"
  end

  def test_returns_error_for_missing_path_parameter
    result = @tool.execute(old: "text", new: "replacement")

    assert result.is_a?(Hash)
    assert_includes result[:error], "Missing required parameter"
    assert_includes result[:error], "path"
  end

  def test_returns_error_for_missing_old_parameter
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "content")

    result = @tool.execute(path: test_file, new: "replacement")

    assert result.is_a?(Hash)
    assert_includes result[:error], "Missing required parameter"
    assert_includes result[:error], "old"
  end

  def test_returns_error_for_missing_new_parameter
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "content")

    result = @tool.execute(path: test_file, old: "content")

    assert result.is_a?(Hash)
    assert_includes result[:error], "Missing required parameter"
    assert_includes result[:error], "new"
  end

  def test_create_flag_creates_new_file
    test_file = File.join(@test_dir, "new_file.txt")
    refute File.exist?(test_file)

    result = @tool.execute(path: test_file, old: "", new: "initial content", create: true)

    assert File.exist?(test_file)
  end

  def test_create_flag_allows_subsequent_edit
    test_file = File.join(@test_dir, "edit_after_create.txt")

    @tool.execute(path: test_file, old: "", new: "original", create: true)
    result = @tool.execute(path: test_file, old: "original", new: "modified")

    assert_equal "ok", result
    assert_equal "modified", File.read(test_file)
  end
end
