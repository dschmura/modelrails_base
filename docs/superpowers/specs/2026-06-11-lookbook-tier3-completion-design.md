# Lookbook Tier 3 completion — design

**Date:** 2026-06-11 · **Status:** design approved, ready to plan · **Repos:** `modelrails_base` (app) + `modelrails_ui` (gem, `modelrails/harden` branch)

Closes out the Tier 3 roadmap from `docs/superpowers/handoff/2026-06-11-lookbook-tier3-handoff.md`
(3a exemplar shipped as app PR #285). Memory: `[[project_lookbook_catalog_improvements]]`.

## Goal

Finish Tier 3 as **three sequenced gem+app PR-pair cycles**, and make the gem carry the decision
pages (user decision) so new apps scaffold the full teaching catalog — including the gem-side fix
for the broken Overview embeds the gem still ships.

## Standing decisions (carried from the 3a exemplar + this brainstorm)

| Decision | Choice |
|----------|--------|
| Embed form on Pages | Scenario-less `<%= embed UI::FooComponentPreview %>` ONLY — `embed Klass, :leaf` resolves nil under the catalog-wide `@!group` grouping (raises `ActionView::Template::Error`). Guarded. |
| Table shape | Reach-for-it-when (per component: positive "use it when" + "Otherwise →" pointing at the sibling). Rows sourced from each component's own doc-comment — never invented. |
| Embeds per page | One per fork group, not per component. |
| Decision pages exist for | Forms & Inputs, Overlays, Navigation, Feedback & Status, Data Display, Media. **Layout and Actions are skipped** (too little sibling overlap = ceremony). |
| 3c+3e+3b | Bundled into one cycle (same preview-file family, one choreography). |
| 3d toolbar | Per-preview `@display` tags only — NO global toolbar dropdown. |
| Cross-repo | Gem-first per cycle; app syncs vendored copies (parity is SEMANTIC — per-repo RuboCop normalizes). The two PRs in a pair are independent (app doesn't consume gem templates at runtime) but validate the app locally first. |
| Render truth | Browser eyeball (both themes) before every app push — a green suite does not prove a Lookbook Page renders. |

## Verified facts (do not re-derive)

- Gem repo: `/Users/dschmura/Documents/code/modelrails_ui`, branch `modelrails/harden`. Its Lookbook
  generator template `templates/previews/pages/00_overview.md.erb` **still has the broken
  `embed Klass, :leaf` embeds** (lines 31–33) — the #285 fix was app-only. Cycle 1 fixes it.
- The generator copies previews recursively (`directory "previews", "spec/components/previews"`),
  so `templates/previews/pages/choosing/*.md.erb` flows to new apps with **zero generator changes**.
- The gem ships the preview layout template
  (`lib/generators/modelrails_ui/lookbook/templates/component_preview.html.erb`); the app's copy is
  `app/views/layouts/component_preview.html.erb` with hardcoded `<body class="bg-surface-raised text-text-body p-6">`.
- Lookbook 2.3.14 per-preview display options: `PreviewEntity#display_options` =
  `Lookbook.config.preview_display_options.deep_merge(fetch_config(:display_options))` (the YARD
  `@display key: value` tag); `ScenarioEntity#display_options` merges parent. Values reach the
  preview iframe as `params[:lookbook][:display][...]` — the exact pipeline the theme toolbar uses.
- **The 0b axe specs visit the VC preview host (`/rails/view_components/...`), not the Lookbook
  iframe — `@display` params never reach them.** 3d cannot affect AAA results.
- 3e targets (missing `## Accessibility contract` in preview headers): **breadcrumb, menubar,
  navbar, tabs** (the nav band). All other previews have the full structure.
- 3b targets (no `def playground`): **form_field, input, checkbox, radio_group, range**. 13 other
  components already have playgrounds; the pattern + `spec/system/ui/playground_smoke_spec.rb` exist.
- Lookbook is dev-only (undefined in the test env) → all guards are static source analysis
  (the established idiom: `logical_path_coverage_spec.rb`, `scenario_grouping_spec.rb`,
  `choosing_overlays_spec.rb`).
- Toolchain: app `mise exec -- bundle exec …`; gem `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH"`
  + bare `rake` (tests **and** RuboCop). Never `git add -A` in either repo.

## Cycle 1 — Decision pages everywhere (3a fan-out + gem carry)

**App (`modelrails_base`):**

- Renumber + add pages under `spec/components/previews/pages/choosing/`, mirroring the sidebar's
  section order:
  - `00_forms.md.erb` — label `Forms & Inputs` (21 siblings; forks ≈ text entry / selection /
    on-off toggles / date & time / field wrappers)
  - `01_overlays.md.erb` — **rename of the existing `00_overlays.md.erb`** (content unchanged)
  - `02_navigation.md.erb` — label `Navigation` (8 siblings; forks ≈ page-level chrome / in-page)
  - `03_feedback.md.erb` — label `Feedback & Status` (8 siblings; forks ≈ message surfaces /
    status markers / progress & loading)
  - `04_data_display.md.erb` — label `Data Display` (11 siblings; forks ≈ containers / records &
    collections / disclosure)
  - `05_media.md.erb` — label `Media` (13 siblings; forks ≈ images & figures / playback /
    embeds & framing)
  - Exact fork groupings and row copy are derived in the plan from each preview's doc-comment
    (`## Use when` where present, title description otherwise). One scenario-less embed per fork.
- **Generalize the guard** (`spec/components/previews/pages/choosing_overlays_spec.rb` →
  rename to `choosing_pages_spec.rb`): map each `choosing/NN_<name>.md.erb` to its section label,
  derive that section's sibling set from `@logical_path`, assert every sibling is routed
  (backtick-delimited match). The embed-form and preview-exists checks already run for all pages.

**Gem (`modelrails_ui`):**

- Copy the six finished `choosing/` pages into
  `lib/generators/modelrails_ui/lookbook/templates/previews/pages/choosing/`.
- Fix `templates/previews/pages/00_overview.md.erb` embeds → scenario-less form.
- Mirror the guard as a Minitest beside `test_lookbook_overview_page.rb`
  (e.g. `test_lookbook_choosing_pages.rb`): embed-form rule + per-section routing coverage over
  the template files.

## Cycle 2 — Preview-file enrichment (3b + 3c + 3e), gem-first

All three are edits to preview files that exist in both repos; gem templates first, app vendored
copies synced (semantic parity).

- **3e — doc-structure fill** on breadcrumb, menubar, navbar, tabs: add `## Accessibility
  contract` (Guarantees / You supply) and `## Use when` / `## Don't use when` where absent.
  Formalize-only — the contracts ship in the implementations; copy documents, never changes
  behavior.
- **3c — `## Related` cross-links**: one-line section listing genuinely related siblings
  (backticked). Starter graph (only known relationships): form_field ↔ input/label/select/
  checkbox/radio_group/textarea; menu trio (dropdown_menu/context_menu/menubar — shared `menu`
  controller); floating trio (popover/tooltip/hover_card); dialog family (dialog/alert_dialog/
  drawer/sheet — shared `modal` controller); gallery → dialog (modal reuse); card → list_group/
  avatar/badge (composition); toggle ↔ switch ↔ checkbox. The plan finalizes the list from the
  doc-comments; no invented links.
  **Guard:** every backticked name inside a `## Related` section must match a real
  `*_component_preview.rb` (static, same idiom).
- **3b — form-control playgrounds** on form_field, input, checkbox, radio_group, range:
  `@param` selects/toggles for the ARIA-relevant states (`required`, `invalid`, `hint`/
  `description`, `disabled` where supported), inline `def playground` rendering via `ui`,
  exempt from the template-backed test (existing convention). Extend
  `spec/system/ui/playground_smoke_spec.rb` with the five components, including assertions that
  flipping `required`/`invalid`/`hint` actually rewires `aria-required`/`aria-invalid`/
  `aria-describedby` in the rendered output (the teaching point of these playgrounds).

## Cycle 3 — Per-preview backgrounds (3d), gem-first

- **Layout** (gem template + app copy, kept in parity): body classes become driven by
  `params.dig(:lookbook, :display, :background)`:
  - `raised` / absent → `bg-surface-raised p-6` (current default, unchanged)
  - `sunken` → sunken surface token + `p-6`
  - `page` → page background token + `p-6`
  - `bleed` → page background token + `p-0` (edge-to-edge)
  - **Token names verified against the gem's CSS during the plan** (`bg-surface-sunken`,
    `bg-page` expected) — fail loud if a token is missing, never invent one.
- **Tags:** raised-surface components whose edges are invisible on the raised default get
  `# @display background: sunken` (candidates: card, dialog, alert_dialog, drawer, sheet —
  final list = components whose own root surface is `bg-surface-raised`, confirmed per component
  in the plan). Full-bleed components get `# @display background: bleed` (candidates: navbar,
  footer, banner, bottom_nav — confirmed per component). Everything else untagged.
- No global `preview_display_options` change (no toolbar dropdown).
- 0b/AAA unaffected (VC preview host doesn't read `@display`).
- **Guard:** static check that any `@display background:` value is one of the four allowed words.

## Sequencing & verification

1. Cycle 1 → 2 → 3; each pair merged before the next cycle starts (user merges on green).
2. Per cycle: gem `rake` green; app full suite green locally (`mise exec -- bundle exec rspec`);
   browser eyeball of affected Lookbook surfaces in light + dark before the app push; Lefthook
   pre-push gates the rest. Move `docs/component-standards/` aside for app pushes.
3. PR hygiene: read per-check states (`gh pr checks`), never `--watch` exit codes; careful-merge
   primitive if I merge anything (normally the user does).

## Out of scope

- SP4 `modelrails_ui:update` re-vendor engine (own brainstorm; this work *widens* the vendored
  surface, making SP4 more valuable — noted, not solved).
- Upstream Lookbook leaf-embed-under-grouping limitation (document in the gem test comment;
  optional upstream issue later).
- New doc prose beyond one framing sentence per fork; playgrounds beyond the five form controls;
  hiding `dont_*` scenarios; nav restructuring (panel guardrails).

## Success criteria

- All six sections with real sibling overlap have decision pages, in both repos, guarded in both.
- A fresh `rails g modelrails_ui:lookbook` scaffolds a **working** Overview (no nil embeds) plus
  the six decision pages.
- The four nav-band previews carry the full doc structure; the relationship graph is encoded and
  guarded; the five form-control playgrounds demonstrate live ARIA rewiring under smoke test.
- Raised components show visible edges in Lookbook; full-bleed components render edge-to-edge —
  verified by eyeball in both themes.
- Zero regressions: app suite green, gem `rake` green, all existing guards still pass.
