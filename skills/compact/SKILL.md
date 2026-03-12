---
name: compact
description: Create a structured summary of conversation context when the window is filling up
---

# Conversation Compaction

Create a structured checkpoint summary of the conversation so far. This preserves essential information while freeing context window space.

## Summary Format

Provide a structured summary with these sections:

## Goal
[Primary objective of the conversation/task]

## Progress
### Done
- [x] [Completed work item]

### In Progress
- [ ] [Current state of ongoing work]

## Key Decisions
- [What was decided and why]

## Critical Context
- [Files read/modified]
- [Important data needed to continue]
- [Open questions or blockers]

## Usage

When you notice the context getting lengthy or need to refocus, create a compaction summary that captures the essential state. The system will:
1. Archive older messages
2. Store your summary as context
3. Continue from the last kept messages
