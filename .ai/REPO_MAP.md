# REPO_MAP.md — AST Repository Map (auto-generated)
<!-- ast-parser-mcp generate_map (E-97): 30/147 files, budget 2048 tokens. `⋮` = elided function body. -->

## .claude/worktrees/e254/src/mcp/shared/is-main.mjs  (centrality 1)
exports: isMainModule
imports: node:url

## src/mcp/shared/is-main.mjs  (centrality 1)
exports: isMainModule
imports: node:url

## .claude/worktrees/e254/src/shared/mcp-telemetry.mjs  (centrality 0.6464)
exports: TELEMETRY_STATUS, toolNameFor, EXPECTED_REJECTION_META, BOOTED_BUILD_META, stampBootedBuild, statusForResult, rejection, markRejection, withTelemetry, instrument
imports: ./telemetry.mjs, ./build-stamp.mjs

## src/shared/mcp-telemetry.mjs  (centrality 0.6464)
exports: TELEMETRY_STATUS, toolNameFor, EXPECTED_REJECTION_META, BOOTED_BUILD_META, stampBootedBuild, statusForResult, rejection, markRejection, withTelemetry, instrument
imports: ./telemetry.mjs, ./build-stamp.mjs

## .claude/worktrees/e254/src/mcp/shared/logger.js  (centrality 0.5892)
exports: createLogger

## src/mcp/shared/logger.js  (centrality 0.5892)
exports: createLogger

## .claude/worktrees/e254/src/mcp/shared/state-db.js  (centrality 0.4702)
exports: getDb, parseDeps, readState, roleFromOwner, archivePointerLines, regenerateViews, MAX_DAG_DEPTH, readDependencyGraph, validateDag, withTransaction, nextId, recordIdHighWater, addTask, DONE_ARCHIVE_THRESHOLD, DONE_KEEP_RECENT, STAMP_ARCHIVE_THRESHOLD, STAMP_KEEP_RECENT, archiveDoneTasks, archiveStamps, nextTopicSeedId, nextClusterPageId
imports: fs, path, node:sqlite

## src/mcp/shared/state-db.js  (centrality 0.4702)
exports: getDb, parseDeps, readState, roleFromOwner, archivePointerLines, regenerateViews, MAX_DAG_DEPTH, readDependencyGraph, validateDag, withTransaction, nextId, recordIdHighWater, addTask, DONE_ARCHIVE_THRESHOLD, DONE_KEEP_RECENT, STAMP_ARCHIVE_THRESHOLD, STAMP_KEEP_RECENT, archiveDoneTasks, archiveStamps, nextTopicSeedId, nextClusterPageId
imports: fs, path, node:sqlite

## .claude/worktrees/e254/src/shared/locate.mjs  (centrality 0.464)
exports: enableDevTree, _resetDevTree, isFrameworkClone, locate
imports: node:fs, node:child_process, node:path, ../mcp/shared/is-main.mjs

## src/shared/locate.mjs  (centrality 0.464)
exports: enableDevTree, _resetDevTree, isFrameworkClone, locate
imports: node:fs, node:child_process, node:path, ../mcp/shared/is-main.mjs

## .claude/worktrees/e254/src/shared/build-stamp.mjs  (centrality 0.4328)
exports: RUN_DIR, buildStampEnabled, recordPathFor, buildInputsFor, stampFor, bootedBuild, isStdioServerInvocation, _resetBootedBuild, writeBootRecord, listStaleServers, GATED_ROOTS, mirrorDrift, checkCompletionBuildGate, formatStaleLines, staleServerReport
imports: node:crypto, node:fs, node:os, node:path, node:url, ./locate.mjs

## src/shared/build-stamp.mjs  (centrality 0.4328)
exports: RUN_DIR, buildStampEnabled, recordPathFor, buildInputsFor, stampFor, bootedBuild, isStdioServerInvocation, _resetBootedBuild, writeBootRecord, listStaleServers, GATED_ROOTS, mirrorDrift, checkCompletionBuildGate, formatStaleLines, staleServerReport
imports: node:crypto, node:fs, node:os, node:path, node:url, ./locate.mjs

## .claude/worktrees/e254/src/shared/telemetry.mjs  (centrality 0.3947)
exports: TELEMETRY_SERVICE, TELEMETRY_DB_PATH, USAGE_DB_PATH, STATUS_ORDER, STATUS_VALUES, STATUS_SQL_IN, STATUS_MIGRATION_SENTINEL, recordToolExecution, recordTaskVelocity, recordTaskVelocityForTask, getTelemetryStats, resetTelemetryCache
imports: node:sqlite, node:crypto, node:fs, node:path, node:os, node:url

## src/shared/telemetry.mjs  (centrality 0.3947)
exports: TELEMETRY_SERVICE, TELEMETRY_DB_PATH, USAGE_DB_PATH, STATUS_ORDER, STATUS_VALUES, STATUS_SQL_IN, STATUS_MIGRATION_SENTINEL, recordToolExecution, recordTaskVelocity, recordTaskVelocityForTask, getTelemetryStats, resetTelemetryCache
imports: node:sqlite, node:crypto, node:fs, node:path, node:os, node:url

