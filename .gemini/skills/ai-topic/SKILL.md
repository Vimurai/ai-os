---
name: ai-topic
description: Create a new SEO TopicSeed (TS-N) for the Topic Cluster Engine. Wraps task-synchronizer-mcp add_topic_seed — a top-5 high-frequency MCP tool (E-178). Use when starting a new keyword cluster before adding cluster pages.
disable-model-invocation: false
user-invocable: true
allowed-tools: mcp__task-synchronizer-mcp__add_topic_seed
context: default
agent: default
---

# AI-Topic — Create a TopicSeed (SEO Cluster Engine)

## Why This Skill Exists

`add_topic_seed` (238 calls across 34 projects in the last meta-cognition window) creates
the root **TopicSeed** of an SEO topic cluster — the pillar term that cluster pages hang
off. This skill is the one-step wrapper. It pairs with `skill: ai-cluster` (add pages) and
`get_topic_cluster` (inspect the cluster).

## When to Invoke

- Starting a new keyword/topic cluster per `.ai/blueprints/seo-keyword-multiplier.md`
- Before any `add_cluster_page` call (a cluster page requires an existing seed)

## Step 1 — Validate Input (avoid the #1 rejection)

`add_topic_seed` rejects bad input with `[INVALID_TOPIC_TERM]` / `[INVALID_TARGET_VOLUME]`
(these are healthy validation rejections — see E-179). Pre-check before calling:

- `term`: 1–256 chars, and **no shell metacharacters** (`; & | ` ` $ ( ) < > ` newlines)
- `target_volume` (optional): integer ≥ 1 and ≤ the cluster cap (defaults to the max)

## Step 2 — Create

```
mcp__task-synchronizer-mcp__add_topic_seed({ term: "<keyword phrase>", target_volume: <N> })
```

Returns the assigned `TS-N` id and the seed record.

## Step 3 — Report

```
[TOPIC] Created TS-3: "best running shoes" (target_volume=12). Next: skill: ai-cluster.
[TOPIC] Rejected — term contains shell metacharacters. Clean the term and retry.
```

## Rules

- This skill is project-scoped: TopicSeeds live in the local `state.sqlite` only and do
  **not** cross the framework cloud boundary (E-73 data-privacy contract).
- One seed per distinct pillar term — do not create near-duplicate seeds (cannibalization).
- After creating the seed, use `skill: ai-cluster` to attach intent-unique cluster pages.
