#!/usr/bin/env bash
# sync_prune_test.sh — E-220 (D-056 R2): manifest-scoped pruning in `ai sync`.
#
# `ai sync` was purely additive: after the E-217 rename the old `ai-task` directories
# survived in every workspace forever. The obvious fix — "delete anything not in the
# source" — is the dangerous one, because a user's own skill is exactly "not in the
# source". So a path is deleted ONLY when all three hold: sync wrote it (manifest),
# nobody has edited it since (hash), and it is gone upstream (source set).
#
# The assertions below are deliberately weighted toward the KEEP direction. Over-pruning
# is data loss caused by housekeeping; under-pruning just leaves a stale directory. Every
# deletion case therefore carries a paired survival case in the same fixture.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SM="${REPO_ROOT}/src/shared/sync-manifest.mjs"
AI_BIN="${REPO_ROOT}/src/bin/ai"

echo "── Suite: sync_prune_test (E-220) ───────────────────────────────────"

_mkskill() { mkdir -p "$1/$2"; printf -- "---\nname: %s\n---\nbody %s\n" "$2" "${3:-x}" > "$1/$2/SKILL.md"; }
_sm() { node --no-warnings "$SM" "$@" 2>&1; }

# ── E-220.1: a first run has no evidence and must prune NOTHING ──────────────
T1="$(mktemp -d)"; D1="$T1/dst"; mkdir -p "$D1"
_mkskill "$D1" alpha; _mkskill "$D1" leftover
printf '["alpha"]' > "$T1/names.json"
_o="$(_sm apply "$D1" "$T1/names.json")"
assert_status 0 "E-220.01a: leftover survives the first (manifest-less) run" test -d "$D1/leftover"
assert_status 0 "E-220.01b: alpha survives the first run"                   test -d "$D1/alpha"
assert_contains "E-220.01c: the reason names the missing manifest" "no manifest yet" "$_o"
assert_status 0 "E-220.01d: the run records a manifest for next time" test -f "$D1/_SYNC_MANIFEST.json"

# ── E-220.2: write -> rename -> prune, the shape E-217 left behind ───────────
_o="$(_sm apply "$D1" "$T1/names.json")"
assert_status 1 "E-220.02a: second run prunes the sync-written, now-absent skill" test -d "$D1/leftover"
assert_status 0 "E-220.02b: a skill STILL in the source set is untouched"        test -d "$D1/alpha"
assert_contains "E-220.02c: the prune states all three grounds" "no longer in the source set" "$_o"

# ── E-220.3: a user-authored skill is never pruned ───────────────────────────
# The case the whole design exists for: absence from the source set is NOT evidence
# that a file is disposable.
T2="$(mktemp -d)"; D2="$T2/dst"; mkdir -p "$D2"
_mkskill "$D2" alpha
_sm record "$D2" >/dev/null            # manifest records ONLY alpha
_mkskill "$D2" my-own-skill "handwritten"
printf '["alpha"]' > "$T2/names.json"
_o="$(_sm apply "$D2" "$T2/names.json")"
assert_status 0 "E-220.03a: a skill sync never wrote is kept" test -d "$D2/my-own-skill"
assert_contains "E-220.03b: it is reported, not silently kept" "not written by sync" "$_o"

# ── E-220.4: a MODIFIED synced skill is kept and reported ────────────────────
# Sync wrote it, but a user edit outranks our bookkeeping.
T3="$(mktemp -d)"; D3="$T3/dst"; mkdir -p "$D3"
_mkskill "$D3" alpha; _mkskill "$D3" gone
_sm record "$D3" >/dev/null
printf -- "---\nname: gone\n---\nEDITED BY THE USER\n" > "$D3/gone/SKILL.md"
printf '["alpha"]' > "$T3/names.json"
_o="$(_sm apply "$D3" "$T3/names.json")"
assert_status 0 "E-220.04a: an edited synced skill survives" test -d "$D3/gone"
assert_contains "E-220.04b: the edit is the stated reason" "modified since sync wrote it" "$_o"

