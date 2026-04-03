---
name: ux_reviewer
description: Automated visual audit of the UI using Playwright and Lighthouse. Triggered by `ai test --vibe`. Produces a Vibe Report covering animations, contrast, layout shift, accessibility, and performance scores.
---

ROLE: UX_REVIEWER (Gemini Vision + Playwright)
Target: `.ai/REVIEWS.md` (append Vibe Report section)
Trigger: `ai test --vibe`

## Preflight
1. Read `.ai/DIGEST.md` — understand the project and expected UI.
2. Read `.ai/BRIEF.md` — check for design system constraints or brand guidelines.
3. Identify the dev server start command (check `package.json` scripts for `dev`, `start`, or `preview`).

## Vibe Audit Steps

### 1. Spin Up Dev Server
```bash
# Detect and start the dev server
npm run dev &   # or yarn dev / pnpm dev
sleep 3         # wait for server to be ready
```

### 2. Playwright Visual Checks
For each primary route/screen in the app, capture and evaluate:
- **Animation smoothness**: Check for janky transitions (> 16ms frame budget violations).
- **Layout shift**: Cumulative Layout Shift (CLS) score — target < 0.1.
- **Color contrast**: All text must meet WCAG AA (4.5:1 for normal text, 3:1 for large text).
- **Interactive targets**: Buttons/links must be ≥ 44×44px touch targets.
- **Focus visibility**: Tab navigation must show a visible focus ring on all interactive elements.

### 3. Lighthouse Audit
Run Lighthouse programmatically against the local server:
- **Performance**: Target score ≥ 80.
- **Accessibility**: Target score ≥ 90.
- **Best Practices**: Target score ≥ 85.
- **SEO**: Target score ≥ 80 (if applicable).

### 4. Rapid-Click Stress Test
Simulate rapid user clicks on primary CTAs:
- Click the primary button 10× rapidly — check for race conditions or UI glitches.
- Submit a form with empty fields — check for graceful error states.
- Navigate forward/back rapidly — check for state corruption.

## Vibe Report Output
Append to `.ai/REVIEWS.md`:
```
[VIBE_REPORT] YYYY-MM-DD | Score: <X/10>

## Visual Audit
- Animations: <pass/fail — details>
- CLS: <score>
- Contrast: <pass/fail — violations listed>
- Touch targets: <pass/fail>
- Focus visibility: <pass/fail>

## Lighthouse Scores
- Performance: <score>
- Accessibility: <score>
- Best Practices: <score>

## Stress Test
- Rapid-click: <pass/fail — any race conditions found>
- Empty form: <pass/fail>
- Back/forward: <pass/fail>

## Recommendations
<Ordered list of issues to fix, P0 first>
```

## Teardown
```bash
# Stop the dev server
kill %1 2>/dev/null || true
```

## Rules
- If Playwright is not installed, output install instructions and exit gracefully.
- Do NOT commit code. This is a read-only audit role.
- If any P0 issues found (contrast failure, CLS > 0.25, broken focus): tag as `[VIBE_BLOCKED]` and notify Claude to fix before Tier 3 release.
