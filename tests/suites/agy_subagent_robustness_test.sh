#!/usr/bin/env bash
# agy_subagent_robustness_test.sh — E-163 / E-164 / E-165 (agy-subagent-robustness.md)
# E-163: plugin-builder harvests mcp__* tools into agent.json toolNames.
# E-164: deduplicateImports() collapses duplicate ai-os plugin registrations.
# E-165: verify_auth_token() warns on missing/expiring Antigravity OAuth token.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PB="${REPO_ROOT}/src/shared/plugin-builder.mjs"
AI_BIN="${REPO_ROOT}/src/bin/ai"

echo "── Suite: agy_subagent_robustness ───────────────────────────────────"

# ── E-163: mcp__* tool harvesting (least-privilege) ───────────────────────────
out=$(node --input-type=module -e '
import { toSubagent } from "'"${PB}"'";
const withMcp = toSubagent(
  { name: "critic_x", "allowed-tools": "Read, mcp__task-synchronizer-mcp__add_stamp, mcp__TestSprite__testsprite_bootstrap" },
  "The agent calls mcp__advisor-mcp__ask_architect in its body.",
  "critic_x"
);
const tn = withMcp.config.customAgent.toolNames;
const noMcp = toSubagent({ name: "plain", "allowed-tools": "Read, Grep" }, "no tools referenced", "plain");
const tn2 = noMcp.config.customAgent.toolNames;
console.log("FM_TOOL="     + tn.includes("mcp__task-synchronizer-mcp__add_stamp"));
console.log("MIXED_CASE="  + tn.includes("mcp__TestSprite__testsprite_bootstrap"));
console.log("BODY_TOOL="   + tn.includes("mcp__advisor-mcp__ask_architect"));
console.log("READ_KEPT="   + tn.includes("view_file"));
console.log("NO_DUPES="    + (new Set(tn).size === tn.length));
console.log("PLAIN_NOMCP=" + !tn2.some(t => t.startsWith("mcp__")));
' 2>&1)
assert_contains "E-163 harvests mcp tool from allowed-tools" "FM_TOOL=true" "$out"
assert_contains "E-163 preserves mixed-case server (TestSprite)" "MIXED_CASE=true" "$out"
assert_contains "E-163 harvests mcp tool referenced in body" "BODY_TOOL=true" "$out"
assert_contains "E-163 keeps the base read tools" "READ_KEPT=true" "$out"
assert_contains "E-163 emits no duplicate toolNames" "NO_DUPES=true" "$out"
assert_contains "E-163 grants no mcp tools when none declared (least-privilege)" "PLAIN_NOMCP=true" "$out"

# ── E-164: import_manifest deduplication ──────────────────────────────────────
TMP="$(mktemp -d)"
cat > "${TMP}/m.json" <<'JSON'
{ "imports": [
  { "name": "ai-os", "source": "antigravity",  "components": ["agents"] },
  { "name": "ai-os", "source": "local-install", "components": ["installed"] },
  { "name": "keep-me", "source": "local-install", "components": ["installed"] }
] }
JSON
ded=$(node --input-type=module -e '
import { deduplicateImports } from "'"${PB}"'";
const r1 = deduplicateImports("'"${TMP}/m.json"'");
const r2 = deduplicateImports("'"${TMP}/m.json"'"); // idempotent
import { readFileSync } from "node:fs";
const d = JSON.parse(readFileSync("'"${TMP}/m.json"'","utf8"));
const aios = d.imports.filter(i => i.name === "ai-os");
console.log("REMOVED="     + (r1.changed && r1.removed === 1));
console.log("AIOS_ONE="    + (aios.length === 1));
console.log("KEPT_SOURCE=" + (aios[0] && aios[0].source === "local-install"));
console.log("OTHER_KEPT="  + d.imports.some(i => i.name === "keep-me"));
console.log("IDEMPOTENT="  + (r2.changed === false));
' 2>&1)
assert_contains "E-164 removes the duplicate ai-os import" "REMOVED=true" "$ded"
assert_contains "E-164 leaves exactly one ai-os import" "AIOS_ONE=true" "$ded"
assert_contains "E-164 keeps the local-install source" "KEPT_SOURCE=true" "$ded"
assert_contains "E-164 preserves other plugins" "OTHER_KEPT=true" "$ded"
assert_contains "E-164 is idempotent" "IDEMPOTENT=true" "$ded"
# fail-open on a missing manifest
miss=$(node --input-type=module -e 'import { deduplicateImports } from "'"${PB}"'"; console.log(JSON.stringify(deduplicateImports("'"${TMP}"'/nope.json")));' 2>&1)
assert_contains "E-164 fail-open on missing manifest" '"changed":false' "$miss"
rm -rf "$TMP"

# ── E-165: OAuth token pre-flight ─────────────────────────────────────────────
H="$(mktemp -d)"
nocreds=$(HOME="$H" bash -c "source '${AI_BIN}'; verify_auth_token" 2>&1 || true)
assert_contains "E-165 warns when not logged in" "Not logged into Antigravity" "$nocreds"

mkdir -p "$H/.gemini"
echo '{"expiry_date":1000,"refresh_token":"x"}' > "$H/.gemini/oauth_creds.json"
expired=$(HOME="$H" bash -c "source '${AI_BIN}'; verify_auth_token" 2>&1 || true)
assert_contains "E-165 warns on expired/expiring token" "expired or expiring" "$expired"

python3 -c "import json,time;json.dump({'expiry_date':int((time.time()+3600)*1000),'refresh_token':'x'},open('$H/.gemini/oauth_creds.json','w'))"
valid=$(HOME="$H" bash -c "source '${AI_BIN}'; verify_auth_token" 2>&1 || true)
assert_not_contains "E-165 silent on a valid token" "AUTH_WARN" "$valid"
if [[ ! -d "$H/.gemini/.ai-os-token.lock" ]]; then _pass "E-165 releases the serialization lock"; else _fail "E-165 left the lock behind"; fi

skip=$(HOME="$H" AI_OS_SKIP_TOKEN_CHECK=1 bash -c "rm -f '$H/.gemini/oauth_creds.json'; source '${AI_BIN}'; verify_auth_token" 2>&1 || true)
assert_not_contains "E-165 honors AI_OS_SKIP_TOKEN_CHECK=1" "AUTH_WARN" "$skip"
rm -rf "$H"

assert_summary
