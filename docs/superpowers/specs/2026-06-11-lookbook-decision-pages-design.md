# Lookbook decision pages — Overlays exemplar (Tier 3, item 3a)

**Date:** 2026-06-11 · **Status:** design approved, ready to plan · **Repo:** `modelrails_base` (app-only)

Memory pointers: `[[project_lookbook_catalog_improvements]]`, handoff
`docs/superpowers/handoff/2026-06-11-lookbook-tier3-handoff.md`.

## Problem

The catalog answers "what does component X do" (per-component previews + doc-comments) but
not "**which of these siblings do I reach for?**" — the hardest adoption question. Overlays
is the sharpest case: a dev choosing between `dialog`, `alert_dialog`, `drawer`, `sheet`,
`popover`, `tooltip`, `hover_card`, `dropdown_menu`, `context_menu`, `menubar` has no single
routing view. Each component documents its own `## Use when` / `## Don't use when`, but the
knowledge is scattered across ten files.

## Goal

A single Lookbook **Page** that routes a developer to the right overlay sibling, validated in
CI, establishing a reusable **content shape** + **nav structure** that the other dense sections
fan out into later. This cycle ships **one** page (Overlays) — the exemplar.

## Non-goals (YAGNI)

- No decision pages for the other sections yet (fast-follow: Forms & Inputs, Media, Data
  Display, Navigation, Feedback & Status). Layout / Actions likely never get one — too little
  sibling overlap; a decision page there is the "ceremony" anti-pattern.
- No changes to any component preview, no new component docs, no hiding of `dont_*` scenarios.
- No additional doc *prose* beyond one framing sentence per fork (panel guardrail).
- **App-only.** Decision pages are app catalog content, not gem components — no
  `modelrails/harden` PR this cycle.

## Decisions (from brainstorm)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope | Overlays exemplar only | Mechanism is proven (Overview page); the *content shape* is what's unproven — discover it once, then reuse. Smallest reviewable PR. |
| Table shape | **Reach-for-it-when** | Per component: a positive "use it when" line that points to the alternative. Most scannable, least prose, directly answers "which sibling." |
| Live embeds | **One per fork** (3 total) | Anchors each fork visually without bloat; sibling previews are one sidebar-click away. |
| Nav structure | **Grouped `choosing/` page tree** | Fan-out drops more files into the same dir — make the later change easy now. |
| Guard | **Static source-analysis spec** | Mirrors the repo's existing guard style (`logical_path_coverage_spec.rb`, `scenario_grouping_spec.rb`) — fast, no render. |

## File & nav structure

- New file: `spec/components/previews/pages/choosing/00_overlays.md.erb`.
- Frontmatter `label: Overlays` → renders under a **"Choosing"** group in the Pages sidebar,
  beneath the existing **Overview** page (`pages/00_overview.md.erb`).
- **No config change expected** — `config.lookbook.page_paths` already points at
  `spec/components/previews/pages` and Lookbook recurses subdirectories into nav groups.
  - **VERIFY DURING PLANNING:** confirm Lookbook 2.3.14 turns a `choosing/` subdir into a
    page group. If subdir recursion is unsupported, fall back to a flat top-level file
    `pages/10_choosing_overlays.md.erb` (label `Choosing: Overlays`) — same content, no group.

## Page content

Markdown `.md.erb` mirroring the proven `00_overview.md.erb` structure: YAML frontmatter,
markdown body, `<%= embed UI::XxxComponentPreview, :scenario %>` for live scenarios. Escape
literal ERB shown to readers as `<%%= … %>` in fenced code (none needed here unless we show a
usage snippet).

Three fork sections, each = one framing sentence + a reach-for-it-when table + one live embed.
Representative embed scenarios confirmed present: all three use `:basic`.

