/**
 * seo-approach-types.mjs — canonical SEO approach-type slugs (E-79).
 *
 * Single source of truth for the 20 approach-types defined in
 * .ai/blueprints/seo-keyword-multiplier.md per E-77's enumeration.
 *
 * Consumers:
 *   - task-synchronizer-mcp (E-79): validate ContentVariation.approach_type
 *   - src/gemini/agents/seo_manager.md (E-77): documents the same list as a
 *     markdown table — kept in sync via tests/suites/seo_manager_test.sh
 *   - src/gemini/agents/seo_content_generator.md (E-78): same.
 *
 * Order is stable — never reorder these. Downstream consumers (e.g. the
 * multiplyKeyword expansion in E-77) iterate this array index-by-index
 * and the variation_ids[] return value is order-dependent.
 */
export const SEO_APPROACH_TYPES = Object.freeze([
  "listicle",
  "how-to-guide",
  "case-study",
  "comparison-versus",
  "ultimate-guide",
  "step-by-step-tutorial",
  "best-of-roundup",
  "data-backed-analysis",
  "pros-cons-tradeoff",
  "expert-roundup",
  "tool-or-product-review",
  "trends-outlook",
  "mistakes-to-avoid",
  "faq-compilation",
  "checklist-or-cheatsheet",
  "definition-explainer",
  "cost-pricing-analysis",
  "alternatives-multi-way",
  "personal-lessons",
  "future-predictions",
]);

export const SEO_APPROACH_TYPES_SET = new Set(SEO_APPROACH_TYPES);

/**
 * Blueprint §Execution Constraints/Generation Limits: hard cap of 20
 * variations per KeywordSeed. Defence-in-depth at the schema layer so
 * that a buggy upstream caller can never create the 21st row.
 */
export const MAX_VARIATIONS_PER_SEED = 20;

export function isValidApproachType(slug) {
  return typeof slug === "string" && SEO_APPROACH_TYPES_SET.has(slug);
}
