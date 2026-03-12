# Detritus

The simplest, most straightforward, stupidly-effective agent we could come up with.
Aptly named after Lance Constable Detritus of the Ankh-Morpork City Watch from [Discworld](https://en.wikipedia.org/wiki/Discworld), Detritus is built in about 350 lines of code packing:

* support for multiple models and providers
* a basic interactive CLI with history
* standard skills
* chat persistence
* subagents
* 2-level configuration (project and global)
* automatic compaction (optional)
* fun personality (thanks to Sir Terry Pratchett)

Almost a full-featured coding agent, but more than anything an experimentation platform: A single file you can read in one sitting, extend with your skills and scripts

### Almost? What is it missing?

No guardrails. No tool permission model. No confirmation dialogs before file edits or tool calls. Detritus will happily rewrite your code the moment it decides that's the right move (how eager depends on the underlying model you pick) but "a little anxious" would be a fair description.

Do not leave it unsupervised on production, do not run it on your home dir, commit often, use branches, etc.. you know the drill.
It does run inside docker container by default, so the impact is somewhat of contained, but never forget you are letting lose a troll with a huge cross-bow with full access to your code.

## Usage

### REPL Commands

- `/<skill> [args]` — Execute a named skill (loads `skills/<skill>/SKILL.md`)
- `/attach <file>` — Attach file to the next message
- `/compact [focus]` — Summarize and archive old messages to save context
- `/new`, `/clear` — Reset conversation
- `/resume [id]` — Resume a previous chat (no arg = list available sessions)
- `/model <provider>/<model>` — Switch model at runtime
- `!<command>` — Direct shell execution with output captured
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
echo 'export PATH="$HOME/.detritus/bin:$PATH"' >> ~/.bashrc
# Run (builds Docker image on first run)
detritus
```

## Extending

Detritus is extended through **skills** following the [AgentSkills specification](https://agentskills.io/specification) so you can use the same skills you use on other coding agents. Even Detritus' own system prompt is a [skill you can read and modify](https://github.com/sinaptia/detritus/blob/main/skills/system/SKILL.md).

Skills are located in `skills/` directories, searched in this order (local takes precedence):

1. `.detritus/skills/` — Project-specific skills
2. `~/.detritus/skills/` — Global user skills

### Creating a Skill

```bash
mkdir -p ~/.detritus/skills/research/{scripts,references}

cat > ~/.detritus/skills/research/SKILL.md << 'EOF'
---
name: research
description: Web research assistant
---

You are a research assistant. Use web search and analysis tools to investigate: $ARGUMENTS

Focus on finding primary sources and recent information.
EOF
```

Use it: `/research distributed systems consensus algorithms`

#### String substitution and dynamic content injection

Detritus skill system supports string placeholders like $ARGUMENTS, $1, $2, ..., $N for argument substitution
and !`bash command` for dynamic content injection


### Skill scripts

Scripts in `skills/<name>/scripts/` are executable files the agent can invoke via it bash tool.

```bash
cat > ~/.detritus/skills/research/scripts/web-search << 'EOF'
#!/bin/bash
if [ "$1" = "--help" ]; then
  echo "Search the web using Gemini"
  exit 0
fi
# your logic here
curl -s "https://.../search?q=$1"
EOF
chmod +x ~/.detritus/skills/research/scripts/web-search
```
The skill file must list and describe the scripts so the agent can use them