# ── E-220.5: --prune-known removes ONLY a byte-identical leftover ────────────
# The E-217 shape specifically: `.agents/skills/ai-task` holding an exact copy of a
# skill that now lives under another name. Identity is the evidence — a byte-for-byte
# match with a CURRENT canonical skill carries nothing a user could lose.
T4="$(mktemp -d)"; S4="$T4/src"; D4="$T4/dst"; mkdir -p "$S4" "$D4"
_mkskill "$S4" arch-task "TASKBODY"
_mkskill "$D4" arch-task "TASKBODY"
cp -R "$D4/arch-task" "$D4/ai-task"          # a true copy, as a rename leaves behind
_mkskill "$D4" genuinely-mine "DIFFERENT"
printf '["arch-task"]' > "$T4/names.json"; printf '["%s"]' "$S4" > "$T4/canon.json"
_o="$(_sm apply "$D4" "$T4/names.json" --prune-known --canon "$T4/canon.json")"
assert_status 1 "E-220.05a: the byte-identical leftover is removed" test -d "$D4/ai-task"
assert_status 0 "E-220.05b: a DIFFERENT orphan is kept"             test -d "$D4/genuinely-mine"
assert_status 0 "E-220.05c: the canonical skill itself is kept"     test -d "$D4/arch-task"
assert_contains "E-220.05d: identity is the stated ground" "byte-identical" "$_o"

# Without the flag the same fixture must keep everything — the flag is the whole
# difference, so a default-on regression fails here.
T5="$(mktemp -d)"; S5="$T5/src"; D5="$T5/dst"; mkdir -p "$S5" "$D5"
_mkskill "$S5" arch-task "TASKBODY"; _mkskill "$D5" arch-task "TASKBODY"
cp -R "$D5/arch-task" "$D5/ai-task"
printf '["arch-task"]' > "$T5/names.json"; printf '["%s"]' "$S5" > "$T5/canon.json"
_sm apply "$D5" "$T5/names.json" --canon "$T5/canon.json" >/dev/null
assert_status 0 "E-220.05e: WITHOUT --prune-known the identical leftover stays" test -d "$D5/ai-task"

# ── E-220.6: refuse to prune when the source list is unusable ────────────────
# An empty source set makes every entry look "gone upstream". Exiting non-zero rather
# than pruning against nothing is the difference between a no-op and wiping a workspace.
T6="$(mktemp -d)"; D6="$T6/dst"; mkdir -p "$D6"; _mkskill "$D6" alpha
_sm record "$D6" >/dev/null
assert_status 3 "E-220.06a: a missing source list refuses to prune" \
  node --no-warnings "$SM" apply "$D6" "$T6/absent.json"
printf 'not json' > "$T6/bad.json"
assert_status 3 "E-220.06b: an unparseable source list refuses to prune" \
  node --no-warnings "$SM" apply "$D6" "$T6/bad.json"
printf '{"alpha":1}' > "$T6/obj.json"
assert_status 3 "E-220.06c: a non-array source list refuses to prune" \
  node --no-warnings "$SM" apply "$D6" "$T6/obj.json"
assert_status 0 "E-220.06d: alpha survived all three refusals" test -d "$D6/alpha"

# A corrupt manifest degrades to "no evidence", never to "prune everything".
printf 'garbage{' > "$D6/_SYNC_MANIFEST.json"
printf '[]' > "$T6/empty.json"
_o="$(_sm apply "$D6" "$T6/empty.json")"
assert_status 0 "E-220.06e: a corrupt manifest keeps everything" test -d "$D6/alpha"

# ── E-220.7: the manifest itself is never treated as a managed entry ─────────
_o="$(_sm plan "$D6" "$T6/empty.json")"
assert_not_contains "E-220.07a: _SYNC_MANIFEST.json is not a prune candidate" "_SYNC_MANIFEST" "$_o"
assert_not_contains "E-220.07b: the generated index is not a prune candidate" "_SKILLS_INDEX" "$_o"

