#!/usr/bin/env node
// arch-write-cases.mjs — E-216 case driver.
//
// WHY A NODE DRIVER RATHER THAN BASH CASES: these payloads depend on their own exact
// quoting (`awk 'BEGIN{print "x" > "src/x"}'`), and a bash test file consumed those
// quotes twice during development — turning `>` inside an awk program into a real shell
// redirection and making a genuine bypass look like a pass. Passing each command as a
// single argv element removes the shell from the loop entirely.
//
// Usage: node arch-write-cases.mjs <safe-exec path> <cases.json>
// Prints one `ok|FAIL <verdict> <command>` line per case; exits 1 on any mismatch.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const [, , safeExec, casesFile] = process.argv;
if (!safeExec || !casesFile) {
  process.stderr.write("usage: arch-write-cases.mjs <safe-exec.js> <cases.json>\n");
  process.exit(2);
}

const verdict = (cmd, role) => {
  try {
    execFileSync("node", ["--no-warnings", safeExec, "--check", cmd], {
      env: { ...process.env, AI_OS_CALLER_ROLE: role },
      stdio: "ignore",
      timeout: 20_000,
    });
    return "pass";
  } catch (e) {
    return e.status === 2 ? "BLOCK" : "pass";
  }
};

const cases = JSON.parse(readFileSync(casesFile, "utf8"));
let fails = 0;
for (const c of cases) {
  const role = c.role || "architect";
  const got = verdict(c.cmd, role);
  const ok = got === c.want;
  if (!ok) fails++;
  process.stdout.write(`${ok ? "ok" : "FAIL"}\t${got}\t${role}\t${c.label || c.cmd}\n`);
}
process.exit(fails === 0 ? 0 : 1);
