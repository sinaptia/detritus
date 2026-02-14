# AGENTS.md

This file provides guidance to Coding Agents when working with code in this repository.

## Overview

Detritus is a Ruby-based autonomous AI agent built on the RubyLLM library.

It's a single-file application (`detritus.rb`) that provides an interactive REPL for software engineering tasks.

**Read the source**: The entire implementation is ~245 lines in `detritus.rb`. Read it directly - it's the authoritative reference and more informative than any documentation.

**Run tests after changes**: After modifying `detritus.rb` or any code, always run the test suite with `rake test` to verify nothing broke.

**Key Philosophy**:
* Minimalist - single file implementation
* Extensible - prompts and scripts as extension points
* Flexible - easy to prototype and modify
* Maximize line of code / power ratio

## Architecture

### Resource Resolution

Prompts and scripts are resolved from two locations (local takes precedence):
1. `.detritus/` in the current project directory
2. `~/.detritus/` global directory

### Tools

The agent has four tools available (defined as `RubyLLM::Tool` subclasses):
- **EditFile** - Search-and-replace in files (requires unique `old` match), can create files
- **Bash** - Shell command execution (runs with `Bundler.with_unbundled_env`)
- **WebSearch** - Web search via Gemini 2.5 Flash with grounded search
- **SubAgent** - Delegates tasks to a sub-agent that can optionally use a named prompt

### REPL Commands

- `/exit`, `/quit` - Exit the agent
- `/new`, `/clear` - Reset conversation context
- `/load <prompt> [args]` - Load a prompt into the conversation without executing
- `/<prompt> [args]` - Execute a named prompt (looks up `.detritus/prompts/<prompt>.txt`)
- `/resume [id]` - Resume a previous chat session (no arg lists available sessions)
- `/model <provider>/<model>` - Switch provider/model at runtime (e.g. `/model anthropic/claude-sonnet-4-5`)

### Configuration

Config is loaded from `~/.detritus/config.yml` (global) merged with `.detritus/config.yml` (local override). Keys:
- `provider` - One of: `anthropic`, `gemini`, `ollama`, `openai`
- `model` - Model identifier for the chosen provider
- `api_key` - API key (can also use env vars: `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`)
- `api_base` - Custom API base URL (for ollama, LMStudio, or OpenAI-compatible endpoints)

### System Prompt

The system prompt is loaded from `prompts/system.txt` with template variables:
- `%%{Dir.pwd}%%` - Current working directory
- `%%{available_prompts}%%` - List of available prompts
- `%%{available_scripts}%%` - List of available scripts

### Chat Persistence

Chats are auto-saved to `.detritus/chats/` using `Marshal` serialization, keyed by timestamp ID (e.g. `20250609_143022`). Use `/resume` to list and reload past sessions.

## Running the Agent

**Run normally (in Docker sandbox):**
```bash
bin/detritus [prompt]
```

**Run without Docker (direct execution, useful for debugging):**
```bash
./detritus.rb [prompt]
```

**Interactive mode** (no arguments): Starts the REPL for interactive conversation.

**Non-interactive mode** (with arguments): Executes the provided prompt once and exits. Useful for scripting or one-off tasks.

The Docker wrapper (`bin/detritus`) provides isolation and mounts:
- Current directory as `/workdir`
- `~/.detritus` as `/root/.detritus` for configuration and prompts
- Persistent gem cache in `detritus-gems` volume
- Environment variables: `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`

## Testing

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