# ── E-220.8: plan is read-only, apply is the only mode that deletes ──────────
T7="$(mktemp -d)"; D7="$T7/dst"; mkdir -p "$D7"; _mkskill "$D7" alpha; _mkskill "$D7" stale
_sm record "$D7" >/dev/null
printf '["alpha"]' > "$T7/names.json"
_o="$(_sm plan "$D7" "$T7/names.json")"
assert_contains "E-220.08a: plan reports the prune"  "PRUNE stale" "$_o"
assert_status 0 "E-220.08b: plan deletes nothing"    test -d "$D7/stale"
_sm apply "$D7" "$T7/names.json" >/dev/null
assert_status 1 "E-220.08c: apply performs it"       test -d "$D7/stale"

# ── E-220.9: `ai sync` end-to-end in a NON-GIT dir exits 0 ───────────────────
# A fresh clone has no manifest anywhere, and the helper is located relative to the
# repo root — which `git rev-parse` cannot supply here. Exiting non-zero would break
# every fresh install, so this is the case that guards the locator's fallback.
T8="$(mktemp -d)"; mkdir -p "$T8/.ai"
cp "${REPO_ROOT}/.ai/roles.json" "$T8/.ai/roles.json" 2>/dev/null || true
_o="$(cd "$T8" && AI_OS_HOME="${AIOS:-$HOME/.ai-os}" bash "$AI_BIN" sync 2>&1)"; _rc=$?
assert_status 0 "E-220.09a: sync exits 0 in a fresh non-git dir" test "$_rc" -eq 0
assert_not_contains "E-220.09b: no unbound-variable abort" "unbound variable" "$_o"
assert_status 0 "E-220.09c: the workspace was still provisioned" test -d "$T8/.claude/skills"

# ── E-220.11: the REAL `ai sync` prunes end-to-end ───────────────────────────
# Case 09 asserts exit 0, and a silently SKIPPED prune satisfies that just as well as a
# working one — which is how the first cut shipped a locator that resolved
# `git rev-parse --show-toplevel` (the USER's repo, not the AI-OS install) and never ran
# at all. These assertions pin the observable effect, not the exit code.
TA="$(mktemp -d)"; mkdir -p "$TA/.ai"
# E-244: bind the Architect to agy EXPLICITLY rather than copying this repo's roles.json.
# Under the D-066 all-Claude default no role is bound to agy, so .agents/ is never
# provisioned — and 11b, which exists to prove the manifest covers MORE than .claude,
# would fail for the one reason it is not testing. A fixture that asserts "every
# provisioned workspace" must be the one that decides which are provisioned.
cat > "$TA/.ai/roles.json" <<'JSON'
{ "roles": { "architect": {"provider":"agy","pane_identifier":"1"},
             "engineer":  {"provider":"claude","pane_identifier":"0","model":"opus"} } }
JSON
(cd "$TA" && bash "$AI_BIN" sync >/dev/null 2>&1)
assert_status 0 "E-220.11a: the first real sync records a manifest" \
  test -f "$TA/.claude/skills/_SYNC_MANIFEST.json"
assert_status 0 "E-220.11b: every provisioned workspace is covered, not just .claude" \
  test -f "$TA/.agents/skills/_SYNC_MANIFEST.json"
# A renamed-away skill: a copy sync itself recorded, now absent upstream.
_seed="$(find "$TA/.claude/skills" -maxdepth 1 -mindepth 1 -type d | head -1)"
cp -R "$_seed" "$TA/.claude/skills/zz-renamed-away"
mkdir -p "$TA/.claude/skills/zz-user-authored"
printf -- "---\nname: zz-user-authored\n---\nmine\n" > "$TA/.claude/skills/zz-user-authored/SKILL.md"
node --no-warnings "$SM" record "$TA/.claude/skills" >/dev/null 2>&1
python3 - "$TA/.claude/skills/_SYNC_MANIFEST.json" <<'PYX'
import json,sys
p=sys.argv[1]; m=json.load(open(p))
m["entries"].pop("zz-user-authored", None)   # sync never wrote this one
json.dump(m, open(p,"w"))
PYX
_o="$(cd "$TA" && bash "$AI_BIN" sync 2>&1)"
assert_status 1 "E-220.11c: the real sync prunes the renamed-away copy" \
  test -d "$TA/.claude/skills/zz-renamed-away"
