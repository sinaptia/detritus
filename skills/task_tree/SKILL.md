---
name: task_tree
description: Hierarchical task planning with dependency tracking
trigger: /task_tree
type: script
---

# Task Tree Skill

This skill provides hierarchical task management with parent/dependency relationships.

## Script Provided

**`task_tree`** - Hierarchical task planning and execution tracker

Located at: `~/.detritus/scripts/task_tree`

## Usage

```bash
task_tree <command> <tasks-file> [args...]
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `init <file>` | Create empty task file | `task_tree init cool-stuff.yml` |
| `add <file> <id> <content>` | Add task (derives parent from ID path) | `task_tree add cool-stuff.yml 1.2-api-planning 'Design API endpoints'` |
| `status <file> <id> <status>` | Set task status | `task_tree status cool-stuff.yml 1.2-api-planning done` |
| `next <file>` | Get next ready task (respects dependencies) | `task_tree next cool-stuff.yml` |
| `list <file>` | List all tasks with hierarchy | `task_tree list cool-stuff.yml` |

## Task ID Format

Tasks use hierarchical numerical IDs where the ID path determines parent relationships:

- `1-description` → Root task (no dots = root)
- `1.1-subtask` → Parent is `1`
- `1.2.1-nested` → Parent is `1.2`

## Status Values

| Status | Meaning | Icon |
|--------|---------|------|
| `pending` | Not started yet | `[ ]` |
| `in_progress` | Currently working on | `[→]` |
| `done` | Completed | `[✓]` |
| `blocked` | Waiting on dependencies | `[!]` |

## Task Selection Logic

The `next` command returns the first task that:
1. Has `pending` status
2. Has no parent **OR** parent is `done`
3. Is ordered by depth (shallow first), then path

## Example Workflow

```bash
# Initialize task tree
task_tree init project.yml

# Add root and subtasks
task_tree add project.yml 1-auth "Implement authentication"
task_tree add project.yml 1.1-login "Login form"
task_tree add project.yml 1.2-logout "Logout endpoint"

# Work on tasks
task_tree next project.yml     # Returns: 1.1-login (parent 1 has no status requirement)
task_tree status project.yml 1.1-login done
task_tree status project.yml 1.2-logout done
task_tree status project.yml 1-auth done

# Check status
task_tree list project.yml
```

## File Format

Tasks are stored in YAML format with automatic file locking for safe concurrent access.