```
---
label: Overlays
---

# Choosing an overlay

Overlays differ on three axes: whether they **block the page** with a scrim, how they're
**triggered**, and whether they **carry actions**. Start with the fork that matches your need.

## Modal surfaces — block the page with a scrim

| Component      | Reach for it when                              | Otherwise → |
|----------------|------------------------------------------------|-------------|
| `dialog`       | a focused task needs the user's full attention | drawer / sheet |
| `alert_dialog` | a destructive confirm — the user MUST decide   | dialog |
| `sheet`        | a side panel: navigation, filters, secondary forms | drawer |
| `drawer`       | a bottom sheet: mobile-friendly secondary actions  | sheet |

<%= embed UI::DialogComponentPreview, :basic %>

## Floating — anchored to a trigger, no scrim

| Component    | Reach for it when                              | Otherwise → |
|--------------|------------------------------------------------|-------------|
| `popover`    | interactive content anchored to a control      | tooltip / hover_card |
| `hover_card` | a rich preview on hover (e.g. a user card)     | popover |
| `tooltip`    | a label-only string on hover/focus             | popover |

<%= embed UI::PopoverComponentPreview, :basic %>

## Menus — a list of commands

| Component       | Reach for it when                          | Otherwise → |
|-----------------|--------------------------------------------|-------------|
| `dropdown_menu` | actions launched from a button trigger     | context_menu |
| `context_menu`  | actions from right-click / long-press      | dropdown_menu |
| `menubar`       | a persistent app menu bar (File / Edit / …) | dropdown_menu |

<%= embed UI::DropdownMenuComponentPreview, :basic %>
```

## Sourcing rule (accuracy)

Every "reach for it when" / "otherwise →" cell is **sourced from the target component's own
`## Use when` / `## Don't use when` doc-comment**, not invented. Confirmed during brainstorm:
`drawer` = bottom sheet (slides up), `sheet` = side panel (slides from edge) — and each
component's "Don't use when" already names its sibling (`drawer` → "side panel → use `sheet`").
This keeps the page consistent with component truth at authoring time and is the basis for the
drift guard below.

**WRITING STEP:** before finalizing copy, re-read all 10 Overlays previews' `## Use when` /
`## Don't use when` blocks and reconcile any wording the table compresses.

## Test / consistency guard

One static source-analysis spec — same family as `logical_path_coverage_spec.rb` and
`scenario_grouping_spec.rb` (read the file, scan, assert; no browser render). Proposed path:
`spec/components/previews/pages/choosing_overlays_spec.rb`.

1. **Coverage** — every Overlays sibling is routed on the page. Derive the Overlays set from
   the **same source of truth** the coverage spec uses (the `@logical_path Overlays` previews,
   i.e. the 10: dialog, alert_dialog, drawer, sheet, popover, tooltip, hover_card,
   dropdown_menu, context_menu, menubar). Assert each name appears in the page markdown.
   → Adding a new overlay component without routing it on the page **fails CI**.
2. **Embed validity** — scan the page for `embed UI::<X>ComponentPreview, :<scenario>`; assert
   each referenced preview class exists (`constantize`) and responds to the scenario method.
   → A renamed/removed scenario breaking the page **fails CI** without needing a render.

Confirm the spec's `require`/placement matches the existing two guards during planning.

## Scope boundaries

- **In:** the one Overlays page, the `choosing/` group dir, the guard spec.
- **Out (fast-follow, separate cycles):** decision pages for the other dense sections.
- **Out:** any component-preview change, new component docs, `dont_*` hiding, config changes
  (unless subdir-group verification forces the flat fallback).
- **Cross-repo:** app-only; no gem PR. (Open question for a *later* cycle, not this one:
  whether the gem's own Lookbook should eventually carry parallel decision pages.)

## Fan-out note (future, not this cycle)

Once this exemplar is CI-green and the shape is validated, the follow-up cycle adds
`choosing/01_forms.md.erb`, `02_media.md.erb`, `03_data_display.md.erb`,
`04_navigation.md.erb`, `05_feedback.md.erb` — same template, sourced rows, one embed per fork,
and the coverage guard generalized to assert each `choosing/<section>.md.erb` routes every
sibling in that `@logical_path` section.

## Open items to resolve during planning

1. Lookbook 2.3.14 subdir-group behavior (else flat fallback).
2. Exact guard-spec placement/`require` to match repo conventions.
3. Final reconciliation of table copy against the 10 previews' `## Use when` blocks.
