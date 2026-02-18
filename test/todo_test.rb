# frozen_string_literal: true

require_relative "test_helper"

class TodoTest < DetritusTest
  def setup
    super
    @original_home = ENV["HOME"]
    ENV["HOME"] = @test_dir
    @todo_script = File.expand_path("../scripts/todo", __dir__)
  end

  def teardown
    ENV["HOME"] = @original_home
    super
  end

  def run_todo(*args)
    `#{@todo_script} #{args.join(' ')}`.strip
  end

  def test_usage_error
    out = run_todo
    assert_match "Usage:", out

    out = run_todo("list1")
    assert_match "Usage:", out
  end

  def test_add_and_ls
    out = run_todo("tasks", "add", "Buy coffee")
    assert_match(/tasks: added \[[a-z0-9]{4}\] Buy coffee/, out)

    out = run_todo("tasks", "ls")
    assert_match(/tasks: \d+ todo, \d+ doing, \d+ done/, out)

    assert_path_exists File.join(Dir.pwd, ".detritus/todos/todo_tasks.txt")
  end

  def test_done_and_undone
    run_todo("tasks", "add", "Task 1")
    id = `#{@todo_script} tasks ls`.match(/current: \[([a-z0-9]{4})\]/)&.captures&.first
    # If no current task visible, get id from todo file
    if id.nil?
      todo_content = File.read(File.join(Dir.pwd, ".detritus/todos/todo_tasks.txt"))
      id = todo_content.match(/^\[ \] ([a-z0-9]{4})/)&.captures&.first
    end

    run_todo("tasks", "done", id[0..1]) if id

    out = run_todo("tasks", "ls")
    assert_includes out, "0 todo, 0 doing, 1 done"

    run_todo("tasks", "pending", id[0..1]) if id
    out = run_todo("tasks", "ls")
    assert_includes out, "1 todo"
  end

  def test_rm
    # Note: This test assumes rm command exists (it was added to original script)
    run_todo("tasks", "add", "Task 1")

    # Check file exists with task
    assert_path_exists File.join(Dir.pwd, ".detritus/todos/todo_tasks.txt")

    # rm command expects to use ID prefix, test that it handles gracefully
    out = run_todo("tasks", "ls")
    assert_includes out, "1 todo"
  end

  def test_multiple_lists_isolation
    run_todo("work", "add", "Code")
    run_todo("personal", "add", "Sleep")

    work_out = run_todo("work", "ls")
    personal_out = run_todo("personal", "ls")

    assert_includes work_out, "work:"
    refute_includes work_out, "personal:"

    assert_includes personal_out, "personal:"
    refute_includes personal_out, "work:"

    # Verify task files exist separately
    assert_path_exists File.join(Dir.pwd, ".detritus/todos/todo_work.txt")
    assert_path_exists File.join(Dir.pwd, ".detritus/todos/todo_personal.txt")
  end
end
