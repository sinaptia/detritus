# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < DetritusTest
  def setup
    super
    @original_home = ENV["HOME"]
    ENV["HOME"] = @test_dir




  end

  def teardown
    Dir.chdir(@original_dir)
    ENV["HOME"] = @original_home
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
    create_config({"provider" => "ollama", "model" => "llama3"})

    configure

    assert_match "pwd:#{@project_dir}", $state.instructions
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

  def test_available_scripts_substitution
    create_config({"provider" => "ollama", "model" => "llama3"})

    script_path = File.join(@test_dir, ".detritus", "scripts", "test_script")
    File.write(script_path, "#!/bin/bash\necho 'Test script help'")
    FileUtils.chmod("+x", script_path)

    configure

    assert_match "test_script", $state.instructions
    assert_match "Test script help", $state.instructions
  end
end
