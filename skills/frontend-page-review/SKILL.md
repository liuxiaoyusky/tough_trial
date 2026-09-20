---
name: frontend-page-review
description: "Create an annotation-first UI review workspace for web, desktop, iOS, Android, and other app front ends. Use when a user wants to review screens visually, annotate screenshots or mockups inside Codex, compare states, turn comments into code changes, and verify the resulting interactions."
---

# Frontend Page Review

Use this skill to make visual UI review a concrete, repeatable part of front-end development.

## Core contract

Treat the work as three distinct evidence layers:

1. **Visual evidence** — screenshots, mocks, rendered states, or a running UI.
2. **Implementation** — the code changes that address accepted review feedback.
3. **Interaction acceptance** — real clicks, taps, typing, keyboard input, drag/drop, navigation, and state changes in a runnable build when the environment supports them.

Never claim that a screenshot proves an interaction works.

Preserve the target project's own design system, platform conventions, and product brief. Do not impose a generic Apple, Material, or web style unless the project explicitly calls for it.

## Workflow

Start by reading the project's product/design source of truth and locating the relevant implementation files. Collect current UI evidence from the best available source: live runtime first when practical, then screenshots, design exports, or code-derived renders.

Build a **page/state inventory** before changing UI. Include the screens the user named plus materially different empty, loading, error, editing, confirmation, or expanded states when those states are part of the requested flow.

For visual review, create or update a local annotation workspace. Prefer the bundled scaffold:

```bash
python3 scripts/create_review_site.py \
  --output /path/to/review \
  --title "Product UI Review" \
  --pages /path/to/pages.json
```

The manifest format is documented in [references/review-site.md](references/review-site.md). The generated site supports page navigation, zoom, point annotations, local persistence, resolve/reopen, delete, and Markdown export.

When the user annotates the review site, read the saved `feedback.json` or `feedback.md`, map each comment to the relevant screen and implementation file, and implement only the requested changes. Re-render the affected states so the user can visually review the result again.

After implementation, perform real interaction acceptance for the changed surface. Inventory every visible interactive control and exercise the meaningful paths supported by the local environment. Cover primary behavior and any changed cancel, undo, disabled, empty, error, keyboard, or drag paths. Report separately what was visually reviewed and what was actually interaction-tested.

## Platform routing

Read [references/platforms.md](references/platforms.md) when platform-specific behavior matters.

## Review-site output

Keep review artifacts local to the project unless the user asks for another destination. Prefer a directory such as `outputs/<feature>-design-review/` or the project's established QA/output location.

The review site is a design-feedback surface. Its preview images may be static. Clearly label static previews as non-interactive, then use the real application for interaction acceptance.

## Completion report

State which pages/states were included, where the review site lives and how it was served, which feedback items were implemented, which interactions were actually tested, and any remaining runtime or device verification gap.

Do not mark interaction behavior complete when only static review evidence exists.
