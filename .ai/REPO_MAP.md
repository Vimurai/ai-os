# REPO_MAP.md — AST Repository Map (auto-generated)
<!-- ast-parser-mcp generate_map (E-97): 35/74 files, budget 2048 tokens. `⋮` = elided function body. -->

## src/mcp/shared/is-main.mjs  (centrality 1)
exports: isMainModule
imports: node:url

## src/shared/mcp-telemetry.mjs  (centrality 0.6464)
exports: TELEMETRY_STATUS, toolNameFor, EXPECTED_REJECTION_META, BOOTED_BUILD_META, stampBootedBuild, statusForResult, rejection, markRejection, withTelemetry, instrument
imports: ./telemetry.mjs, ./build-stamp.mjs

## src/mcp/shared/logger.js  (centrality 0.5892)
exports: createLogger

## src/mcp/shared/state-db.js  (centrality 0.4702)
exports: getDb, parseDeps, readState, roleFromOwner, archivePointerLines, regenerateViews, MAX_DAG_DEPTH, readDependencyGraph, validateDag, withTransaction, nextId, recordIdHighWater, addTask, DONE_ARCHIVE_THRESHOLD, DONE_KEEP_RECENT, STAMP_ARCHIVE_THRESHOLD, STAMP_KEEP_RECENT, archiveDoneTasks, archiveStamps, nextTopicSeedId, nextClusterPageId
imports: fs, path, node:sqlite

## src/shared/locate.mjs  (centrality 0.464)
exports: enableDevTree, _resetDevTree, isFrameworkClone, locate
imports: node:fs, node:child_process, node:path, ../mcp/shared/is-main.mjs

## src/shared/build-stamp.mjs  (centrality 0.4328)
exports: RUN_DIR, buildStampEnabled, recordPathFor, buildInputsFor, stampFor, bootedBuild, isStdioServerInvocation, _resetBootedBuild, writeBootRecord, listStaleServers, GATED_ROOTS, mirrorDrift, checkCompletionBuildGate, formatStaleLines, staleServerReport
imports: node:crypto, node:fs, node:os, node:path, node:url, ./locate.mjs

## src/shared/telemetry.mjs  (centrality 0.3947)
exports: TELEMETRY_SERVICE, TELEMETRY_DB_PATH, USAGE_DB_PATH, STATUS_ORDER, STATUS_VALUES, STATUS_SQL_IN, STATUS_MIGRATION_SENTINEL, recordToolExecution, recordTaskVelocity, recordTaskVelocityForTask, getTelemetryStats, resetTelemetryCache
imports: node:sqlite, node:crypto, node:fs, node:path, node:os, node:url

## src/shared/markdown-exec.mjs  (centrality 0.3291)
exports: EXECUTABLE_FENCE_TAGS, isSkillOrAgentFile, isProseOnlyFile, isGeneratedRecord, classifyMarkdown, addedLines

## src/mcp/safe-exec-mcp/architect-writes.mjs  (centrality 0.2311)
exports: isSafeArchitectPath, boundedRel, hardlinkAlias, projectPathVerdict, architectPathVerdict, findProjectRootFrom, analyzeArchitectWrites
imports: shell-quote, node:fs, node:path

## src/shared/provider-adapter.mjs  (centrality 0.2256)
exports: DEFAULT_ROLE_PROVIDERS, DEFAULT_ROLE_MODELS, DEFAULT_ADAPTERS, roleEntry, roleProvider, roleModel, providerAdapter, buildArgv, PATH_OPERAND_FLAGS, absolutisePathOperands, childEnv
imports: node:fs, node:path

## src/shared/instinct-stager.mjs  (centrality 0.1779)
exports: MIN_CONFIDENCE, isSafeSlug, scanDangerousContent, slugify, validateInstinct, renderProposedSkill, stageInstincts
imports: node:fs, node:path

## src/shared/standards-checker.mjs  (centrality 0.1779)
exports: DEFAULT_STANDARDS_PATH, SEVERITY_ORDER, loadStandards, RULE_REGISTRY, suppressionTokensFor, knownSuppressionTokens, isSuppressed, unknownSuppressionFindings, exemptionFor, validateFile, validateStaged, validateFiles, reportDrift, validateStandards
imports: node:fs, node:path, node:child_process, ./markdown-exec.mjs

## src/mcp/shared/load-policy.mjs  (centrality 0.1363)
exports: POLICY_PATHS, loadPolicy, policyLoadCounts, policyStaleness
imports: node:fs, node:path, node:url

