# frozen_string_literal: true

require_relative "../test_helper"

class AttachFileToolTest < DetritusTest
  def setup
    super
    @tool = AttachFile.new
  end

  def test_successfully_attaches_existing_file
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "Hello world")

    result = @tool.execute(path: test_file)

    assert_equal "ok", result
    assert_includes $state.files, test_file
  end

  def test_returns_error_for_nonexistent_file
    result = @tool.execute(path: "/nonexistent/file.txt")

    assert result.is_a?(Hash)
    assert_includes result[:error], "File Not Found"
  end

  def test_returns_error_for_missing_path_parameter
    result = @tool.execute(**{})

    assert result.is_a?(Hash)
    assert_includes result[:error], "File Not Found"
  end

  def test_can_attach_multiple_files
    file1 = File.join(@test_dir, "file1.txt")
    file2 = File.join(@test_dir, "file2.txt")
    File.write(file1, "content1")
    File.write(file2, "content2")

    @tool.execute(path: file1)
    @tool.execute(path: file2)

    assert_equal 2, $state.files.size
    assert_includes $state.files, file1
    assert_includes $state.files, file2
    assert_includes $state.files, file1
    assert_includes $state.files, file2
  end

  def test_attaching_same_file_multiple_times_deduplicates
    test_file = File.join(@test_dir, "test.txt")
    File.write(test_file, "content")

    @tool.execute(path: test_file)
    @tool.execute(path: test_file)

    # Set deduplicates automatically
    assert_equal 1, $state.files.count(test_file)
  end
end
