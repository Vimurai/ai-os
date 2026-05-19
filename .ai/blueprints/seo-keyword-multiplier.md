# Domain Blueprint: SEO Keyword Multiplier

> [!IMPORTANT]
> High-volume content generation strategy based on the "MrBeast keyword-multiplier" approach.

## Goal & Architecture
The goal is to implement a keyword-multiplier system for the SEO Agent that generates 20 distinct content variations per target keyword to capture a wider range of long-tail search intent and build search engine authority.

## Core Concept
- **Keyword Seed**: A primary search term.
- **Content Engine**: An automated generator that creates 20 unique article structures (e.g., "listicle," "case study," "how-to," "data-backed analysis") from the same keyword seed.
- **Authority Loop**: High-volume, high-quality, non-duplicate content delivery designed to maximize the probability of search engine indexing and ranking.

## Components
1. **Keyword-Multiplier-Manager**: Orchestrates the expansion of a single keyword into 20 distinct task requests.
2. **SEO-Content-Generator**: A specialized LLM agent service that takes a keyword and an "approach-template" (e.g., "listicle") to generate a complete, optimized article.
3. **Multi-Variation-State-Tracker**: Tracks the status and performance of all 20 variations for a single keyword seed to prevent collisions and identify top-performing content.

## Data Model
- `KeywordSeed`: `id`, `term`, `status`, `target_volume`.
- `ContentVariation`: `id`, `seed_id`, `approach_type`, `content_blob`, `performance_metrics`, `published_at`.

## API / Interface Contracts
- `multiplyKeyword(term: string) -> variation_ids[]`: Initiates the creation of 20 variations.
- `generateVariation(seed_id: string, type: string) -> variation_blob`: Executes the generation.
- `reportPerformance(variation_id: string, metrics: Object)`: Updates the content's SEO metrics.

## Security
- **Content Integrity**: All generated content must be validated against a "duplicate-content" checker.
- **Rate Limiting**: Automated generation is bound by LLM provider rate limits; requires exponential backoff.
- **PII/Safety**: Content generation is gated through the existing Identity Guardian and Security Engineer (critic_security) checks.

## Execution Constraints
- **Concurrency**: Generate up to 3 variations concurrently.
- **Generation Limits**: Max 20 variations per seed.
- **Performance**: Each variation must be generated in < 120 seconds.

## Rollback Plan
- Delete the `KeywordSeed` and all associated `ContentVariation` records via `task-synchronizer-mcp` commands.
- Purge generated content files from the repository if they have been staged.

## E-## Task Breakdown
- E-77: Implement the Keyword-Multiplier-Manager in `src/gemini/agents/seo_manager.md`.
- E-78: Create the SEO-Content-Generator agent logic to support variation-types.
- E-79: Develop the Multi-Variation-State-Tracker in `task-synchronizer-mcp`.
