// traversal-policy.mjs — how `run_review` grades a `../` in a diff (E-222, D-057 §2).
//
// WHY THIS EXISTS:
//   The check was one flat regex — any added line containing `../`, `/etc/` or `/root/`
//   was a P0 that BLOCKED the commit. That is right for a path assembled from runtime
//   input and wrong for the ordinary idiom of resolving a file relative to the script
//   that needs it. It blocked E-220's own fix for a real vulnerability, on a line
//   (`"${_sd}/../shared/sync-manifest.mjs"`) whose shape already existed at four other
//   sites in the same file — they simply were not in that diff.
//
//   A gate that fires on correct code teaches people to route around it, which costs more
//   than the check earns. So the severity now depends on what the `../` is ANCHORED to:
//
//     /etc/ or /root/                          → P0, unchanged
//     `../` anchored to a script-relative base → P1 advisory (still reported)
//     `../` anywhere else                      → P0, unchanged
//
//   Advisory, not silent: a P1 still appears in the report, so a reviewer sees every
//   traversal. Only the BLOCKING changes.
//
// Rollback: AI_OS_REVIEW_STRICT_TRAVERSAL=1 restores the flat regex (every `../` is P0).

/**
 * Bases that make a `../` script-relative rather than input-relative. Kept as ONE
 * exported constant so the policy has a single definition and the fixtures can enumerate
 * it — a second copy in the checker is how the two would drift apart.
 */
/**
 * Build an anchor matcher: the base pattern, then only the characters that can
 * legitimately sit between a script-relative base and the `../` it prefixes.
 *
 * The tail excludes `/`, `;` and `+` deliberately. An earlier cut allowed any non-slash
 * tail, which let a DISTANT anchor excuse an unrelated traversal on the same line —
 * `a("${_sd}"); b(x + "/../")` graded advisory because `${_sd}` appeared earlier in the
 * line, even though the dangerous `../` was concatenated onto a variable. A statement
 * separator or a concatenation between the two means they are not the same path, so the
 * anchor does not vouch for it. Quotes, parens, commas and `&&` stay allowed, because
 * the real idioms are wrapped in them: `join(__dirname, "../x")` and
 * `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../src"`.
 */
function anchored(base) {
  return new RegExp(base.source + '[^/;+]*\\/?$');
}

export const SCRIPT_RELATIVE_ANCHORS = [
  { name: "__dirname",        re: anchored(/__dirname/) },
  { name: "import.meta.url",  re: anchored(/import\.meta\.url/) },
  { name: "fileURLToPath",    re: anchored(/fileURLToPath\([^)]*\)/) },
  { name: "BASH_SOURCE",      re: anchored(/BASH_SOURCE(\[[^\]]*\])?/) },
  { name: "$0",               re: anchored(/\$0/) },
  // Shell variables conventionally holding "the directory of this script".
  { name: "self_dir",         re: anchored(/\$\{?_?(SELF_DIR|self_dir|_sd|SCRIPT_DIR|script_dir)\}?/) },
  // Install-mirror roots: these are OUR directories, not a path built from input.
  // Bare `~` is deliberately NOT an anchor — too easy to hit in prose, and it does not
  // expand inside the quoted contexts these paths actually appear in.
  { name: "install mirror",   re: anchored(/(\$\{?AIOS\}?|\$\{?AI_OS_HOME[^}]*\}?|\.ai-os|\$\{?HOME\}?)/) },
  // node's own "resolve relative to this module" idiom.
  { name: "new URL(...)",     re: /new URL\(\s*["'`]?$/ },
];

const RUNTIME_P0 = /(\/etc\/|\/root\/)/;

/**
 * Grade one added diff line.
 * @returns {{severity: "P0"|"P1"|null, detail: string, anchor?: string}}
 */
export function classifyTraversalLine(line, { strict = false } = {}) {
  const text = String(line ?? "");
  const detail = text.trim().slice(0, 80);

  // Absolute system paths are never anchored to anything and stay P0 in both modes.
  if (RUNTIME_P0.test(text)) return { severity: "P0", detail };
  if (!text.includes("../")) return { severity: null, detail };
  if (strict) return { severity: "P0", detail };

  // Every `../` in the line must be anchored for the line to be advisory. One
  // unanchored occurrence is enough to keep it blocking — a line may legitimately
  // carry both, and the dangerous one governs.
  let idx = text.indexOf("../");
  let matchedAnchor = null;
  while (idx !== -1) {
    const before = text.slice(0, idx);
    const hit = SCRIPT_RELATIVE_ANCHORS.find((a) => a.re.test(before));
    if (!hit) return { severity: "P0", detail };
    matchedAnchor = matchedAnchor || hit.name;
    idx = text.indexOf("../", idx + 3);
  }
  return { severity: "P1", detail, anchor: matchedAnchor };
}

/**
 * Grade a whole diff. Returns the worst severity found plus its detail, or null.
 * Added lines only (`^+` and not `+++`), matching the original check.
 */
export function classifyTraversal(diff, { strict = false } = {}) {
  const added = String(diff ?? "").split("\n").filter((l) => /^\+[^+]/.test(l));
  let advisory = null;
  for (const line of added) {
    const v = classifyTraversalLine(line, { strict });
    if (v.severity === "P0") return v;
    if (v.severity === "P1" && !advisory) advisory = v;
  }
  return advisory;
}
