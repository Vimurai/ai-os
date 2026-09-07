# Architect Provider Parity (Claude as Architect)

## Goal & Architecture
**Goal**: A provider that is bound to the `architect` role (D-054, `ai pane architect`) receives
**everything the previous Architect providers (agy / gemini) had**: the Architect skill set, the
Architect-side agents, Architect permissions, an Architect-aware rulefile bootstrap, role-correct
MCP spawn identity, and a role-scoped git lane. Today `ai sync` provisions by **provider directory**
(`src/claude/*` → `.claude/`, `src/agents/*` → `.agents/`), which silently equates provider with role.
Under D-054 provisioning must be **role-aware**: a provider directory receives the shared assets plus
the assets of every role that provider serves per `.ai/roles.json`.

**Architecture**: keep the D-052 vendor directories as adapters; add a role manifest to
`src/config/registry.json` that maps each role to its skill/agent source directories; make
`do_sync`, the settings overlay generator, the hooks, and `ai doctor` consult `.ai/roles.json` ×
the manifest instead of hardcoding `claude=engineer`, `agents/gemini=architect`.

## Parity Inventory (measured 2026-09-04)
| Surface | agy/gemini Architect has | Claude provider gets today | Gap |
|---|---|---|---|
| MCP servers | 25 via `.agents/mcp_config.json` (safe-exec spawn env `AI_OS_CALLER_ROLE=architect`) | 25 via `.mcp.json` (shared by both panes; spawn env = engineer) | Spawn identity — closed by E-208 launch env; verify |
| Skills | shared (25) + `src/agents/skills` (15: blueprint-writer, task-planner, decision-recorder, arch-review, architectural-aligner, digest_updater, review_synthesizer, ux_template, aqg-resolver, identity_guardian, seo_content_checklist, ai-seo, ai-task, repo-oracle, proposed) | shared + `src/claude/skills` (9, Engineer-side) | **15 Architect skills missing** from `.claude/skills` |
| Agents | 21 via agy plugin (built from `src/claude/agents` + `src/gemini/agents`) | 13 from `src/claude/agents` | **7 missing**: ux_reviewer, docs-architect, knowledge_architect, meta_analyst, memory_curator, seo_manager, seo_content_generator |
| Rulefile | `GEMINI.md → ARCHITECT.md` auto-load | `CLAUDE.md → ENGINEER.md`; `ARCHITECT.md` appended by `ai pane` (E-208) | `ARCHITECT.md` assumes `activate_skill`; needs the ENGINEER.md-style runtime ladder (Skill tool → MCP → activate_skill) |
| Permissions | agy: no allow-list gate | `.claude/settings.json` allow-list is Engineer-scoped (68 rules, legacy `Bash(gemini -p *)`) | Architect overlay needs `ai add-task`/`ai handoff` Bash allows + `handoff_control`, `add_topic_seed`, `add_cluster_page`, `check_role_access` |
| Identity labels | owner "Architect (Agy)" hardcoded in `cli-add-task.mjs`; Stop hook stamps Actor "Claude" | same | Labels must be `<Role> (<provider>)` from roles.json |
| Git | agy has no git tool → Engineer proxy-commits `.ai/` edits (D-053 precedent) | Claude Architect HAS git | New capability: Architect-scoped commit lane (path-scoped, see §Git Lane) |
| Health | `ai doctor` reports agy plugin install state | — | Per-role provisioning report |

## Components
1. **Role manifest** (`src/config/registry.json` → `roles`):
   ```json
   "roles": {
     "architect": { "skill_dirs": ["agents/skills"], "agent_dirs": ["gemini/agents"], "rulefile": "ARCHITECT.md" },
     "engineer":  { "skill_dirs": ["claude/skills"], "agent_dirs": ["claude/agents"], "rulefile": "ENGINEER.md" },
     "shared":    { "skill_dirs": ["shared/skills"] }
   }
   ```
   Directory names stay vendor-named (D-052); the manifest is the only place that says which role they serve.
