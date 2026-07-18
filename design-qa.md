# Design QA

## Visual source of truth

- Selected reference: `/Users/yingwu/.codex/generated_images/019f7537-6937-7f93-a49b-9250314f47da/exec-c383588a-0d27-4b0b-a04a-45dc06730a9a.png`
- Final implementation capture: `/Users/yingwu/.codex/visualizations/2026/07/18/019f7537-6937-7f93-a49b-9250314f47da/implemented-home-hero-final.png`
- Side-by-side comparison: `/Users/yingwu/.codex/visualizations/2026/07/18/019f7537-6937-7f93-a49b-9250314f47da/design-qa-home-final-side-by-side.png`
- Desktop viewport: 1487 x 1058
- Mobile viewport: 390 x 844
- Compared state: public home page, initial viewport

## Interaction and responsive checks

- Verified desktop and mobile rendering for home, features, support, privacy, timetable sharing, and community post sharing routes.
- Verified the mobile navigation menu opens and routes correctly.
- Verified public pages have no horizontal overflow at a 375 px viewport.
- Verified a fresh browser session reports no console errors after the final changes.
- Verified support actions, App Store links, copy-email behavior, and public navigation retain their existing behavior.

## Iteration history

1. The first implementation retained light paper sections and invalid opacity utilities. Public-page dark overrides were scoped and opacity tokens were standardized.
2. The hero was taller than the reference and delayed the first editorial section. Desktop hero height and section spacing were tightened, and the supporting composition was reordered.
3. The support hero lifebuoy icon felt visually heavy. It was replaced with a regular-weight headset icon.

## Final assessment

- P0 findings: none
- P1 findings: none
- P2 findings: none
- Accepted deviations: the real Leafy app frame and responsive page proportions are preserved instead of reproducing the reference as a static poster.

Result: passed
