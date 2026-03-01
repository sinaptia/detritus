# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < DetritusTest
  def setup
    super
    @original_home = ENV["HOME"]
    ENV["HOME"] = @test_dir

    # Capture original history to restore later
    @original_history = Reline::HISTORY.to_a.dup
    Reline::HISTORY.clear
  end

  def teardown
    Dir.chdir(@original_dir)
    ENV["HOME"] = @original_home
    
    # Restore original history
    Reline::HISTORY.clear
    @original_history.each { |line| Reline::HISTORY << line }
    
    super
  end

  def test_loads_local_config
    create_config({"provider" => "ollama", "model" => "llama3"})

    configure

    assert_equal "ollama", $state.provider
    assert_equal "llama3", $state.model
  end

  def test_loads_global_config
    global_config_path = File.join(@test_dir, ".detritus", "config.yml")
    File.write(global_config_path, {"provider" => "anthropic", "model" => "claude-sonnet-4-5", "api_key" => "global-key"}.to_yaml)

    configure

    assert_equal "anthropic", $state.provider
    assert_equal "global-key", $state.api_key
  end

  def test_local_overrides_global
    global_config_path = File.join(@test_dir, ".detritus", "config.yml")
    File.write(global_config_path, {"provider" => "anthropic", "model" => "claude-sonnet-4-5", "api_key" => "global-key"}.to_yaml)
    create_config({"provider" => "gemini", "model" => "gemini-2.5-flash", "api_key" => "local-key"})

    configure

    assert_equal "gemini", $state.provider
    assert_equal "local-key", $state.api_key
  end

  def test_system_instructions_substitution
    # Create a test skill
    create_skill("my_skill", "Skill body content", 
      frontmatter: {description: "A test skill"})

    create_config({"provider" => "ollama", "model" => "llama3"})

    configure

    assert_match "my_skill", $state.instructions
    assert_match "A test skill", $state.instructions
  end

  def test_rubyllm_configuration_anthropic
    create_config({"provider" => "anthropic", "model" => "claude-sonnet-4-5", "api_key" => "anthropic-key"})
    configure
    assert_equal "anthropic-key", RubyLLM.config.anthropic_api_key
  end

  def test_rubyllm_configuration_gemini
    create_config({"provider" => "gemini", "model" => "gemini-2.5-flash", "api_key" => "gemini-key"})

    configure

    assert_equal "gemini-key", RubyLLM.config.gemini_api_key
  end

  def test_rubyllm_configuration_ollama
    create_config({"provider" => "ollama", "api_base" => "http://ollama:11434/v1"})

    configure

    assert_equal "http://ollama:11434/v1", RubyLLM.config.ollama_api_base
  end

  def test_rubyllm_configuration_openai
    create_config({"provider" => "openai", "api_key" => "openai-key", "api_base" => "http://openai-proxy/v1"})

    configure

    assert_equal "openai-key", RubyLLM.config.openai_api_key
    assert_equal "http://openai-proxy/v1", RubyLLM.config.openai_api_base
  end

  def test_available_skills_substitution
    create_config({"provider" => "ollama", "model" => "llama3"})

    create_skill("another_skill", "Another body", 
      frontmatter: {description: "Another test skill"})

    configure

    assert_match "another_skill", $state.instructions
    assert_match "Another test skill", $state.instructions
  end

  def test_missing_system_skill_raises_type_error
    # Remove the system skill file that test_helper creates
    system_skill_path = File.join(@test_dir, ".detritus", "skills", "system", "SKILL.md")
    File.delete(system_skill_path)
    refute File.exist?(system_skill_path), "System skill file should be deleted"

    create_config({"provider" => "ollama", "model" => "llama3"})

    # configure tries to read system skill but find_skill returns nil
    # File.read(nil) raises TypeError
    assert_raises(TypeError) do
      configure
    end
  end

  def test_loads_readline_history_from_file
    # Create history file with some entries
    FileUtils.mkdir_p(File.join(@test_dir, ".detritus"))
    history_file = File.join(@test_dir, ".detritus", "history")
    File.write(history_file, "first command\nsecond command\nthird command\n")

    create_config({"provider" => "ollama", "model" => "llama3"})
    
    # Clear any existing history first
    Reline::HISTORY.clear
    
    configure

    # Verify history was loaded
    assert_includes Reline::HISTORY.to_a, "first command"
    assert_includes Reline::HISTORY.to_a, "second command"
    assert_includes Reline::HISTORY.to_a, "third command"
  end

  def test_skips_history_loading_when_no_history_file
    # Ensure no history file exists
    history_file = File.join(@test_dir, ".detritus", "history")
    FileUtils.rm_f(history_file)
    
    create_config({"provider" => "ollama", "model" => "llama3"})
    
    # Clear any existing history
    Reline::HISTORY.clear
    
    # Should not raise an error
    assert_silent do
      configure
    end
    
    # History should be empty or not affected
    assert_empty Reline::HISTORY.to_a
  end
end
