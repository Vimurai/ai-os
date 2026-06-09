# REPO_MAP.md — AST Repository Map (auto-generated)
<!-- ast-parser-mcp generate_map (E-97): 36/49 files, budget 2048 tokens. `⋮` = elided function body. -->

## src/mcp/shared/logger.js  (centrality 1)
exports: createLogger

## src/mcp/shared/state-db.js  (centrality 0.2207)
exports: getDb, parseDeps, readState, roleFromOwner, regenerateViews, MAX_DAG_DEPTH, readDependencyGraph, validateDag, withTransaction, nextId, recordIdHighWater, DONE_ARCHIVE_THRESHOLD, DONE_KEEP_RECENT, STAMP_ARCHIVE_THRESHOLD, STAMP_KEEP_RECENT, archiveDoneTasks, archiveStamps, nextTopicSeedId, nextClusterPageId
imports: fs, path, node:sqlite

## src/shared/instinct-stager.mjs  (centrality 0.1106)
exports: MIN_CONFIDENCE, isSafeSlug, scanDangerousContent, slugify, validateInstinct, renderProposedSkill, stageInstincts
imports: node:fs, node:path

## src/mcp/ast-parser-mcp/extractor.mjs  (centrality 0.0767)
exports: PARSE_TIMEOUT_MICROS, languageForFile, initParsers, extractSymbols, extractFromSource
imports: web-tree-sitter, node:url, node:path

## src/mcp/ast-parser-mcp/repo-mapper.mjs  (centrality 0.0767)
exports: normalizePath, resolveImport, buildDependencyGraph, pageRank, rankSymbols

## src/mcp/ast-parser-mcp/serializer.mjs  (centrality 0.0767)
exports: DEFAULT_MAX_TOKENS, estimateTokens, renderFileBlock, serializeRepoMap

## src/mcp/shared/mcp-domains.mjs  (centrality 0.0767)
exports: DOMAINS, domainForServer

## src/shared/telemetry.mjs  (centrality 0.0767)
exports: TELEMETRY_SERVICE, TELEMETRY_DB_PATH, recordToolExecution, recordTaskVelocity, getTelemetryStats, resetTelemetryCache
imports: node:sqlite, node:crypto, node:fs, node:path, node:os, node:url

## src/mcp/task-synchronizer-mcp/tool-schemas.mjs  (centrality 0.0683)
exports: buildToolSchemas

## src/shared/managed-agents-client.mjs  (centrality 0.0683)
exports: isEnabled, projectState, syncToCloud, cancelPendingSync, migrateLegacyToSteps, sendSteps, diagnostics
imports: node:sqlite, node:crypto, node:fs, node:path

## src/shared/schema-validator.js  (centrality 0.0683)
exports: validate, loadSchemas, validateNamed
imports: node:fs, node:path, node:url

## src/shared/seo-cluster-intents.mjs  (centrality 0.0683)
exports: SEO_PILLAR_INTENT, SEO_CLUSTER_INTENTS, SEO_ALL_INTENTS, SEO_CLUSTER_INTENTS_SET, SEO_ALL_INTENTS_SET, MAX_CLUSTER_PAGES_PER_SEED, isValidIntentType, isClusterIntent

## scripts/generate_blueprints_index.mjs  (centrality 0.0598)
imports: node:fs, node:path

## scripts/generate_mcp_docs.mjs  (centrality 0.0598)
imports: node:fs, node:path, node:url, node:os

## scripts/standards.mjs  (centrality 0.0598)
imports: node:path, node:fs, node:url, node:os

## src/mcp/advisor-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, child_process, fs, path, ../shared/logger.js

## src/mcp/approval-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, node:sqlite, node:readline, node:fs, node:path, node:os, ../shared/logger.js

## src/mcp/archive-manager-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, readline, path, ../shared/logger.js, ../shared/state-db.js

## src/mcp/ast-parser-mcp/index.js  (centrality 0.0598)
imports: node:fs, node:path, ./extractor.mjs, ./repo-mapper.mjs, ./serializer.mjs

## src/mcp/blueprint-aligner-mcp/index.js  (centrality 0.0598)
exports: parseDiffByFile, isMarkdownFile, isPackageJsonFile, isJsonFile, traversalOutsideBackticks, isTestHelperFile, isInternalPathBuilder
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, child_process, fs, path, ../shared/logger.js

## src/mcp/cache-manager-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, node:sqlite, node:fs, node:path, node:os, ../shared/logger.js

## src/mcp/code-execution-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, node:child_process, ../shared/logger.js

## src/mcp/computer-use-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, child_process, fs, os, path, ../shared/logger.js

## src/mcp/context-guardian-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, child_process, ../shared/state-db.js, ../shared/logger.js

## src/mcp/context-invoker-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, os, ../shared/logger.js

## src/mcp/github-bridge-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, child_process, ../shared/logger.js

## src/mcp/lsp-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, module, child_process, ../shared/logger.js, typescript

## src/mcp/mcp-router/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, node:child_process, node:fs, node:path, node:os, ../shared/logger.js, ../shared/mcp-domains.mjs, ../../shared/telemetry.mjs

## src/mcp/memory-manager-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, ../shared/logger.js

## src/mcp/orchestrator-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, child_process, ../shared/state-db.js, ../shared/logger.js

## src/mcp/patch-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, crypto, ../shared/logger.js

## src/mcp/propose-patch-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, child_process, crypto, ../shared/state-db.js, ../shared/logger.js

## src/mcp/risk-analyzer-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, child_process, fs, path, ../shared/logger.js

## src/mcp/safe-exec-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, shell-quote, ../shared/logger.js, node:crypto, node:fs, node:os, node:path

## src/mcp/shared/state-writer.js  (centrality 0.0598)
exports: readStateStrict, writeState, regenerateMarkdown
imports: fs, path, ./state-db.js

## src/mcp/task-synchronizer-mcp/index.js  (centrality 0.0598)
imports: @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, fs, path, ../shared/state-db.js, ./tool-schemas.mjs, ../../shared/schema-validator.js, ../shared/logger.js, ../../shared/managed-agents-client.mjs, ../../shared/seo-cluster-intents.mjs
