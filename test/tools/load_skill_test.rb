# frozen_string_literal: true

require_relative "../test_helper"

class LoadSkillTest < DetritusTest
  def setup
    super
    @loader = LoadSkill.new
  end

  # Test basic skill loading with frontmatter
  def test_loads_skill_with_frontmatter
    create_skill("test_skill", "body content here", 
      frontmatter: {description: "Test description", trigger: "on_start"})
    
    result = @loader.execute(name: "test_skill")
    
    assert_equal "test_skill", result[:name]
    assert_equal "Test description", result[:description]
    assert_equal "on_start", result[:trigger]
    assert_equal "prompt", result[:type]
    assert_equal "body content here", result[:body]
  end

  # Test skill with defaults when no frontmatter provided
  def test_loads_skill_without_frontmatter
    skill_dir = File.join(@test_dir, ".detritus", "skills", "plain_skill")
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "Just plain content")
    
    result = @loader.execute(name: "plain_skill")
    
    assert_equal "plain_skill", result[:name]
    assert_equal "", result[:description]
    assert_equal "", result[:trigger]
    assert_equal "prompt", result[:type]
    assert_equal "Just plain content", result[:body]
  end

  # Test argument interpolation with $ARGUMENTS
  def test_interpolates_arguments_placeholder
    create_skill("interpolate", "Args were: $ARGUMENTS")
    
    result = @loader.execute(name: "interpolate", arguments: "foo bar baz")
    
    assert_equal "Args were: foo bar baz", result[:body]
  end

  # Test positional argument interpolation $1, $2, $3
  def test_interpolates_positional_arguments
    create_skill("positional", "First: $1, Second: $2, Third: $3")
    
    result = @loader.execute(name: "positional", arguments: "alpha beta gamma")
    
    assert_equal "First: alpha, Second: beta, Third: gamma", result[:body]
  end

  # Test missing skill returns error
  def test_returns_error_for_missing_skill
    result = @loader.execute(name: "nonexistent")
    
    assert result[:error]
    assert_includes result[:error], "nonexistent"
  end

  # Test missing name parameter returns error
  def test_returns_error_for_missing_name
    result = @loader.execute(name: nil)
    
    assert_includes result[:error], "Missing required parameter"
  end

  # Test local skills take precedence over global
  def test_local_skill_takes_precedence
    # Create global skill
    global_dir = File.join(Dir.home, ".detritus", "skills", "cascade_test")
    FileUtils.mkdir_p(global_dir)
    File.write(File.join(global_dir, "SKILL.md"), "---\nname: global\n---\nGlobal content")
    
    # Create local skill with same name
    create_skill("cascade_test", "Local content", frontmatter: {name: "local"})
    
    result = @loader.execute(name: "cascade_test")
    
    # Should return local version
    assert_equal "local", result[:name]
    assert_equal "Local content", result[:body]
  ensure
    FileUtils.rm_rf(global_dir)
  end

  # Test skill falls back to global when no local
  def test_fallback_to_global_skill
    skill_name = "global_only_#{Time.now.to_i}"
    global_dir = File.join(Dir.home, ".detritus", "skills", skill_name)
    FileUtils.mkdir_p(global_dir)
    File.write(File.join(global_dir, "SKILL.md"), "---\nname: global_fall\n---\nGlobal fallback")
    
    result = @loader.execute(name: skill_name)
    
    assert_equal "global_fall", result[:name]
    assert_equal "Global fallback", result[:body]
  ensure
    FileUtils.rm_rf(global_dir)
  end

  # Test complex frontmatter parsing
  def test_handles_complex_frontmatter
    create_skill("complex", "Complex body", 
      frontmatter: {
        name: "Complex Skill",
        description: "A skill with many settings",
        trigger: "manual",
        type: "agent"
      })
    
    result = @loader.execute(name: "complex")
    
    assert_equal "Complex Skill", result[:name]
    assert_equal "A skill with many settings", result[:description]
    assert_equal "manual", result[:trigger]
    assert_equal "agent", result[:type]
  end

  # Test empty arguments don't break interpolation (positional args stay as-is when not provided)
  def test_handles_empty_arguments
    create_skill("no_args", "Content with $ARGUMENTS end")
    
    result = @loader.execute(name: "no_args")
    
    assert_equal "Content with  end", result[:body]
  end
end
