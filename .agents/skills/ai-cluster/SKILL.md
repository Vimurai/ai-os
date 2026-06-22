---
name: ai-cluster
description: Add an intent-unique ClusterPage (CP-N) to an existing SEO TopicSeed. Wraps task-synchronizer-mcp add_cluster_page — a top-5 high-frequency MCP tool (E-178). Use after skill: ai-topic to build out a topic cluster.
disable-model-invocation: false
user-invocable: true
allowed-tools: mcp__task-synchronizer-mcp__add_cluster_page
context: default
agent: default
---

# AI-Cluster — Add a ClusterPage to a TopicSeed (SEO Engine)

## Why This Skill Exists

`add_cluster_page` (510 calls across 34 projects in the last meta-cognition window) attaches
a deep-dive **ClusterPage** to an existing TopicSeed, each targeting a unique, non-overlapping
search intent (no cannibalization). This skill is the one-step wrapper. It follows
`skill: ai-topic` (which creates the `TS-N` seed).

## When to Invoke

- After a TopicSeed exists, to add pillar + cluster pages per `.ai/blueprints/seo-keyword-multiplier.md`
- When building out the ≤ 10 cluster pages of a topic cluster

## Step 1 — Pick a Canonical Intent

`add_cluster_page` rejects unknown intents with `[UNKNOWN_INTENT_TYPE]` and duplicates with
`[INTENT_ALREADY_USED]` (healthy validation — see E-179). Choose ONE not yet used on the seed:

- **Pillar (1 per seed, uncapped):** `pillar-overview`
- **Cluster (≤ 10 per seed):** `cost`, `comparison`, `how-to`, `process`, `alternatives`,
  `best-for-use-case`, `benefits`, `requirements`, `mistakes`, `faq`

## Step 2 — Add the Page

```
mcp__task-synchronizer-mcp__add_cluster_page({
  seed_id: "TS-<N>",
  intent_type: "<one canonical intent>",
  content_blob: "<optional draft content>"
})
```

`seed_id` must match `TS-N` and the seed must already exist (`[SEED_NOT_FOUND]` otherwise —
call `skill: ai-topic` first). The pillar page does NOT count against the 10-page cap.

## Step 3 — Report

```
[CLUSTER] Added CP-7 to TS-3 [how-to]. 4/10 cluster pages used.
[CLUSTER] Rejected — intent 'how-to' already used on TS-3 (CP-7). Pick a free intent.
[CLUSTER] Rejected — [CLUSTER_CAP_REACHED] TS-3 already has 10/10 cluster pages.
```

## Rules

- One intent per cluster page — never reuse an intent on the same seed (cannibalization guard).
- Respect the 10-cluster-page cap; the pillar is separate.
- Project-scoped state only — cluster pages do not sync to the framework cloud (E-73).
- Use `get_topic_cluster` (or a future `ai-cluster-status`) to inspect remaining capacity.
