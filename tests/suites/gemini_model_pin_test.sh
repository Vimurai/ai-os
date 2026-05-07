#!/usr/bin/env bash
# gemini_model_pin_test.sh — Tests for E-45 May 2026 API upgrades.
#
# Verifies:
#   • registry.json carries gemini.default_model + interactions_api_schema
#   • bin/ai propagates them into .gemini/settings.json on sync
#   • GEMINI.md template + active mirror state the mandate
#   • GEMINI_MODEL env override wins over registry default

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== gemini_model_pin_test.sh ====="

# ── T-GMP-S01: registry.json gemini block ─────────────────────────────────────
echo ""
echo "  [T-GMP-S01] registry.json carries gemini block"

assert_status 0 "default_model is gemini-3.1-pro" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (r?.gemini?.default_model !== 'gemini-3.1-pro') process.exit(1);
JS

assert_status 0 "interactions_api_schema is 'steps'" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (r?.gemini?.interactions_api_schema !== 'steps') process.exit(1);
JS

assert_status 0 "rollback note documents env override" \
  bash -c "grep -q 'GEMINI_MODEL' '${REPO_ROOT}/src/config/registry.json'"

# ── T-GMP-S02: GEMINI.md mandate ──────────────────────────────────────────────
echo ""
echo "  [T-GMP-S02] GEMINI.md mandate"

for f in "${REPO_ROOT}/src/templates/GEMINI.md" "${REPO_ROOT}/GEMINI.md"; do
  assert_status 0 "${f#${REPO_ROOT}/} exists" test -f "$f"
  assert_status 0 "${f#${REPO_ROOT}/} mandates gemini-3.1-pro" \
    grep -q 'gemini-3.1-pro' "$f"
  assert_status 0 "${f#${REPO_ROOT}/} cites the steps schema migration" \
    grep -qE '`steps`[[:space:]]+array' "$f"
done

# ── T-GMP-S03: bin/ai propagator wires the registry block ────────────────────
echo ""
echo "  [T-GMP-S03] bin/ai propagator"

# The propagator lives inline in _configure_project_gemini_settings.
# Assert the python block reads gemini_cfg from registry and writes model
# + interactions_api_schema, honouring GEMINI_MODEL env override.
assert_status 0 "reads reg.gemini block" \
  grep -q 'gemini_cfg = reg.get("gemini")' "${REPO_ROOT}/src/bin/ai"

assert_status 0 "honours GEMINI_MODEL env override" \
  grep -q 'os.environ.get("GEMINI_MODEL")' "${REPO_ROOT}/src/bin/ai"

assert_status 0 "writes model into settings" \
  grep -q 'data\["model"\] = default_model' "${REPO_ROOT}/src/bin/ai"

assert_status 0 "preserves user-set model (no clobber)" \
  grep -q 'not data.get("model")' "${REPO_ROOT}/src/bin/ai"

assert_status 0 "writes interactions_api_schema into settings" \
  grep -q 'data\["interactions_api_schema"\] = api_schema' "${REPO_ROOT}/src/bin/ai"

# ── T-GMP-S04: .gemini/settings.json reflects the pin ────────────────────────
echo ""
echo "  [T-GMP-S04] Active .gemini/settings.json"

if [[ -f "${REPO_ROOT}/.gemini/settings.json" ]]; then
  assert_status 0 "active settings.json model = gemini-3.1-pro" \
    node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('${REPO_ROOT}/.gemini/settings.json', 'utf8'));
if (s.model !== 'gemini-3.1-pro') process.exit(1);
JS
  assert_status 0 "active settings.json schema = steps" \
    node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('${REPO_ROOT}/.gemini/settings.json', 'utf8'));
if (s.interactions_api_schema !== 'steps') process.exit(1);
JS
else
  echo "  ⚠  .gemini/settings.json absent — skipping active-pin check"
fi

# ── T-GMP-S05: GEMINI_MODEL env override behaviour ───────────────────────────
echo ""
echo "  [T-GMP-S05] GEMINI_MODEL env override"

# Run the propagator's logic in isolation against a temp dir to confirm the
# env override wins over the registry default. We replicate the relevant
# python excerpt (no shell side-effects, no global ~/.ai-os mutation).
TMPDIR_OVR="$(mktemp -d -t aios-gmp-XXXXXX)"
mkdir -p "${TMPDIR_OVR}/.gemini"

cat > "${TMPDIR_OVR}/run.py" <<'PY'
import json, os, sys
target_dir = sys.argv[1]
registry_path = sys.argv[2]
path = os.path.join(target_dir, "settings.json")
gemini_cfg = {}
if os.path.exists(registry_path):
    with open(registry_path) as f:
        reg = json.load(f)
    gemini_cfg = reg.get("gemini") or {}
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f) or {}
default_model = os.environ.get("GEMINI_MODEL") or gemini_cfg.get("default_model")
api_schema = gemini_cfg.get("interactions_api_schema")
if default_model and not data.get("model"):
    data["model"] = default_model
if api_schema and not data.get("interactions_api_schema"):
    data["interactions_api_schema"] = api_schema
with open(path, "w") as f:
    json.dump(data, f)
PY

# Default registry path → gemini-3.1-pro.
GEMINI_MODEL="" python3 "${TMPDIR_OVR}/run.py" "${TMPDIR_OVR}/.gemini" "${REPO_ROOT}/src/config/registry.json"
DEFAULT_MODEL="$(python3 -c "import json;print(json.load(open('${TMPDIR_OVR}/.gemini/settings.json'))['model'])")"
assert_status 0 "registry default lands as gemini-3.1-pro" \
  bash -c "[[ '$DEFAULT_MODEL' == 'gemini-3.1-pro' ]]"

# With env override → override wins on a fresh settings file.
rm -f "${TMPDIR_OVR}/.gemini/settings.json"
GEMINI_MODEL="gemini-2.5-pro" python3 "${TMPDIR_OVR}/run.py" "${TMPDIR_OVR}/.gemini" "${REPO_ROOT}/src/config/registry.json"
OVR_MODEL="$(python3 -c "import json;print(json.load(open('${TMPDIR_OVR}/.gemini/settings.json'))['model'])")"
assert_status 0 "GEMINI_MODEL env overrides default" \
  bash -c "[[ '$OVR_MODEL' == 'gemini-2.5-pro' ]]"

# User-set model in existing file is preserved (no clobber).
echo '{"model":"my-custom-model"}' > "${TMPDIR_OVR}/.gemini/settings.json"
GEMINI_MODEL="" python3 "${TMPDIR_OVR}/run.py" "${TMPDIR_OVR}/.gemini" "${REPO_ROOT}/src/config/registry.json"
KEPT_MODEL="$(python3 -c "import json;print(json.load(open('${TMPDIR_OVR}/.gemini/settings.json'))['model'])")"
assert_status 0 "user-set model preserved across sync" \
  bash -c "[[ '$KEPT_MODEL' == 'my-custom-model' ]]"

rm -rf "$TMPDIR_OVR"

assert_summary
