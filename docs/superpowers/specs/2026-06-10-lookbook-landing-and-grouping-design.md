# Lookbook landing page + sidebar grouping — design

- **Date:** 2026-06-10
- **Status:** Approved (brainstorm complete) — ready for implementation plan
- **Scope:** Give the modelrails_ui Lookbook catalog a **front door** (a teaching Overview
  landing page) and a **map** (group the flat 78-item sidebar into 8 functional sections via
  `@logical_path`). Gem-first (durable artifact), then app-adopt. Tier 1 only — see Non-goals.
- **Origin:** 6-reviewer panel (Adam Wathan, Steve Schoger, Jason Fried, DHH, Chris Oliver,
  Brad Frost) reviewing the Lookbook catalog as a component-selection tool. All six named the
  same gap: excellent per-component docs, no orientation and no navigability around them.

## Problem

The Lookbook catalog (Lookbook 2.3.14, mounted dev-only at `/lookbook`) presents **78 app
components (80 in the gem) under a single flat `UI::` namespace**:

- **No front door.** A developer landing on `/lookbook` is dropped onto `accordion`
  (alphabetical accident) with no statement of what the system is, how to call it, or how it is
  organized.
- **No map.** The sidebar is one flat alphabetical list of 78. Related controls are scattered
  (`input` / `textarea` / `select` / `checkbox` are nowhere near each other); finding a
  component requires already knowing its name.

The per-component documentation is *not* the problem — the `## Use when` / `## Don't use when`
/ `## Accessibility contract` / `## Variants` doc-comments and the `dont_*` anti-pattern
scenarios are best-in-class and unanimously praised. The fix is **exposure and orientation, not
authoring.** Nobody is asking for more prose.

## Goals

1. A teaching **Overview landing page**, sorted first in the nav, that orients a developer in
   one screen.
2. The 78/80 components **grouped into 8 functional sections** in the sidebar.
3. Both shipped the **durable way**: in the gem's Lookbook generator templates, then adopted in
   the app — mirroring the component-hardening cross-repo groove.
4. A **consistency guard** so a future component cannot land ungrouped or mis-bucketed without
   failing CI.

## Non-goals (deferred — Tier 2/3 from the panel synthesis)

- Relocating the light/dark theme toggle out of the preview canvas (Tier 2).
- Per-section intro pages with "reach for X when…" decision tables (Tier 3).
- Surfacing the canonical `ui :name` invocation more prominently / code-copy affordances (Tier 2).
- Per-component "all variants" showcase scenarios (Tier 2).
- Extending `@param` playgrounds to the form-control family (Tier 3).
- Adding `## Related` / `## Composes` cross-links (Tier 3).
- Per-preview background framing (Tier 3).
- Resolving the stale `feat/lookbook-teaching-catalog` branch (separate decision).

Explicitly **not** doing (panel anti-recommendations): adding more doc-comment prose; making
every component an interactive playground; hiding the `dont_*` anti-patterns; porting
atoms/molecules/organisms into the nav; reorganizing preview files on disk.

## Feasibility (verified against lookbook-2.3.14 source)

- **`@logical_path`** is read per preview (`Lookbook::Entity#fetch_config(:logical_path)`),
  overriding the directory-derived nav path. → grouping is a **one-line magic comment per
  preview**, with **no file moves, no `UI::` class renames**, and no change to the gem→app copy
  glob or the template-backed preview test.
- **Pages** load from `config.lookbook.page_paths` (markdown / `.md.erb`). → the landing page
  ships as a template + a `page_paths` line in the initializer.
- **Open risk (settle in planning, not a design change):** Lookbook's page **`embed`** helper —
  confirm the exact syntax renders an existing preview scenario through the `component_preview`
  layout (so app CSS + AAA apply). Fallback if not: link to the scenarios instead of embedding
  them. Affects only the hero-component mechanism, not the design.

## The taxonomy

Group by **job-to-be-done, not atomic level** (a developer thinks "I need to show a message,"
not "I need a molecule"). Each of the 78 app components is assigned to exactly one section.

| Section | n | Members |
|---|---|---|
| **Forms & Inputs** | 21 | input, textarea, select, checkbox, radio_group, switch, toggle, toggle_group, range, number_input, search_input, file_input, input_otp, combobox, date_picker, timepicker, calendar, rating_input, floating_label, label, form_field |
| **Actions** | 4 | button, button_group, speed_dial, command |
| **Overlays** | 10 | dialog, alert_dialog, drawer, sheet, popover, tooltip, hover_card, dropdown_menu, context_menu, menubar |
| **Navigation** | 8 | navbar, sidebar, breadcrumb, tabs, bottom_nav, mega_menu, navigation_menu, footer |
| **Feedback & Status** | 8 | alert, banner, badge, progress, spinner, skeleton, indicator, stepper |
| **Data Display** | 11 | card, list_group, data_table, timeline, accordion, collapsible, chat_bubble, avatar, kbd, rating, chart |
| **Media** | 13 | image, picture, figure, gallery, audio, video, embed, iframe, carousel, qr_code, device_mockup, map_area, aspect_ratio |
| **Layout** | 3 | separator, scroll_area, resizable |

