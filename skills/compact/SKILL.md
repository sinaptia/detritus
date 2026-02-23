---
name: compact
description: Conversation compaction strategy - use when you need to free context window space
trigger: /compact
type: prompt
---

# Conversation Compaction

You are in compaction mode. The context window is filling up and we need to preserve essential information while freeing space.

## Compaction Strategy

1. **Summarize what we've accomplished so far**
   - Key decisions made
   - Important code changes
   - Current state of work

2. **Identify what's still relevant**
   - Open tasks or pending items
   - Questions that need answers
   - Decisions that still need to be made

3. **Preserve context efficiently**
   - Remove detailed conversation history
   - Keep essential facts and decisions
   - Maintain the thread of the task

## Output
Provide a compact summary that captures all relevant state so we can continue effectively.