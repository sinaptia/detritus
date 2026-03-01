# frozen_string_literal: true

require_relative "../test_helper"

class LoadSkillTest < DetritusTest
  def setup
    super
    @loader = LoadSkill.new
  end

  def test_loads_skill_with_frontmatter
    create_skill("test_skill", "body content here", frontmatter: {description: "Test description", trigger: "on_start"})

    result = @loader.execute(name: "test_skill")

    assert_equal "body content here", result
  end

  def test_loads_skill_without_frontmatter
    skill_dir = File.join(@test_dir, ".detritus", "skills", "plain_skill")
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "Just plain content")

    result = @loader.execute(name: "plain_skill")

    assert_equal({error: "Invalid skill file format"}, result)
  end

  def test_interpolates_arguments_placeholder
    create_skill("interpolate", "Args were: $ARGUMENTS")

    result = @loader.execute(name: "interpolate", arguments: "foo bar baz")

    assert_equal "Args were: foo bar baz", result
  end

  def test_interpolates_positional_arguments
    create_skill("positional", "First: $1, Second: $2, Third: $3")

    result = @loader.execute(name: "positional", arguments: "alpha beta gamma")

    assert_equal "First: alpha, Second: beta, Third: gamma", result
  end

  def test_returns_error_for_missing_skill
    result = @loader.execute(name: "nonexistent")

    assert result.is_a?(Hash)
    assert result[:error]
    assert_includes result[:error], "nonexistent"
  end

  def test_returns_error_for_missing_name
    result = @loader.execute(name: nil)

    assert result.is_a?(Hash)
    assert_includes result[:error], "Missing required parameter"
  end

  def test_local_skill_takes_precedence
    # Create global skill
    global_dir = File.join(Dir.home, ".detritus", "skills", "cascade_test")
    FileUtils.mkdir_p(global_dir)
    File.write(File.join(global_dir, "SKILL.md"), "---\nname: global\n---\nGlobal content")

    # Create local skill with same name
    create_skill("cascade_test", "Local content", frontmatter: {name: "local"})

    result = @loader.execute(name: "cascade_test")

    # Should return local body
    assert_equal "Local content", result
  ensure
    FileUtils.rm_rf(global_dir)
  end

  def test_fallback_to_global_skill
    skill_name = "global_only_#{Time.now.to_i}"
    global_dir = File.join(Dir.home, ".detritus", "skills", skill_name)
    FileUtils.mkdir_p(global_dir)
    File.write(File.join(global_dir, "SKILL.md"), "---\nname: global_fall\n---\nGlobal fallback")

    result = @loader.execute(name: skill_name)

    assert_equal "Global fallback", result
  ensure
    FileUtils.rm_rf(global_dir)
  end

  def test_handles_complex_frontmatter
    create_skill("complex", "Complex body",
      frontmatter: {
        name: "Complex Skill",
        description: "A skill with many settings",
        trigger: "manual",
        type: "agent"
      })

    result = @loader.execute(name: "complex")

    assert_equal "Complex body", result
  end

  def test_handles_empty_arguments
    create_skill("no_args", "Content with $ARGUMENTS end")

    result = @loader.execute(name: "no_args")

    assert_equal "Content with  end", result
  end

  def test_bash_expansion_basic
    create_skill("bash_basic", "Dir: !`echo mytest`")

    result = @loader.execute(name: "bash_basic")

    assert_equal "Dir: mytest", result
  end

  def test_bash_expansion_multiple
    create_skill("bash_multi", "First: !`echo one` Second: !`echo two`")

    result = @loader.execute(name: "bash_multi")

    assert_equal "First: one Second: two", result
  end

  def test_bash_expansion_with_arguments
    create_skill("bash_args", "$ARGUMENTS is !`echo substituted`")

    result = @loader.execute(name: "bash_args", arguments: "hello")

    assert_equal "hello is substituted", result
  end

  def test_bash_expansion_error
    create_skill("bash_error", "Output: !`exit 1; echo should_not_see`")

    result = @loader.execute(name: "bash_error")

    assert_includes result, "Output: "
  end

  def test_bash_expansion_real_command
    create_skill("bash_real", "Current file: !`basename #{@test_dir}`")

    result = @loader.execute(name: "bash_real")

    assert_equal "Current file: #{File.basename(@test_dir)}", result
  end

  def test_skill_without_body_returns_invalid_format_error
    skill_dir = File.join(@test_dir, ".detritus", "skills", "no_body")
    FileUtils.mkdir_p(skill_dir)

    File.write(File.join(skill_dir, "SKILL.md"), "---
name: no_body_skill
description: Just the frontmatter
---")

    result = @loader.execute(name: "no_body")

    assert_equal({error: "Invalid skill file format"}, result)
  end

  def test_skill_with_empty_frontmatter_section
    skill_dir = File.join(@test_dir, ".detritus", "skills", "empty_frontmatter")
    FileUtils.mkdir_p(skill_dir)
    # Empty frontmatter (just markers) followed by body - needs newline between
    File.write(File.join(skill_dir, "SKILL.md"), "---\n---\n\nBody with empty frontmatter")

    result = @loader.execute(name: "empty_frontmatter")

    # With empty frontmatter, the regex captures body including the leading \n
    assert_includes result, "Body with empty frontmatter"
  end
end
