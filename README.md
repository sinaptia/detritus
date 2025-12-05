# Detritus

The simplest, more straightforward, stupidly-effective agent we could come up with.
Aptly named after Lance Constable Detritus of the Ankh-Morpork City Watch from [Discworld](https://en.wikipedia.org/wiki/Discworld), Detritus is built in about 250 lines of code packing:

* support for multiple models and providers
* a basic interactive CLI with history
* custom slash commands and skills-like instruction format
* chat persistence
* subagents
* 2-level configuration (project and global)
* fun personality (thanks to Sir Terry Pratchett)

Almost a full-featured coding agent, but more than anything an experimentation platform: A single file you can read in one sitting, extend with plain text prompts and shell scripts you (or itself) already know how to write.

### Almost? what is it missing?

No guardrails. No tool permission model. No confirmation dialogs before file edits or tool calls. Detritus will happily rewrite your code the moment it decides that's the right move (how eager depends on the underlying model you pick) but "a little anxious" would be a fair description.

Do not leave it unsupervised on production, do not run it directly on your machine, use git, branches, etc, you know the drill.
It does run inside docker container by default, so the impact is kind of contained, but be warned: you are letting lose a troll with a huge cross-bow in you project.

## Usage

### REPL Commands

- `/<prompt> [args]` — Execute a named prompt
- `/load <prompt> [args]` — Load a prompt into context without executing
- `/new`, `/clear` — Reset conversation
- `/resume [id]` — Resume a previous chat (no arg lists available sessions)
- `/model <provider>/<model>` — Switch model at runtime
- `/exit`, `/quit`, `Ctrl+D` — Exit

### Non-Interactive Mode

Pass arguments to run a one-shot prompt and exit:

```bash
bin/detritus "explain this codebase"
```

## Installation

Prerequisites: **Docker** and an LLM provider (Ollama for local, or an API key for Anthropic/OpenAI/Gemini).

```bash
git clone git@github.com:sinaptia/detritus.git ~/.detritus
```

### Configuration

Edit `~/.detritus/config.yml` — uncomment and fill in the provider section you want to use. API keys can also be set via environment variables (`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`).

For project-specific overrides, create `.detritus/config.yml` in your project directory. Local config is merged on top of global.

### Running

```bash
# Add to PATH (optional)
echo 'export PATH="$HOME/.detritus/bin:$PATH"' >> ~/.zshrc

# Run (builds Docker image on first run)
bin/detritus
```

## Extending

Detritus is extended through two mechanisms: **prompts** and **scripts**. Both are resolved from two locations, with local taking precedence:

1. `.detritus/` in the current project directory
2. `~/.detritus/` global directory

### Prompts

Prompts are text files in `prompts/` that provide specialized instructions. The first line is the description (shown in the agent's available prompts list), the rest is the content. Use `{{ARGS}}` as a placeholder for arguments passed from the REPL.

```
prompts/
  system.txt      # Base instructions for all agents (special, always loaded)
  review.txt      # /review invokes this
  plan.txt        # /plan invokes this
```

To create one:

```bash
cat > ~/.detritus/prompts/review.txt << 'EOF'
Review code for bugs and improvements
Analyze the following code and provide feedback:

{{ARGS}}
EOF
```

Then use it: `/review path/to/file.rb`

Prompts can also be loaded into sub-agents via the `use_prompt` parameter, giving you specialized agent modes.

### Scripts

Scripts are executable files in `scripts/` that the agent discovers automatically and can invoke via the Bash tool. They must support a `--help` flag — the first line of its output is used as the description the LLM sees.

To create one:

```bash
cat > ~/.detritus/scripts/my-tool << 'EOF'
#!/bin/bash
if [ "$1" = "--help" ]; then
  echo "One-line description of what this does"
  exit 0
fi
# your logic here
EOF
chmod +x ~/.detritus/scripts/my-tool
```

The agent sees the script in its system prompt and can decide when to use it.

### Combining Prompts and Scripts

The real power is in combining both: a prompt provides the workflow and instructions, a script provides the custom tooling. The agent connects them automatically through the system prompt, which lists all available prompts and scripts.

### System Prompt

The base behavior is defined in `prompts/system.txt`. It supports template variables:

- `%%{Dir.pwd}%%` — Current working directory
- `%%{available_prompts}%%` — Auto-populated list of available prompts
- `%%{available_scripts}%%` — Auto-populated list of available scripts

Edit it to change how the agent behaves.