Total: **78** (app). Gem adds `wysiwyg` → Forms & Inputs (22) and `toaster` → Feedback & Status
(9), = **80**. (`wysiwyg`/`toaster` are hardened-superseded in-app — Lexxy and `shared/_toasts`
replace them — so they exist as gem 0a previews for downstream apps but are simply absent in
the app's preview set.)

The `@logical_path` value is the section name, e.g. `@logical_path "Forms & Inputs"`.

### Ratified edge-case placements

These were judgment calls, approved during brainstorm:

- **stepper → Feedback & Status, not Navigation.** Its own doc-comment states it "is NOT
  interactive navigation" — it is a progress indicator.
- **rating → Data Display** (read-only score) while **rating_input → Forms & Inputs** (the
  interactive control). Deliberate split.
- **command → Actions** (a ⌘K action-launcher).
- **chart → Data Display** (data visualization).
- **footer → Navigation** (wayfinding/site chrome).
- **aspect_ratio → Media** (ratio box, almost always wraps media).
- **accordion / collapsible → Data Display** (content disclosure).

## The landing page (Teaching front door)

A markdown `.md.erb` Lookbook Page, sorted first in the nav. Contents, in order:

1. **Identity (one line):** "AAA-proven (7:1 in CI) · OKLCH-themed · Hotwire-native
   ViewComponent library."
2. **The `ui()` facade:** the single canonical call, shown once
   (`<%= ui :button, "Save", variant: :solid, tone: :primary %>`).
3. **Reach for the Rails built-in first:** `f.submit` · `f.text_field` · `button_to`
   (destructive) — DHH's framing, so the catalog teaches restraint before reach.
4. **The four laws:** semantic tokens (no raw hex) · variant × tone · `data-slot` is the
   contract · focus = offset outline.
5. **3–4 live hero components:** rendered by embedding **existing AAA-proven scenarios**
   (button/primary, alert/info, card/default) — no new markup to prove. (Mechanism pending the
   `embed` confirmation above.)
6. **BROWSE index:** the 8 sections with counts, each linking into its grouped sidebar section;
   closes with "type in the sidebar filter to jump by name."

## Architecture & file changes

Durable artifact is the **gem**; the app vendors copies. Gem-first, then app-adopt — same
choreography as the hardening program.

### Gem (`modelrails_ui`, branch `modelrails/harden`)

- `lib/generators/modelrails_ui/lookbook/templates/previews/ui/*_component_preview.rb` —
  add one `@logical_path "<Section>"` magic comment to each of the 80 previews.
- `lib/generators/modelrails_ui/lookbook/templates/previews/pages/00_overview.md.erb` (new) —
  the landing page.
- `lib/generators/modelrails_ui/lookbook/templates/lookbook.rb` — wire
  `config.lookbook.page_paths` to the previews `pages/` directory.
- `lib/generators/modelrails_ui/lookbook/lookbook_generator.rb` — ensure the new `pages/`
  directory is copied (extend the existing `directory "previews"` glob or add a `pages` copy).
- Gem tests (see Testing).

### App (`modelrails_base`, branch off `main`)

- `spec/components/previews/ui/*_component_preview.rb` — mirror the `@logical_path` lines on the
  78 app previews.
- `spec/components/previews/pages/00_overview.md.erb` (new) — the landing page.
- `config/initializers/modelrails_ui_lookbook.rb` — set
  `config.lookbook.page_paths = [ <pages_dir> ]` (dev-only, alongside `preview_paths`).
- `spec/system/ui/lookbook_overview_spec.rb` (new) — the 0b system spec.

## Testing

**Gem:**
- A consistency guard test: **every** preview template declares a `@logical_path` whose value is
  one of the 8 canonical section strings (a new/mis-bucketed component fails CI).
- A test that `00_overview.md.erb` exists and `lookbook.rb` wires `page_paths`.
- The existing template-backed preview test stays green (adding comment lines must not break it).

**App (0b):**
- A system spec visiting the Overview page that asserts the hero components render and the 8
  BROWSE links are present, **with axe at WCAG 2.2 AAA** (the page renders real components, so
  AAA runs in CI per the project's CI-only AAA hook).
- Validated **locally before the gem PR merges**, per the proven cross-repo gate (local 0b
  catches generation/contrast/structural bugs that gem-side gates miss).

## Rollout / PR shape

- Grouping + landing page are **causally coupled** (the page's index links the sections the
  grouping creates) → **one gem PR**, then **one app PR**. (Option held: split grouping first,
  page second, if preferred.)
- Choreography: gem PR on `modelrails/harden` → app temp-pins that branch and validates 0b
  locally → app PR → **gem merges first only after app 0b is green** → app re-pins to
  `modelrails/harden` → app PR merges. Do not let the gem PR merge before app 0b validates.

## Success criteria

- `/lookbook` opens to the Overview page, not `accordion`.
- The sidebar shows 8 named, collapsible sections; every component sits in exactly one.
- The Overview page passes axe AAA in CI.
- The gem consistency guard fails if any preview lacks a valid `@logical_path`.
- Downstream `rails g modelrails_ui:lookbook` ships the grouped sidebar + landing page.
