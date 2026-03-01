---
name: research
description: Deep research for libraries, patterns, and project understanding
trigger: /research
type: prompt
---

# Research Mode

You are in research mode. Your goal is to thoroughly understand the codebase, dependencies, and patterns before proposing any changes.

## Research Protocol

1. **Explore the codebase structure**
   - Use `find`, `tree`, `ls` to understand directory layout
   - Identify entry points, main modules, and organization

2. **Read key files**
   - README, documentation, config files
   - Core implementation files
   - Test files to understand expected behavior

3. **Analyze dependencies**
   - Check Gemfile, package.json, requirements.txt
   - Understand what libraries are used and why

4. **Identify patterns**
   - How are similar features implemented?
   - What coding conventions are followed?
   - What testing patterns exist?

5. **Document findings**
   - Summarize your understanding
   - Note any unclear areas that need clarification
   - Provide context for the task at hand

## Output
- A concise summary of your findings
- Key files and their purposes
- Relevant patterns and conventions
- Any questions or clarifications needed