## .claude/worktrees/e254/src/shared/markdown-exec.mjs  (centrality 0.3291)
exports: EXECUTABLE_FENCE_TAGS, isSkillOrAgentFile, isProseOnlyFile, isGeneratedRecord, classifyMarkdown, addedLines

## src/shared/markdown-exec.mjs  (centrality 0.3291)
exports: EXECUTABLE_FENCE_TAGS, isSkillOrAgentFile, isProseOnlyFile, isGeneratedRecord, classifyMarkdown, addedLines

## src/shared/provider-adapter.mjs  (centrality 0.3073)
exports: DEFAULT_ROLE_PROVIDERS, DEFAULT_ROLE_MODELS, DEFAULT_HEADLESS_ROLES, DEFAULT_ADAPTERS, roleEntry, roleProvider, roleModel, isHeadless, roleLabel, providerAdapter, buildArgv, PATH_OPERAND_FLAGS, absolutisePathOperands, childEnv
imports: node:fs, node:path

## .claude/worktrees/e254/src/mcp/safe-exec-mcp/architect-writes.mjs  (centrality 0.2311)
exports: isSafeArchitectPath, boundedRel, hardlinkAlias, projectPathVerdict, architectPathVerdict, findProjectRootFrom, analyzeArchitectWrites
imports: shell-quote, node:fs, node:path

## src/mcp/safe-exec-mcp/architect-writes.mjs  (centrality 0.2311)
exports: isSafeArchitectPath, boundedRel, hardlinkAlias, projectPathVerdict, architectPathVerdict, findProjectRootFrom, analyzeArchitectWrites
imports: shell-quote, node:fs, node:path

## .claude/worktrees/e254/src/shared/provider-adapter.mjs  (centrality 0.2256)
exports: DEFAULT_ROLE_PROVIDERS, DEFAULT_ROLE_MODELS, DEFAULT_ADAPTERS, roleEntry, roleProvider, roleModel, providerAdapter, buildArgv, PATH_OPERAND_FLAGS, absolutisePathOperands, childEnv
imports: node:fs, node:path

## .claude/worktrees/e254/src/shared/instinct-stager.mjs  (centrality 0.1779)
exports: MIN_CONFIDENCE, isSafeSlug, scanDangerousContent, slugify, validateInstinct, renderProposedSkill, stageInstincts
imports: node:fs, node:path

## .claude/worktrees/e254/src/shared/standards-checker.mjs  (centrality 0.1779)
exports: DEFAULT_STANDARDS_PATH, SEVERITY_ORDER, loadStandards, RULE_REGISTRY, suppressionTokensFor, knownSuppressionTokens, isSuppressed, unknownSuppressionFindings, exemptionFor, validateFile, validateStaged, validateFiles, reportDrift, validateStandards
imports: node:fs, node:path, node:child_process, ./markdown-exec.mjs

## src/shared/instinct-stager.mjs  (centrality 0.1779)
exports: MIN_CONFIDENCE, isSafeSlug, scanDangerousContent, slugify, validateInstinct, renderProposedSkill, stageInstincts
imports: node:fs, node:path

## src/shared/standards-checker.mjs  (centrality 0.1779)
exports: DEFAULT_STANDARDS_PATH, SEVERITY_ORDER, loadStandards, RULE_REGISTRY, suppressionTokensFor, knownSuppressionTokens, isSuppressed, unknownSuppressionFindings, exemptionFor, validateFile, validateStaged, validateFiles, reportDrift, validateStandards
imports: node:fs, node:path, node:child_process, ./markdown-exec.mjs

## .claude/worktrees/e254/src/mcp/shared/load-policy.mjs  (centrality 0.1363)
exports: POLICY_PATHS, loadPolicy, policyLoadCounts, policyStaleness
imports: node:fs, node:path, node:url

## src/mcp/shared/load-policy.mjs  (centrality 0.1363)
exports: POLICY_PATHS, loadPolicy, policyLoadCounts, policyStaleness
imports: node:fs, node:path, node:url

## .claude/worktrees/e254/src/shared/signal-handoff.mjs  (centrality 0.1308)
exports: VALID_TARGETS, emitHandoff, hasPendingHandoff, settleTasks, findAiDir, defaultMessage
imports: node:fs, node:path, ../mcp/shared/state-db.js

## src/shared/signal-handoff.mjs  (centrality 0.1308)
exports: VALID_TARGETS, emitHandoff, hasPendingHandoff, settleTasks, findAiDir, defaultMessage
imports: node:fs, node:path, ../mcp/shared/state-db.js

## .claude/worktrees/e254/src/mcp/shared/caller-role.mjs  (centrality 0.1227)
exports: resolveCallerRole, _resetCallerRoleCache, effectiveRequestRole, inArchitectScope, architectScopeGuard
imports: node:child_process, node:fs, node:path, ../safe-exec-mcp/architect-writes.mjs, node:url

## src/mcp/shared/caller-role.mjs  (centrality 0.1227)
exports: resolveCallerRole, _resetCallerRoleCache, effectiveRequestRole, inArchitectScope, architectScopeGuard
imports: node:child_process, node:fs, node:path, ../safe-exec-mcp/architect-writes.mjs, node:url
