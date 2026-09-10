#!/usr/bin/env node
// resolve-launch.mjs — resolve a ROLE to its provider + launch argv.
//
// WHY THIS EXISTS (E-208 review, critic_tests P2): `ai pane <role>` previously
// carried this resolution as an inline `node --input-type=module -e '...'` snippet
// while the test suite exercised provider-adapter.mjs directly. Two copies of the
// same logic, and neither test would fail if they drifted. This file is the single
// executable seam both use, so a change to the launch contract cannot pass tests
// while breaking the launcher.
//
// Usage:  node resolve-launch.mjs <role> <aiDir>
// Output: line 1 = provider name, remaining lines = argv (one element per line).
// Exit:   0 ok | 2 role not mapped to a provider | 3 bad usage.
//
// One element per line (not JSON) so the bash caller can read it with a plain
// `while read` loop and keep argv elements intact even when they contain spaces.

import { roleProvider, roleModel, providerAdapter, buildArgv, absolutisePathOperands } from "./provider-adapter.mjs";
import { dirname, resolve } from "node:path";

const [, , role, aiDir] = process.argv;
if (!role || !aiDir) {
  process.stderr.write("usage: resolve-launch.mjs <role> <aiDir>\n");
  process.exit(3);
}

const provider = roleProvider(aiDir, role);
if (!provider) process.exit(2);

const adapter = providerAdapter(aiDir, provider);
// The rulefile is what makes a same-provider Triad work: without ARCHITECT.md
// appended, a claude Architect pane boots the ENGINEER persona from CLAUDE.md (G1).
const rulefile = role === "architect" ? "ARCHITECT.md" : "ENGINEER.md";
const argv = buildArgv(adapter.launch, {
  role,
  rulefile,
  model: roleModel(aiDir, role),
});

// E-242 (D-066): the adapter templates emit PROJECT-RELATIVE paths, which only resolve
// when the CLI's cwd is the project root. A pane opened in a subdirectory, or one whose
// rc-file `cd`s, made the CLI report "Settings file not found" for a file that exists.
//
// Anchoring here rather than in the templates fixes every project at once, including one
// whose .ai/providers.json predates this change and still carries the relative form —
// editing the default template alone would leave those broken.
const projectRoot = resolve(dirname(resolve(aiDir)));
const anchored = absolutisePathOperands(argv, projectRoot);

process.stdout.write([provider, ...anchored].join("\n"));
