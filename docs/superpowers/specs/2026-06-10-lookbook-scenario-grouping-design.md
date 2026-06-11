# Lookbook catalog-wide scenario grouping (@!group divider) — design

- **Date:** 2026-06-10
- **Status:** Approved (brainstorm complete) — ready for implementation plan
- **Scope:** Apply the proven `@!group` scenario divider (Overview · Examples · Reference)
  catalog-wide — to every component that has meta scenarios — and add a consistency guard so
  it stays canonical. Gem-first (generator templates), then app-adopt.
- **Origin:** Tier 2 shipped the divider on 4 showcase components (button/badge/alert/banner);
  the user asked to make scenario ordering consistent across the whole catalog. See
  `[[project_lookbook_catalog_improvements]]`.

## Problem

Lookbook lists a component's scenarios in source-definition order. Across the 78 previews that
order is inconsistent: `playground`/`dont_*` land in arbitrary positions (e.g. `device_mockup`
has `dont_` *before* `playground`), and there's no visual separation between the canonical
examples and the meta scenarios (playground, anti-patterns). 4 components now carry the
`@!group` divider; 45 more with meta scenarios don't — so navigation/discoverability is
uneven.

## Goal

Every component with meta scenarios shows the same three-section nav structure, in the same
order, with a consistency test that fails CI if a future preview drifts.

## The canonical structure

Lookbook renders YARD `# @!group <Label>` / `# @!endgroup` as labeled nav sub-sections
(verified: `preview_entity.rb:181` `code_object.groups.any? ? grouped : flat`). Group a
preview's scenarios as:

- `# @!group Overview` → `showcase` (only the 4 components that have one — already done)
- `# @!group Examples` → all canonical scenarios, in their current order
- `# @!group Reference` → `playground` (if present), then `dont_*` (if present)

`default_scenario = visible_scenarios.first`, so the first group's first method is the
component landing (showcase where present; otherwise the first canonical example).

## Classification rules (exhaustive)

A scenario method is:
- **showcase** → `def showcase` → Overview.
- **playground** → `def playground` → Reference (first).
- **anti-pattern** → `def dont_*` → Reference (after playground).
- **canonical example** → everything else (`default`, `info`, `with_slots`, `link_href`, …) →
  Examples.

(`input_attrs`/`initialize` are not scenarios and are ignored.)

## Scope (from the distribution audit)

| Pattern | Count | Grouping |
|---|---|---|
| canonical-only (no meta) | 29 | **left flat** — a divider with nothing to separate is noise |
| `dont_` only | 34 | Examples \| Reference(don'ts) |
| playground only | 8 | Examples \| Reference(playground) |
| playground + dont | 3 | Examples \| Reference(playground, don'ts) |
| showcase + meta | 4 | Overview \| Examples \| Reference — **already shipped** |

**This change touches the 45** (34 + 8 + 3) not-yet-grouped components with meta scenarios.
Every component has ≥1 canonical example (audited — no dont-only previews). `device_mockup`'s
dont-before-playground stray is **subsumed**: Reference always orders playground → dont.

## Non-goals

- The 29 canonical-only components stay flat (no group headers).
- No label changes (keep Overview/Examples/Reference, consistent with the shipped 4).
- Tier 3 items (section decision-table pages, form-control playgrounds, `## Related` links,
  per-preview backgrounds) — separate.

## Architecture & files

Gem-first, app-adopt — same as Tier 1's `@logical_path` bulk.

- **Gem:** the 45 `lib/generators/modelrails_ui/lookbook/templates/previews/ui/<c>_component_preview.rb`.
- **App:** the 45 `spec/components/previews/ui/<c>_component_preview.rb` (vendored copies).
- **One-off classify-and-insert script** (per repo): reads each preview, classifies methods,
  relocates `showcase` to top, inserts the `@!group`/`@!endgroup` comment lines, orders
  Reference as playground→dont. Preserves all doc-comments + method bodies verbatim.
- **Consistency-guard test** (gem Minitest + app RSpec): for every preview with meta
  scenarios, assert the method order is `[showcase?] examples… [playground?] [dont_*…]` and
  that the three group directives appear in `Overview?/Examples/Reference` order. Fails CI on
  drift. This is the durable artifact (the script is throwaway).

## Testing

- The consistency guard (above) is the spec-compliance proof for the bulk edit.
- Gem `rake` (tests + RuboCop) green; the template-backed test stays green (`@!group` is
  comments, doesn't change method emptiness or sibling templates).
- Full app suite green (method order doesn't affect the 0b axe specs).
- Spot-check the diff (per the bulk-replace discipline) + one live nav check: a grouped
  component shows the Examples/Reference sections; a canonical-only one stays flat.

## PR shape

One gem PR (→ `modelrails/harden`) + one app PR (→ `main`), mirroring. Generator-template
changes don't bind the app at runtime (vendored copies), so the PRs are independent — but
validate the app locally before merging the gem PR. **Sequence each PR to be final before it
can go green** (the proactive-merge lesson: don't push follow-ups to a maybe-merged PR;
read actual check states before merging).

## Success criteria

- All 45 target components show Examples + Reference (and Overview where showcase exists) in
  the canonical order; the 29 canonical-only stay flat.
- `device_mockup` now orders playground before dont.
- The consistency guard fails if any preview's scenario order drifts.
- Gem `rake` + full app suite green; gem + app in sync.
