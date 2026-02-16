# AGENTS.md

This file provides guidance to Coding Agents when working with code in this repository.

## Overview

Detritus is a Ruby-based AI agent built on the RubyLLM library.

It's a single-file application (`detritus.rb`) that provides an interactive REPL for software engineering tasks.

**Read the source**: The entire implementation is ~245 lines in `detritus.rb`. Read it directly - it's the authoritative reference and more informative than any documentation.

**Run tests after changes**: After modifying `detritus.rb` or any code, always run the test suite with `rake test` to verify nothing broke.

**Key Philosophy**:
* Minimalist - single file implementation
* Extensible - prompts and scripts as extension points
* Flexible - easy to prototype and modify
* Maximize line of code / power ratio

### Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/) format for all commits:

- `feat:` - New features
- `fix:` - Bug fixes
- `refactor:` - Code restructuring
- `docs:` - Documentation updates
- `test:` - Test changes
- `chore:` - Maintenance tasks

Format: `<type>: <description>` (lowercase, no period at end)


### Testing Philosophy

1. **Test outcomes, not implementation** - EG: Verify file contents after EditFile, not internal calls
2. **Real behavior with VCR** - Record actual API responses, no mocks
3. **Isolation** - Each test gets fresh temp directory, no shared state
4. **Happy paths focus** - Test successful execution, not every error case

### Running Tests

```bash
rake test                        # Run all tests
ruby test/some_test.rb           # Run a specific test file
ruby test/some_test.rb -n test_x # Run a specific test method
```

### Test Structure

```
test/
  test_helper.rb          # Setup, VCR config, base class
  cassettes/              # VCR recordings for API calls
  fixtures/               # Test data (prompts, scripts, configs, chats)
  *_test.rb               # Test files
```

### Writing Tests

Inherit from `DetritusTest` for automatic temp directory isolation. Each test gets a fresh temp directory with `.detritus` structure, and cleanup is automatic.

**Available helpers**:
- `create_prompt(name, content)` - Creates `.detritus/prompts/{name}.txt`
- `create_script(name, content, executable: true)` - Creates `.detritus/scripts/{name}`
- `create_config(config_hash)` - Creates `.detritus/config.yml`
- `with_vcr(cassette_name) { }` - Wraps block with VCR recording/playback

### Test Mode

`ENV["DETRITUS_TEST"]` causes detritus.rb to skip REPL initialization while still loading all classes and methods.

### VCR for API Calls

Tests that make real API calls use VCR to record and replay HTTP interactions.

**Recording new cassettes**:
1. Ensure API keys are set in environment
2. Delete the cassette file (if re-recording)
3. Run the test - VCR records the interaction
4. Subsequent runs replay from cassette
