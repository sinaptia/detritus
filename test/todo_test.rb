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
    assert_equal "tasks: task added", out

    out = run_todo("tasks", "ls")
    assert_includes out, "1: [ ] Buy coffee"

    assert_path_exists File.join(Dir.pwd, ".detritus/todos/todo_tasks.txt")
  end

  def test_done_and_undone
    run_todo("tasks", "add", "Task 1")
    run_todo("tasks", "done", "1")

    out = run_todo("tasks", "ls")
    assert_includes out, "1: [x] Task 1"

    run_todo("tasks", "undone", "1")
    out = run_todo("tasks", "ls")
    assert_includes out, "1: [ ] Task 1"
  end

  def test_rm
    run_todo("tasks", "add", "Task 1")
    run_todo("tasks", "rm", "1")

    out = run_todo("tasks", "ls")
    assert_equal "tasks: empty", out
    refute_path_exists File.join(Dir.pwd, ".detritus/todos/todo_tasks.txt")
  end

  def test_multiple_lists_isolation
    run_todo("work", "add", "Code")
    run_todo("personal", "add", "Sleep")

    work_out = run_todo("work", "ls")
    personal_out = run_todo("personal", "ls")

    assert_includes work_out, "Code"
    refute_includes work_out, "Sleep"

    assert_includes personal_out, "Sleep"
    refute_includes personal_out, "Code"
  end
end
