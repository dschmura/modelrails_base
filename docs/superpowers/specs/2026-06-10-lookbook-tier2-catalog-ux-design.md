# Lookbook Tier 2 — catalog UX (toolbar theme · copyable source · all-variants showcase) — design

- **Date:** 2026-06-10
- **Status:** Approved (brainstorm complete) — ready for implementation plan
- **Scope:** Tier 2 of the Lookbook panel roadmap — three independent catalog-UX improvements:
  **2a** surface the canonical `ui` call (lean on Lookbook's Source panel), **2b** move the
  light/dark toggle into Lookbook's chrome as a display option, **2c** add an all-variants
  showcase scenario to variant-axis components. Gem-first (durable templates), then app-adopt.
- **Origin:** the 6-reviewer Lookbook panel (Tier 1 shipped #47/#270). See
  `[[project_lookbook_catalog_improvements]]` for the full Tier 1/2/3 roadmap.

## Problem

Tier 1 gave the catalog a front door and a map. The panel's remaining "make a found component
*usable*" gaps:

- **2a (Adam #1, Chris #3):** the exact paste-ready `ui :name` call isn't front-and-center.
- **2b (5 of 6):** the light/dark toggle is a bespoke `position:fixed` button *inside* the
  preview canvas — it overlaps anything anchored top-right (toasts, close buttons, `speed_dial`,
  dropdowns) and reads as per-canvas markup, not catalog chrome.
- **2c (Adam, Steve):** variants are click-per-scenario; you can't see a component's whole
  `variant × tone` family on one screen to triage fast.

## Goals

1. The canonical invocation for every component is discoverable and copyable without leaving
   the catalog.
2. The theme toggle lives in Lookbook's own toolbar, never overlapping component content.
3. Variant-axis components expose a one-screen showcase of their full family.
4. Shipped the durable way (gem templates → app adoption), every new rendered surface AAA-proven.

## Non-goals (deferred to Tier 3)

Per-section "reach for X when…" decision-table pages; extending `@param` playgrounds to the
form-control family; `## Related`/`## Composes` cross-links; per-preview backgrounds; resolving
the stale `feat/lookbook-teaching-catalog` branch. Panel anti-recommendations still hold: no
*more* doc-comment prose, not every component a playground, don't hide the `dont_*` anti-patterns.

## Feasibility (verified against lookbook-2.3.14 source)

- **2b display option:** `config.lookbook.preview_display_options` (a hash, read at
  `preview_entity.rb:157`) renders a toolbar dropdown per key. The selected value reaches the
  rendered layout via request params: `params.dig(:lookbook, :display, :theme)` (the
  `lookbook_display(key)` helper at `preview_helper.rb:6` is the Lookbook-only sugar for the same
  param).
- **2b host-independence:** the app's 0b axe harness drives dark mode itself —
  `playwright_accessibility.rb:241 set_theme` evaluates JS that toggles `html.classList` + sets a
  `theme` cookie, **independent of the preview-theme button**. So removing/relocating the button
  does not affect dark-mode AAA coverage; only the dedicated `preview_theme_toggle_spec.rb`
  depends on the button.
- **2a Source panel:** Lookbook's inspector shows the scenario's template ERB (the 63
  template-backed scenarios) with a copy control by default. The 15 inline-`@param` playgrounds
  show their `ui :name, ...` Ruby method (acceptable — it *is* the call). Compound previews
  (e.g. dialog) correctly show `render "shared/modal"` / `render "shared/confirm_dialog"` — the
  real paste-ready usage, not a `ui :dialog` call.

## 2a — Surface the canonical `ui` call (lean on Source + lead the docs)

The lightest of the three; the Source panel already does most of the work.

- **Make Source prominent:** configure the inspector so Source is the default-focused panel
  (initializer config; exact key confirmed at implementation — fallback: Source is already
  visible, no change needed).
- **Lead the docs (targeted, NOT blanket):** audit the 78 previews; only where the canonical
  call is not already obvious from Source + the doc-comment, ensure the doc-comment surfaces it.
  Explicitly **not** ~80 new hand-maintained snippets.

## 2b — Theme toggle → Lookbook toolbar control

- **Register** `config.lookbook.preview_display_options = { theme: %w[light dark] }` in the gem
  `lookbook.rb` template and the app initializer → a `Theme: light/dark` dropdown in Lookbook's
  chrome.
- **Layout** `component_preview.html.erb`: set `<html class="<%= "dark" if params.dig(:lookbook,
  :display, :theme) == "dark" %>">` (raw `params.dig`, not `lookbook_display`, so it degrades to
  light in the non-Lookbook test host; the axe harness forces `.dark` there itself). Remove the
  in-canvas `<div data-controller="preview-theme">` button block.
- **Remove the bespoke mechanism:** `preview_theme_controller.js` (gem template + app vendored
  copy), the gem generator's `copy_preview_theme_controller` step (and its
  generator/structural test reference if any), and `spec/system/ui/preview_theme_toggle_spec.rb`
  (obsolete once the button is gone).
- **Net:** toggle becomes catalog chrome; component owns the full canvas; ~3 bespoke files
  deleted; dark-mode AAA coverage unaffected.

## 2c — All-variants showcase scenario

- **Scope (6 components):** `button`, `badge`, `alert`, `banner`, `indicator`, `chat_bubble` —
  where seeing the whole variant/tone family at once speeds triage. (device_mockup / timeline /
  list_group excluded — their "variants" aren't a signal axis worth a grid.)
- **Mechanism:** a `showcase.html.erb` sibling template per component (template-backed →
  copyable + 0b-testable), rendering every **AAA-proven** `(variant, tone)` cell with labels.
  button/badge already raise on unproven combos, so the showcase enumerates only proven cells.
- **Preview method** is the empty template-backed pattern (a `def showcase; end` with the
  sibling `.html.erb`), consistent with the existing scenario convention and the gem's
  template-backed test.

## Architecture & files

Gem-first, app-adopt — same choreography as Tier 1.

### Gem (`modelrails_ui`, branch off `modelrails/harden`)

- `lib/generators/modelrails_ui/lookbook/templates/lookbook.rb` — add
  `preview_display_options` + Source-panel config.
- `.../templates/component_preview.html.erb` — theme-from-param, drop the button block.
- Remove `.../templates/preview_theme_controller.js` + the `copy_preview_theme_controller`
  generator step in `lookbook_generator.rb`.
- 6 new `.../previews/ui/<c>_component_preview/showcase.html.erb` + a `def showcase; end` in
  each of the 6 preview `.rb`.
- Targeted doc-lead-in edits where 2a audit finds a gap.

### App (`modelrails_base`, branches off `main`)

- `app/views/layouts/component_preview.html.erb` — mirror the layout change.
- `config/initializers/modelrails_ui_lookbook.rb` — add `preview_display_options` + Source config.
- Delete `app/javascript/controllers/preview_theme_controller.js` and
  `spec/system/ui/preview_theme_toggle_spec.rb`.
- 6 new app `showcase.html.erb` + the 6 preview-method stubs.
- 6 new 0b axe specs (`spec/system/ui/<c>_showcase_spec.rb` or extend existing component specs).

## PR shaping

Two PRs (each gem + app):

- **PR-A — catalog chrome:** 2a + 2b (both edit `component_preview.html.erb` + the initializer;
  tightly coupled). Carries the spec + plan docs.
- **PR-B — showcase scenarios:** 2c (new scenarios + 0b specs; distinct additive concern),
  branched after PR-A.

Generator-template changes don't bind the app at runtime (vendored copies), so gem and app PRs
are independent per pair — but validate app locally before merging the gem PR, per the proven gate.

## Testing

- **2b:** delete `preview_theme_toggle_spec.rb`; the full suite — including every existing 0b
  axe spec run in **both themes** (`axe_clean_in_both_themes?`) — must stay green. That green run
  IS the proof the param-driven theme mechanism works end to end.
- **2a:** no new tests (config + targeted docs); full suite green; gem template-backed test stays
  green.
- **2c:** one 0b axe spec per showcase scenario, asserting it renders and passes axe at AAA in
  **both** themes (CI-gated). Gem `showcase` scenarios are template-backed, so the gem's
  template-backed test covers their structure.

## Success criteria

- The `Theme` control appears in Lookbook's toolbar; toggling it re-renders the preview in
  dark/light; no toggle button overlaps any component; `preview_theme_controller.js` is gone.
- The Source panel shows a copyable canonical call for every component (template ERB, playground
  Ruby, or the `render "shared/…"` partial as appropriate).
- The 6 showcase scenarios render the full proven variant family on one screen and pass AAA in CI.
- Full suite green in both repos; gem `rake` (tests + RuboCop) green.