assert_status 0 "E-220.11d: it keeps the user-authored skill beside it" \
  test -d "$TA/.claude/skills/zz-user-authored"
assert_contains "E-220.11e: the prune is reported to the user" "pruned zz-renamed-away" "$_o"
assert_contains "E-220.11f: the kept orphan is reported too" "orphan (kept) zz-user-authored" "$_o"
# The rollback flag must reach the real command path, not just the helper.
cp -R "$_seed" "$TA/.claude/skills/zz-renamed-again"
node --no-warnings "$SM" record "$TA/.claude/skills" >/dev/null 2>&1
(cd "$TA" && AI_OS_NO_PRUNE=1 bash "$AI_BIN" sync >/dev/null 2>&1)
assert_status 0 "E-220.11g: AI_OS_NO_PRUNE=1 leaves the leftover in place" \
  test -d "$TA/.claude/skills/zz-renamed-again"
rm -rf "$TA"

# ── E-220.12: helpers resolve relative to the SCRIPT, never the user's repo ──
# `git rev-parse --show-toplevel` inside a user project resolves to THEIR repo, so a
# project containing src/shared/<helper>.mjs got that file executed by node and its
# stdout trusted — the E-219 F3 shape.
assert_status 1 "E-220.12a: no locator resolves a helper via git rev-parse" \
  bash -c "grep -q 'rev-parse --show-toplevel.*/src/shared/' '$AI_BIN'"

# ── E-220.10: the rollback flag genuinely disables pruning ───────────────────
T9="$(mktemp -d)"; D9="$T9/dst"; mkdir -p "$D9"; _mkskill "$D9" alpha; _mkskill "$D9" stale
_sm record "$D9" >/dev/null
printf '["alpha"]' > "$T9/names.json"
assert_status 0 "E-220.10a: AI_OS_NO_PRUNE=1 is honoured by the shell caller" \
  bash -c "grep -q 'AI_OS_NO_PRUNE' '$AI_BIN'"
assert_status 0 "E-220.10b: pruning is wired into the provisioner, not one workspace" \
  bash -c "grep -q '_prune_workspace_dir \"\${ws}/skills\"' '$AI_BIN'"

# ── E-233 (D-060 §4): the artefacts sync regenerates must not dirty the project ──
# The manifest is machine-local by construction — its hashes describe what THIS machine
# wrote — so committing one hands another machine a manifest that lies, and the prune
# above then trusts that lie. Ignoring it is therefore a correctness requirement, not
# just diff hygiene. `ai init` and `ai sync` add the patterns so a project cannot end up
# permanently dirty (or, worse, tracking one).
_gi() {
  # Run the real helper against a scratch repo. Sourced by extraction rather than by
  # running `ai sync`, which would need a whole provisioned workspace to reach the call.
  ( eval "$(sed -n '/^_ensure_generated_gitignore() {/,/^}/p' "$AI_BIN")"
    cd "$1" && _ensure_generated_gitignore "." ) 2>&1
}

T10="$(mktemp -d)"
assert_status 0 "E-233.01a: init wires the helper in" \
  bash -c "grep -q '_ensure_generated_gitignore \"\.\"' '$AI_BIN'"
assert_status 0 "E-233.01b: sync wires it in too (two call sites)" \
  bash -c "[ \"\$(grep -c '_ensure_generated_gitignore \"\.\"' '$AI_BIN')\" -eq 2 ]"

# Outside a git work tree there is nothing to ignore — writing a .gitignore anyway would
# be litter in a directory the user never asked to be a repo.
_gi "$T10" >/dev/null 2>&1 || true
assert_status 1 "E-233.02a: a non-git directory gets no .gitignore" test -f "$T10/.gitignore"

