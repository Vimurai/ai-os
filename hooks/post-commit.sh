#!/usr/bin/env bash
# AI-OS post-commit Hook — state.json Primary Write + TASKS.md View Regeneration (P-44)
# Parses the latest commit message for task IDs and marks them complete in state.json,
# then regenerates TASKS.md as a view. Falls back with a warning if state.json is absent.
#
# Syntax recognised in commit messages:
#   Fixes E-12 / Closes P-03 / Implemented T-07
#   (case-insensitive; multiple IDs per commit are all processed)

COMMIT_MSG=$(git log -1 --format="%s %b" 2>/dev/null || true)
[[ -z "$COMMIT_MSG" ]] && exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
STATE_FILE="${REPO_ROOT}/.ai/state.json"
TASKS_FILE="${REPO_ROOT}/.ai/TASKS.md"

[[ -f "$TASKS_FILE" ]] || exit 0

# Extract all task IDs referenced with Fixes/Closes/Implemented keywords
IDS=$(printf '%s' "$COMMIT_MSG" \
  | grep -oiE '(fixes|closes|implemented)[[:space:]]+(E|P|T)-[0-9]+' \
  | grep -oE '(E|P|T)-[0-9]+' || true)

[[ -z "$IDS" ]] && exit 0

# Warn and exit if state.json is missing — do NOT fall back to sed mutation (P-44)
if [[ ! -f "$STATE_FILE" ]]; then
  printf "[TASK-SYNC] WARN: state.json not found — run: ai migrate-state to enable task sync.\n" >&2
  exit 0
fi

if ! command -v node &>/dev/null; then
  printf "[TASK-SYNC] WARN: node not found — cannot sync state.json.\n" >&2
  exit 0
fi

LOCK_FILE="${STATE_FILE}.lock"

# Portable atomic lock using mkdir (POSIX-safe; works on macOS and Linux without flock)
acquire_lock() {
  local retries=20
  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    retries=$((retries - 1))
    [[ $retries -le 0 ]] && return 1
    sleep 0.1
  done
  return 0
}
release_lock() { rmdir "$LOCK_FILE" 2>/dev/null || true; }

for ID in $IDS; do
  if ! acquire_lock; then
    printf "[TASK-SYNC] Could not acquire lock for %s — skipping.\n" "$ID" >&2
    continue
  fi

  # Primary write: update state.json, then regenerate TASKS.md as a view
  node -e "
    const fs   = require('fs');
    const path = require('path');

    const statePath  = process.argv[1];
    const tasksPath  = process.argv[2];
    const taskId     = process.argv[3];

    let state;
    try {
      state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    } catch (e) {
      process.stderr.write('[TASK-SYNC] state.json parse error: ' + e.message + '\n');
      process.exit(1);
    }

    const task = (state.tasks || []).find(t => t.id === taskId);
    if (!task) {
      process.stderr.write('[TASK-SYNC] ' + taskId + ' not found in state.json — skipping.\n');
      process.exit(0);
    }

    if (task.status === 'DONE') {
      process.stderr.write('[TASK-SYNC] ' + taskId + ' already DONE — skipping.\n');
      process.exit(0);
    }

    task.status       = 'DONE';
    task.completed_at = new Date().toISOString();

    // Write state.json first
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n', 'utf8');

    // Regenerate TASKS.md as a view from state.json
    if (state.tasks.length > 0) {
      const lines = ['# TASKS (Generated from state.json)', ''];
      const byOwner = {};
      for (const t of state.tasks) {
        const owner = t.owner || 'Unassigned';
        if (!byOwner[owner]) byOwner[owner] = [];
        byOwner[owner].push(t);
      }
      for (const [owner, tasks] of Object.entries(byOwner)) {
        lines.push('## ' + owner);
        for (const t of tasks) {
          const check   = t.status === 'DONE' ? 'x' : ' ';
          const tierStr = t.tier ? ' | Tier: ' + t.tier : '';
          lines.push('- [' + check + '] ' + t.id + ': ' + t.description + tierStr);
          if (t.status === 'DONE' && t.completed_at) {
            lines.push('  Status: DONE ' + t.completed_at.split('T')[0] + ' — ' + (t.summary || 'Complete'));
          }
        }
        lines.push('');
      }
      fs.writeFileSync(tasksPath, lines.join('\n'), 'utf8');
    }

    process.stderr.write('[TASK-SYNC] Marked ' + taskId + ' as DONE.\n');
  " "$STATE_FILE" "$TASKS_FILE" "$ID" 2>&1 >&2 || true

  release_lock
done

rm -f "$LOCK_FILE" 2>/dev/null || true

exit 0
