---
name: ai-update-lifecycle
description: DEPRECATED — UPDATE.md has been removed from AI-OS. Intent is now provided directly via conversation context. This skill is a no-op and will be removed in a future cleanup.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read
context: default
agent: default
---

# AI-OS Update Lifecycle — DEPRECATED

> ⚠️ **DEPRECATED**: `UPDATE.md` has been removed from AI-OS (E-147).
> Intent is now provided directly via conversation context — no file needed.
> This skill is a no-op. Do NOT invoke it.

## Migration

If you were previously using `ai-update-lifecycle` to archive UPDATE.md:
- There is nothing to archive — UPDATE.md no longer exists.
- Session intent lives in the conversation history.
- Use `ai-compact` to distill long sessions when context grows large.

## Replacement
Use `skill: "ai-compact"` to manage session context accumulation.