G1="$T10/repo"; mkdir -p "$G1"; git -C "$G1" init -q .
_o="$(_gi "$G1")"
assert_status 0 "E-233.03a: a fresh repo gets the manifest pattern"      grep -qx '\*\*/_SYNC_MANIFEST.json' "$G1/.gitignore"
assert_status 0 "E-233.03b: and the skills index pattern"                grep -qx '\*\*/_SKILLS_INDEX.md' "$G1/.gitignore"
assert_status 0 "E-233.03c: and the blueprint index pattern"             grep -qx '\.ai/blueprints/_INDEX.md' "$G1/.gitignore"
assert_contains "E-233.03d: the addition is reported"                    "generated-artefact pattern" "$_o"

# Idempotence is the whole point: init and sync both call this, on every run.
_before="$G1/.before"; cp "$G1/.gitignore" "$_before"
_gi "$G1" >/dev/null; _gi "$G1" >/dev/null
assert_status 0 "E-233.04a: repeated runs do not append again" \
  cmp -s "$_before" "$G1/.gitignore"

# A project that already ignores the artefact by bare name is ALREADY correct; adding a
# second, differently-spelled pattern for the same file is noise in someone else's file.
G2="$T10/named"; mkdir -p "$G2"; git -C "$G2" init -q .
printf '_SKILLS_INDEX.md\n_SYNC_MANIFEST.json\n_INDEX.md\n' > "$G2/.gitignore"
_gi "$G2" >/dev/null
assert_status 0 "E-233.05a: an equivalent existing rule suppresses the append" \
  bash -c "[ \"\$(grep -c . '$G2/.gitignore' | tr -d ' ')\" -eq 3 ]"

# NON-VACUITY for 05a: a mere mention in a COMMENT is not an ignore rule, so the same
# fixture minus the real rules must still gain the pattern. Without this, 05a would pass
# just as well if the helper had stopped writing anything at all.
G3="$T10/comment"; mkdir -p "$G3"; git -C "$G3" init -q .
printf '# TODO: ignore _SYNC_MANIFEST.json and _SKILLS_INDEX.md and _INDEX.md\n' > "$G3/.gitignore"
_gi "$G3" >/dev/null
assert_status 0 "E-233.05b: a commented-out mention does not count (non-vacuity)" \
  grep -qx '\*\*/_SYNC_MANIFEST.json' "$G3/.gitignore"

# A .gitignore with no final newline: appending naively rewrites the project's LAST RULE
# into something else entirely, which is a silent change to their ignore semantics.
G4="$T10/nonl"; mkdir -p "$G4"; git -C "$G4" init -q .
printf 'node_modules' > "$G4/.gitignore"
_gi "$G4" >/dev/null
assert_status 0 "E-233.06a: a missing trailing newline does not splice the last rule" \
  grep -qx 'node_modules' "$G4/.gitignore"
assert_status 0 "E-233.06b: and the pattern still lands"  grep -qx '\*\*/_SYNC_MANIFEST.json' "$G4/.gitignore"

# This repo is the reference project: the patterns are already present, so a sync here
# must be a no-op. If this fails, `ai sync` would start dirtying the framework tree.
#
# Run against a COPY, never against $REPO_ROOT itself. A test that invokes a file-writing
# helper on the repository under test will, the first time the helper regresses, silently
# edit the real .gitignore and then pass on the next run because it fixed its own input.
G5="$T10/reference"; mkdir -p "$G5"; git -C "$G5" init -q .
cp "$REPO_ROOT/.gitignore" "$G5/.gitignore"
_gi "$G5" >/dev/null
assert_status 0 "E-233.07a: the framework repo's own rules need no change" \
  cmp -s "$REPO_ROOT/.gitignore" "$G5/.gitignore"

rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6" "$T7" "$T8" "$T9" "$T10"
assert_summary
