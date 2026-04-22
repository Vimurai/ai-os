# CAPABILITIES (Declarative Capability Schema)
# Source of truth for ai-exec and .mcp.json enforcement.
# Edit this file to define what AI agents are allowed to do in THIS project.

## filesystem.read
# Allowed path patterns for READ operations (no approval required).
- src/**
- .ai/**
- docs/**
- tests/**
- *.md
- *.json
- *.ts
- *.js
- *.sh
- ~/.ai-os/config/**
- ~/.ai-os/memory/**

## filesystem.write
# Allowed path patterns for WRITE operations (requires --allow-write in ai-exec).
- src/**
- .ai/**
- tests/**
- ~/.ai-os/memory/**

## shell.exec
# Allowed commands/patterns for EXECUTE operations (requires [SEC_CLEARED] + --allow-execute).
- npm test
- npm run build
- npm run lint
- git commit
- git add
- git status
- git diff
- ai test
# computer-use-mcp sandbox tools (E-8, SEC_CLEARED 2026-04-21, D-002)
- xdpyinfo (Linux only — Xvfb health check on DISPLAY=:99)
- scrot (Linux only — screenshot to tmp file, deleted immediately)
- xdotool (Linux only — mouse/keyboard in sandboxed DISPLAY=:99)
- screencapture (macOS only — host display, test/dev use only)
- cliclick (macOS only — mouse/keyboard, test/dev use only)
- osascript (macOS only — key combos via System Events)
- base64 (encode screenshot data, pipes from tmp file)

## network.outbound
# Allowed external domains for network operations.
- npmjs.org
- github.com
- registry.npmjs.org

## notes
# Project-specific capability notes.
# Add context here for the security_engineer to evaluate SEC_CLEARED requests.
- WRITE to .ai/ is low-risk (documentation only)
- EXECUTE of npm test/build is pre-approved (no side effects on external systems)
- Any operation touching auth, secrets, or external APIs requires explicit [SEC_CLEARED]
- WRITE to ~/.ai-os/memory/ is low-risk (architectural signatures only, no secrets per §31 sanitize())
- READ of ~/.ai-os/config/registry.json is pre-approved for compliance tools (verification-mcp, §32)
