# frozen_string_literal: true

require_relative "test_helper"

class PromptBuildingTest < DetritusTest
  def test_loads_prompt_and_substitutes_single_args
    create_prompt("test_prompt", "Description line\nHello {{ARGS}}, welcome!")

    result = build_prompt("test_prompt", "world")

    assert_equal "Description line\nHello world, welcome!", result
  end

  def test_multiple_args_in_same_file_all_get_replaced
    create_prompt("multi_args", "Description\n{{ARGS}} is here and {{ARGS}} is also here")

    result = build_prompt("multi_args", "value")

    assert_equal "Description\nvalue is here and value is also here", result
  end

  def test_works_with_prompt_names_with_and_without_txt_extension
    create_prompt("my_prompt", "First line\nContent with {{ARGS}}")

    # Without .txt extension
    result_without_ext = build_prompt("my_prompt", "test")
    assert_equal "First line\nContent with test", result_without_ext

    # With .txt extension
    result_with_ext = build_prompt("my_prompt.txt", "test")
    assert_equal "First line\nContent with test", result_with_ext
  end
end
