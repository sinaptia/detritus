# AGENTS.md

Guidance for coding agents to work with this codebase.

## Overview

Detritus is a Ruby-based AI agent built on the RubyLLM library.

It's a single-file application (`detritus.rb`) that provides an interactive REPL for software engineering tasks.

**Key Philosophy**:
* Minimalist - Maximize power / line count ratio. Simple is better than feature full. fight overengineering.
* Extensible - skills are central constructs (even the system prompt is a skill)
* Flexible - easy to prototype and modify. single file.

## Directives

**Read the source**: The entire implementation is ~350 lines in `detritus.rb`. Read it in full - it's the authoritative reference and more informative than any documentation.

**Run tests after changes**: After modifying `detritus.rb` or any code, always run the test suite with `rake test` to verify nothing broke.

* Always check if there's a directive you need to read before doing anything:
    **Code Constraints**: ./docs/code_constraints.md - read before adding or changing any code, specially new features
    **Testing**: ./docs/testing.md - read before working with tests
    **Git Usage**: ./docs/git.md - read before using Git
    **RubyLLM Docs nav map**: ./docs/ruby_llm.md - short cuts to access RubyLLM official docs