## src/shared/signal-handoff.mjs  (centrality 0.1308)
exports: VALID_TARGETS, emitHandoff, hasPendingHandoff, settleTasks, findAiDir, defaultMessage
imports: node:fs, node:path, ../mcp/shared/state-db.js

## src/mcp/shared/caller-role.mjs  (centrality 0.1227)
exports: resolveCallerRole, _resetCallerRoleCache, effectiveRequestRole, inArchitectScope, architectScopeGuard
imports: node:child_process, node:fs, node:path, ../safe-exec-mcp/architect-writes.mjs, node:url

## src/mcp/vibe-check-mcp/browser-check.mjs  (centrality 0.1166)
exports: BROWSER_MISSING, browserStatus, browserMissingMessage, assertBrowserAvailable
imports: node:fs

## src/mcp/ast-parser-mcp/extractor.mjs  (centrality 0.1125)
exports: PARSE_TIMEOUT_MICROS, languageForFile, initParsers, extractSymbols, extractFromSource
imports: web-tree-sitter, node:url, node:path

## src/mcp/ast-parser-mcp/repo-mapper.mjs  (centrality 0.1125)
exports: normalizePath, resolveImport, buildDependencyGraph, pageRank, rankSymbols

## src/mcp/ast-parser-mcp/serializer.mjs  (centrality 0.1125)
exports: DEFAULT_MAX_TOKENS, estimateTokens, renderFileBlock, serializeRepoMap

## src/mcp/shared/mcp-domains.mjs  (centrality 0.1125)
exports: DOMAINS, domainForServer

## src/mcp/propose-patch-mcp/diff-targets.mjs  (centrality 0.1064)
exports: diffFileSections, headerName, isUnifiedDiff, validateDiffContent
imports: node:path

## src/mcp/task-synchronizer-mcp/tool-schemas.mjs  (centrality 0.1036)
exports: buildToolSchemas

## src/shared/managed-agents-client.mjs  (centrality 0.1036)
exports: isEnabled, projectState, syncToCloud, cancelPendingSync, migrateLegacyToSteps, sendSteps, diagnostics
imports: node:sqlite, node:crypto, node:fs, node:path

## src/shared/schema-validator.js  (centrality 0.1036)
exports: validate, loadSchemas, validateNamed
imports: node:fs, node:path, node:url

## src/shared/seo-cluster-intents.mjs  (centrality 0.1036)
exports: SEO_PILLAR_INTENT, SEO_CLUSTER_INTENTS, SEO_ALL_INTENTS, SEO_CLUSTER_INTENTS_SET, SEO_ALL_INTENTS_SET, MAX_CLUSTER_PAGES_PER_SEED, isValidIntentType, isClusterIntent

## scripts/generate_blueprints_index.mjs  (centrality 0.0962)
imports: node:fs, node:path

## scripts/generate_mcp_docs.mjs  (centrality 0.0962)
imports: node:fs, node:path, node:url, node:os

## scripts/standards.mjs  (centrality 0.0962)
exports: formatSuppressionSummary
imports: node:path, node:fs, node:url, node:os

## src/mcp/advisor-mcp/index.js  (centrality 0.0962)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, child_process, fs, path, ../shared/logger.js, ../../shared/provider-adapter.mjs

## src/mcp/approval-mcp/index.js  (centrality 0.0962)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:sqlite, node:readline, node:fs, node:path, node:os, ../shared/logger.js

## src/mcp/archive-manager-mcp/index.js  (centrality 0.0962)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, fs, readline, path, ../shared/logger.js, ../shared/state-db.js

## src/mcp/ast-parser-mcp/index.js  (centrality 0.0962)
imports: ../shared/is-main.mjs, node:fs, node:path, ./extractor.mjs, ./repo-mapper.mjs, ./serializer.mjs, ../../shared/mcp-telemetry.mjs

## src/mcp/blueprint-aligner-mcp/index.js  (centrality 0.0962)
exports: parseDiffByFile, isMarkdownFile, isPackageJsonFile, isJsonFile, traversalOutsideBackticks, isTestHelperFile, isInternalPathBuilder
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, child_process, fs, path, ../shared/logger.js

## src/mcp/cache-manager-mcp/index.js  (centrality 0.0962)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:sqlite, node:fs, node:path, node:os, ../shared/logger.js

## src/mcp/code-execution-mcp/index.js  (centrality 0.0962)
imports: ../shared/is-main.mjs, @modelcontextprotocol/sdk/server/index.js, @modelcontextprotocol/sdk/server/stdio.js, @modelcontextprotocol/sdk/types.js, ../../shared/mcp-telemetry.mjs, node:child_process, ../shared/logger.js
