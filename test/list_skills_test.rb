# frozen_string_literal: true

require_relative "test_helper"

class ListSkillsTest < DetritusTest
  def test_find_skills_returns_all_skills_in_test_dir
    create_skill("zebra_skill", "Zebra body", frontmatter: {description: "Zebra skill"})
    create_skill("alpha_skill", "Alpha body", frontmatter: {description: "Alpha skill"})
    create_skill("m_skill", "M body", frontmatter: {description: "M skill"})
    
    paths = find_skills("*")
    skill_names = paths.map { |p| File.basename(File.dirname(p)) }
    
    assert_includes skill_names, "system"
    assert_includes skill_names, "zebra_skill"
    assert_includes skill_names, "alpha_skill"
    assert_includes skill_names, "m_skill"
    assert_equal 4, paths.count, "Should find 4 skills total"
  end
  
  def test_find_skills_dedupe_by_skill_name_not_filename
    create_skill("aaa_skill", "AAA body", frontmatter: {description: "AAA skill"})
    create_skill("bbb_skill", "BBB body", frontmatter: {description: "BBB skill"})
    
    paths = find_skills("*")
    skill_names = paths.map { |p| File.basename(File.dirname(p)) }.sort
    
    assert_equal ["aaa_skill", "bbb_skill", "system"], skill_names
  end
  
  def test_list_skills_returns_all_skill_descriptions
    create_skill("zzz_skill", "ZZZ body", frontmatter: {description: "ZZZ desc"})
    create_skill("aaa_skill", "AAA body", frontmatter: {description: "AAA desc"})
    
    result = list_skills
    
    assert_includes result, "aaa_skill"
    assert_includes result, "AAA desc"
    assert_includes result, "zzz_skill"
    assert_includes result, "ZZZ desc"
  end
end