2. **Role-aware `do_sync`**: for each provider in `.ai/roles.json`, the provider's skill/agent target dir
   receives `shared` + every served role's dirs (union, byte-identical copies, `_SKILLS_INDEX.md` regenerated).
   A provider serving both roles gets everything. Agent `.md` files from `src/gemini/agents` MUST be
   normalized to the Claude agent frontmatter contract (`name`, `description`, `allowed-tools`,
   `context: fork`, `agent: general-purpose`) — verify each of the 7 loads in `/agents`.
3. **Architect settings overlay** (`.claude/settings.architect.json`, generated per E-208): adds the Architect
   allow rules (`Bash(ai add-task *)`, `Bash(ai handoff *)`, `mcp__task-synchronizer-mcp__handoff_control`,
   `add_topic_seed`, `add_cluster_page`, `mcp__context-guardian-mcp__check_role_access`); the base
   settings drop the legacy `Bash(gemini -p *)`. Deny rules are NOT the sovereignty mechanism (the hook is).
4. **Role-correct identity everywhere**: `AI_OS_CALLER_ROLE` in the `ai pane` launch env reaches every MCP
   server spawned by that pane (parity with agy's per-server env freeze) — acceptance: `analyze_command`
   from the Architect pane reports `caller_role=architect`. Owner labels become `Architect (<provider>)` /
   `Engineer (<provider>)`; the Stop hook stamps `Actor: <provider> (<role>)`.
5. **ARCHITECT.md runtime ladder**: mirror ENGINEER.md — Step 1 Skill tool `ai-preflight`, Step 2
   `run_preflight`, Step 3 `activate_skill`; skill invocation "use the Skill tool when present"; the Gemini
   Model Mandate moves under a "Provider notes" heading. Content of the Forbidden Zone / §35 unchanged.
6. **`ai doctor` per-role report**: for each role → provider, print whether the provider dir holds the role's
   skills/agents, whether the overlay exists, and whether the rulefile is present.

## Git Lane (Architect-scoped commits) — ruling
A Claude Architect may commit **only** when every staged path is under `.ai/` or `plans/`. The pre-commit
hook reads the E-129 session role (token first, env fallback): role `architect` + any staged path outside
that scope → BLOCK (`[SOVEREIGNTY_BLOCK]`, hint: hand the change list to the Engineer). For an
architect-scoped commit the `[CRITIC_STAMP]` requirement is **waived** (critics review `src/`; `.ai/` docs
have no diff for them) — all other Gate 2 checks (secret scan, co-modification warning) still run. Engineer
role behaviour is unchanged. This retires the D-053 proxy-commit workaround for same-provider Triads only;
agy Architects keep using the Engineer proxy.

## Security
- Provisioning copies files; it grants no new tool capability by itself. Capability in a Claude Architect
  pane is bounded by (a) the E-208 `Write|Edit` sovereignty gate, (b) the pre-tool-use Bash gate keyed on
  the token role, (c) the Git Lane above. Tier 3 review (`security_engineer`) is mandatory for E-214.
- Agent `.md` normalization must not widen `allowed-tools` beyond what the agy plugin `toolNames` granted.

## Execution Constraints
- Depends on **E-208** (launcher, overlay, token role) — no parity task may start before it is DONE.
- Byte-identical mirrors: `src/` canonical → `.claude/` / `.agents/` / `~/.ai-os/` (E-201 lesson).
- No new dependencies.

## Rollback Plan
- Remove `roles` from `registry.json`; `do_sync` falls back to the provider-directory mapping. Delete the
  copied Architect skills/agents from `.claude/`; delete the overlay. Revert `pre-commit.sh` Git Lane.

## E-## Task Breakdown
- **E-212** (Tier 2, dep E-208): Role manifest + role-aware skill/agent provisioning in `ai sync` (§Components 1–2).
- **E-213** (Tier 2, dep E-208): Architect overlay permissions + role-correct identity labels + MCP spawn-identity acceptance (§Components 3–4).
- **E-214** (Tier 3, dep E-208): Architect-scoped Git Lane in `pre-commit.sh` (§Git Lane).
- **E-215** (Tier 2, dep E-212): ARCHITECT.md runtime ladder + `ai doctor` per-role provisioning report (§Components 5–6).
