# REVIEWS (Append-only critic stamps)
# Format: [CRITIC_STAMP] YYYY-MM-DD | [TIER_N] Summary

[CRITIC_STAMP] 2026-03-11 | [TIER_2] Blueprint aligned — 3 deviations resolved: (1) do_review dispatch fixed (${2:-} → ${@:2}, --tier flag now forwarded), (2) tests/ staged and committed, (3) install-ai-os.sh confirmed clean (no partial staging). 21/21 tests passing. Tier 2 Quality Gate satisfied.

---
[CRITIC_STAMP] 2026-03-12 | [TIER_2] Parallel 3-critic review — P0: 0 | P1: 6 | P2: 5

## critic_arch — COMPLIANT (Grade A)
- P1: Gemini CLI commands (.toml) not implemented — src/gemini/commands/ missing, Gemini slash commands non-functional
- P1: gemini_tasks.md lacks task sequencing rigor vs claude_tasks.md
- P2: Missing file templates (ARCH.md, DECISIONS.md, PII_AUDIT.md) in src/templates/
- P2: Shared agents decision undocumented in architect.md
- PASS: Domain sovereignty enforced, all 3 gates functional, MCP registry complete, Skills 2.0 done

## critic_security — 0 P0, 2 P1, 3 P2
- P1: .mcp.json + src/templates/.mcp.json contain hardcoded placeholder "your-testsprite-api-key" — must use env var
- P1: .gitignore missing .env, .env.local, *.key, *.pem, /node_modules entries
- P2: context-invoker-mcp skill/agent name input not validated — path traversal possible (../etc/passwd)
- P2: execSync in blueprint-aligner-mcp + risk-analyzer-mcp — safe now but fragile pattern
- P2: blueprint-aligner-mcp path traversal regex bypassable via URL encoding or symlinks
- PASS: safe-exec-mcp blocks rm -rf, curl|bash, secrets in commands. No env leakage found.

## critic_tests — 2 P0, 4 P1 (CRITICAL GAP)
- P0: safe-exec-mcp BLOCK_RULES completely untested — security-critical shell validation has zero tests
- P0: blueprint-aligner-mcp secret detection regex untested — hardcoded credential gate is unverified
- P1: All 8 MCP tool handlers untested (CallToolRequestSchema handlers = core business logic)
- P1: File I/O error handling untested across all MCP servers
- P1: CLI commands tested smoke-only (ai install, ai review, ai mcp-setup all missing)
- P1: No CI pipeline — .github/workflows/ is empty
- Overall coverage: ~5-10% (bash smoke tests only, no unit/integration tests)
---
