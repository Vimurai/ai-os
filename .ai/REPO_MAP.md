# REPO_MAP.md — AST Repository Map (auto-generated)
<!-- ast-parser-mcp generate_map (E-97): 34/52 files, budget 2048 tokens. `⋮` = elided function body. -->

## src/shared/telemetry.mjs  (centrality 1)
exports: TELEMETRY_SERVICE, TELEMETRY_DB_PATH, USAGE_DB_PATH, recordToolExecution, recordTaskVelocity, recordTaskVelocityForTask, getTelemetryStats, resetTelemetryCache
imports: node:sqlite, node:crypto, node:fs, node:path, node:os, node:url

## src/mcp/shared/is-main.mjs  (centrality 0.9668)
exports: isMainModule
imports: node:url

## src/shared/mcp-telemetry.mjs  (centrality 0.9668)
exports: TELEMETRY_STATUS, toolNameFor, statusForResult, withTelemetry, instrument
imports: ./telemetry.mjs

## src/mcp/shared/logger.js  (centrality 0.9427)
exports: createLogger

## src/mcp/shared/state-db.js  (centrality 0.3955)
exports: getDb, parseDeps, readState, roleFromOwner, regenerateViews, MAX_DAG_DEPTH, readDependencyGraph, validateDag, withTransaction, nextId, recordIdHighWater, DONE_ARCHIVE_THRESHOLD, DONE_KEEP_RECENT, STAMP_ARCHIVE_THRESHOLD, STAMP_KEEP_RECENT, archiveDoneTasks, archiveStamps, nextTopicSeedId, nextClusterPageId
imports: fs, path, node:sqlite

## src/shared/instinct-stager.mjs  (centrality 0.2627)
exports: MIN_CONFIDENCE, isSafeSlug, scanDangerousContent, slugify, validateInstinct, renderProposedSkill, stageInstincts
imports: node:fs, node:path

## src/mcp/ast-parser-mcp/extractor.mjs  (centrality 0.1661)
exports: PARSE_TIMEOUT_MICROS, languageForFile, initParsers, extractSymbols, extractFromSource
imports: web-tree-sitter, node:url, node:path

## src/mcp/ast-parser-mcp/repo-mapper.mjs  (centrality 0.1661)
exports: normalizePath, resolveImport, buildDependencyGraph, pageRank, rankSymbols

## src/mcp/ast-parser-mcp/serializer.mjs  (centrality 0.1661)
exports: DEFAULT_MAX_TOKENS, estimateTokens, renderFileBlock, serializeRepoMap

## src/mcp/shared/mcp-domains.mjs  (centrality 0.1661)
exports: DOMAINS, domainForServer

## src/mcp/task-synchronizer-mcp/tool-schemas.mjs  (centrality 0.1541)
exports: buildToolSchemas

## src/shared/managed-agents-client.mjs  (centrality 0.1541)
exports: isEnabled, projectState, syncToCloud, cancelPendingSync, migrateLegacyToSteps, sendSteps, diagnostics
imports: node:sqlite, node:crypto, node:fs, node:path

## src/shared/schema-validator.js  (centrality 0.1541)
exports: validate, loadSchemas, validateNamed
imports: node:fs, node:path, node:url

## src/shared/seo-cluster-intents.mjs  (centrality 0.1541)
exports: SEO_PILLAR_INTENT, SEO_CLUSTER_INTENTS, SEO_ALL_INTENTS, SEO_CLUSTER_INTENTS_SET, SEO_ALL_INTENTS_SET, MAX_CLUSTER_PAGES_PER_SEED, isValidIntentType, isClusterIntent

## src/shared/signal-handoff.mjs  (centrality 0.1541)
exports: VALID_TARGETS, emitHandoff, findAiDir, defaultMessage
imports: node:fs, node:path

## scripts/generate_blueprints_index.mjs  (centrality 0.142)
imports: node:fs, node:path

## scripts/generate_mcp_docs.mjs  (centrality 0.142)
imports: node:fs, node:path, node:url, node:os

## scripts/standards.mjs  (centrality 0.142)
imports: node:path, node:fs, node:url, node:os

## src/mcp/advisor-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, child_process, fs, path, ../shared/logger.js

## src/mcp/approval-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:sqlite, node:readline, node:fs, node:path, node:os, ../shared/logger.js

## src/mcp/archive-manager-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, readline, path, ../shared/logger.js, ../shared/state-db.js

## src/mcp/ast-parser-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, node:fs, node:path, ./extractor.mjs, ./repo-mapper.mjs, ./serializer.mjs, ../../shared/mcp-telemetry.mjs

## src/mcp/blueprint-aligner-mcp/index.js  (centrality 0.142)
exports: parseDiffByFile, isMarkdownFile, isPackageJsonFile, isJsonFile, traversalOutsideBackticks, isTestHelperFile, isInternalPathBuilder
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, child_process, fs, path, ../shared/logger.js

## src/mcp/cache-manager-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:sqlite, node:fs, node:path, node:os, ../shared/logger.js

## src/mcp/code-execution-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:child_process, ../shared/logger.js

## src/mcp/computer-use-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, child_process, fs, os, path, ../shared/logger.js

## src/mcp/context-guardian-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, path, child_process, ../shared/state-db.js, ../shared/logger.js

## src/mcp/context-invoker-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, path, os, ../shared/logger.js

## src/mcp/github-bridge-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, child_process, ../shared/logger.js

## src/mcp/lsp-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, path, module, child_process, ../shared/logger.js, typescript

## src/mcp/mcp-router/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:child_process, node:fs, node:path, node:os, ../shared/logger.js, ../shared/mcp-domains.mjs, ../../shared/telemetry.mjs

## src/mcp/memory-manager-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, path, ../shared/logger.js

## src/mcp/orchestrator-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, path, child_process, ../shared/state-db.js, ../shared/logger.js

## src/mcp/patch-mcp/index.js  (centrality 0.142)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, path, crypto, ../shared/logger.js
