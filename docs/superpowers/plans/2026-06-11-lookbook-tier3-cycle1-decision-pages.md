# Lookbook Tier 3 Cycle 1 — Decision Pages Everywhere (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decision pages for all six sections with real sibling overlap, in both repos, guarded in both — plus the gem-side fix for the broken Overview embeds it still ships.

**Architecture:** Five new `choosing/` Lookbook Pages in the app (the Overlays exemplar renames to slot into section order), a generalized static guard, then the six finished pages copied into the gem's generator templates (with two gem-only rows added), the gem Overview embed fix, and a mirrored gem Minitest guard.

**Tech Stack:** Lookbook 2.3.14 Pages, RSpec static guards (app), Minitest static guards (gem), YARD `@logical_path` taxonomy.

**Spec:** `docs/superpowers/specs/2026-06-11-lookbook-tier3-completion-design.md`

---

## Pre-flight facts (verified — do not re-investigate)

- **Embed rule:** scenario-less `<%= embed UI::FooComponentPreview %>` ONLY. `embed Klass, :leaf` resolves nil under `@!group` grouping → `ActionView::Template::Error`.
- App branch `feat/lookbook-tier3-completion` exists (has the spec commit). Gem repo `/Users/dschmura/Documents/code/modelrails_ui` is on `modelrails/harden` with a dirty tracked `MODELRAILS_STATUS.md` — do NOT touch or stage it; never `git add -A` in either repo.
- Gem generator copies previews recursively (`directory "previews"`) — new template files need no generator change.
- Gem's `test/test_lookbook_overview_page.rb#test_every_embed_target_exists` scans `embed UI::(\w+)ComponentPreview,\s*:(\w+)` and asserts ≥3 — **it fails once Overview is fixed to scenario-less; update it in the same commit (Task 4).**
- Gem templates include gem-only previews `toaster` and `wysiwyg` (superseded in this app). The gem copies of the affected pages get extra sourced rows; each repo's guard derives sibling sets from its own previews.
- Section sibling sets (app): Forms & Inputs 21 · Overlays 10 · Navigation 8 · Feedback & Status 8 · Data Display 11 · Media 13. Layout/Actions get no page (by design — guard must not require one).
- Toolchain: app `mise exec -- bundle exec …`; gem `cd /Users/dschmura/Documents/code/modelrails_ui && PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" rake` (bare `rake` = tests + RuboCop).
- Full app suite green before every commit. AAA axe is CI-only; not affected by catalog pages.

## File structure

**App:**
- Create: `spec/components/previews/pages/choosing/00_forms.md.erb`, `02_navigation.md.erb`, `03_feedback.md.erb`, `04_data_display.md.erb`, `05_media.md.erb`
- Rename: `choosing/00_overlays.md.erb` → `choosing/01_overlays.md.erb` (content unchanged)
- Rename + rewrite: `spec/components/previews/pages/choosing_overlays_spec.rb` → `choosing_pages_spec.rb` (generalized guard)

**Gem (`/Users/dschmura/Documents/code/modelrails_ui`):**
- Create: `lib/generators/modelrails_ui/lookbook/templates/previews/pages/choosing/*.md.erb` (six files; two with extra gem-only rows)
- Modify: `…/templates/previews/pages/00_overview.md.erb` (embeds → scenario-less)
- Modify: `test/test_lookbook_overview_page.rb` (embed assertions → scenario-less form)
- Create: `test/test_lookbook_choosing_pages.rb` (mirrored guard)

---

### Task 1: App — generalized guard (the failing test)

**Files:**
- Rename+rewrite: `spec/components/previews/pages/choosing_overlays_spec.rb` → `spec/components/previews/pages/choosing_pages_spec.rb`

- [ ] **Step 1: Rename and rewrite the guard**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
git mv spec/components/previews/pages/choosing_overlays_spec.rb spec/components/previews/pages/choosing_pages_spec.rb
```

Replace the file's entire contents with:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Guards the Lookbook Pages (the Overview landing + the "choosing" decision pages).
# Static source analysis only — same idiom as logical_path_coverage_spec.rb and
# scenario_grouping_spec.rb (read files, scan, assert; no render).
#
# Lookbook is a development-only gem (undefined in the test env), so we cannot resolve
# embeds through Lookbook::Engine.previews here. Instead we enforce the convention that
# GUARANTEES an embed resolves under the catalog-wide @!group grouping:
#
#   `@!group Overview/Examples/Reference` nests every leaf scenario inside a group, so a
#   GROUPED preview's top-level scenarios become the GROUP names. `embed UI::FooComponentPreview, :basic`
#   then resolves to nil (":basic" is a nested leaf, not a top-level scenario) and the page
#   raises ActionView::Template::Error. (A flat/ungrouped preview WOULD resolve a named leaf —
#   but pages mix both, so the scenario-less form is enforced uniformly as the one rule that
#   always resolves.) The safe, universal form is a scenario-less `embed UI::FooComponentPreview`,
#   which renders the preview's default scenario.
#
# See docs/superpowers/specs/2026-06-11-lookbook-tier3-completion-design.md.
RSpec.describe "Lookbook Pages" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  pages_root = Rails.root.join("spec/components/previews/pages")

  scenario_defs = ->(src) { src.scan(/^\s+def ([a-z_][a-z0-9_]*)/).flatten - %w[input_attrs] }

  Dir.glob(pages_root.join("**/*.md.erb")).sort.each do |page|
    rel = page.sub("#{Rails.root}/", "")
    src = File.read(page)
    embeds = src.scan(/embed\s+(UI::\w+ComponentPreview)(\s*,\s*:\w+)?/)

    it "#{rel}: every embed uses the resolvable scenario-less form" do
      offenders = embeds.select { |_klass, scenario_arg| scenario_arg }.map(&:first).uniq
      expect(offenders).to be_empty,
        "grouping nests leaves, so `embed Klass, :leaf` resolves nil — drop the scenario arg: #{offenders.join(", ")}"
    end

    it "#{rel}: every embedded preview exists and has a default scenario" do
      embeds.each do |klass, _|
        file = klass.sub(/\AUI::/, "").sub(/ComponentPreview\z/, "").underscore
        preview_file = preview_root.join("#{file}_component_preview.rb")
        expect(File).to exist(preview_file), "#{klass}: no preview file at #{file}_component_preview.rb"
        expect(scenario_defs.call(File.read(preview_file))).not_to be_empty,
          "#{klass}: no scenario methods, so no default scenario to embed"
      end
    end
  end

  describe "the choosing decision pages" do
    # Filename → @logical_path section. Layout and Actions get no decision page by
    # design (too little sibling overlap); this map is the allowlist.
    section_by_page = {
      "choosing/00_forms.md.erb" => "Forms & Inputs",
      "choosing/01_overlays.md.erb" => "Overlays",
      "choosing/02_navigation.md.erb" => "Navigation",
      "choosing/03_feedback.md.erb" => "Feedback & Status",
      "choosing/04_data_display.md.erb" => "Data Display",
      "choosing/05_media.md.erb" => "Media"
    }

    it "maps every choosing page file to a section (no unmapped strays)" do
      actual = Dir.glob(pages_root.join("choosing/*.md.erb")).map { |p| p.sub("#{pages_root}/", "") }.sort
      expect(actual).to eq(section_by_page.keys.sort)
    end

    section_by_page.each do |rel, section|
      page_path = pages_root.join(rel)
      source = File.exist?(page_path) ? File.read(page_path) : ""

      siblings = Dir.glob(preview_root.join("*_component_preview.rb")).select do |path|
        File.read(path).match?(/^\s*#\s*@logical_path\s+#{Regexp.escape(section)}\s*$/)
      end.map { |path| File.basename(path, "_component_preview.rb") }.sort

      it "#{rel} routes every #{section} sibling" do
        expect(siblings).not_to be_empty
        # Match the backtick-delimited token, not a bare substring: otherwise `dialog`
        # would be falsely "covered" by `alert_dialog` and a dropped row would slip through.
        missing = siblings.reject { |name| source.match?(/`#{Regexp.escape(name)}`/) }
        expect(missing).to be_empty, "#{rel} is missing: #{missing.join(", ")}"
      end

      it "#{rel} embeds at least one live scenario per fork" do
        expect(source.scan(/embed\s+UI::\w+ComponentPreview/).size).to be >= 3
      end
    end
  end
end
```

- [ ] **Step 2: Run it — clean red**

Run: `mise exec -- bundle exec rspec spec/components/previews/pages/choosing_pages_spec.rb`
Expected: FAIL. "maps every choosing page file" fails (only `00_overlays.md.erb` exists, which isn't in the map); the five new pages' routing examples fail listing all siblings missing; `01_overlays.md.erb` routing fails (file doesn't exist yet under that name). No load errors.

- [ ] **Step 3: Rubocop the guard**

Run: `mise exec -- bundle exec rubocop spec/components/previews/pages/choosing_pages_spec.rb`
Expected: no offenses (wrap lines per offense if flagged; no `rubocop:disable`).

Do NOT commit — red by design.

---

### Task 2: App — the five pages + rename (goes green)

**Files:**
- Rename: `spec/components/previews/pages/choosing/00_overlays.md.erb` → `01_overlays.md.erb`
- Create: `00_forms.md.erb`, `02_navigation.md.erb`, `03_feedback.md.erb`, `04_data_display.md.erb`, `05_media.md.erb` (same dir)

Every row below is sourced from the component's own doc-comment (`## Use when` / `## Don't use when` where present, title description otherwise). Transcribe exactly.

- [ ] **Step 1: Rename the exemplar (content unchanged)**

```bash
git mv spec/components/previews/pages/choosing/00_overlays.md.erb spec/components/previews/pages/choosing/01_overlays.md.erb
```

- [ ] **Step 2: Create `choosing/00_forms.md.erb`**

```erb
---
label: Forms & Inputs
---

# Choosing a form control

Inside a `form_with`, reach for the form builder first — `f.text_field`, `f.select`,
`f.file_field` already render these primitives with label/hint/error wiring. Reach for a
primitive directly when you're outside a form or building something custom.

## Free text

| Component        | Reach for it when                                                      | Otherwise →       |
|------------------|------------------------------------------------------------------------|-------------------|
| `input`          | a one-off single-line text control outside `form_with`                 | `textarea`        |
| `textarea`       | multi-line free text — comments, descriptions, notes                   | `input`           |
| `floating_label` | a compact field whose label starts inside and floats on focus/value    | `input` + `label` |
| `search_input`   | a standalone search/filter box with a built-in accessible name         | `input`           |

<%= embed UI::InputComponentPreview %>

## Numbers & codes

| Component      | Reach for it when                                                       | Otherwise →               |
|----------------|--------------------------------------------------------------------------|---------------------------|
| `number_input` | an exact numeric entry with `min` / `max` / `step`                       | `range`                   |
| `range`        | an approximate pick from a continuous, bounded range                     | `number_input`            |
| `input_otp`    | confirming an out-of-band code — cells auto-advance and accept paste     | `input` (type: password)  |
| `rating_input` | a 1..max star score submitted in a form                                  | `rating` (display-only)   |

<%= embed UI::RangeComponentPreview %>

## Choosing from a list

| Component     | Reach for it when                                          | Otherwise →             |
|---------------|-------------------------------------------------------------|-------------------------|
| `select`      | a single choice from a short, known list                    | `combobox`              |
| `combobox`    | a long list that needs type-to-filter                       | `select`; `command` for actions |
| `radio_group` | a small fixed set where every option stays visible          | `select`                |

<%= embed UI::SelectComponentPreview %>

## On / off

| Component      | Reach for it when                                             | Otherwise →            |
|----------------|----------------------------------------------------------------|------------------------|
| `checkbox`     | an on/off choice submitted with a form                         | `switch`               |
| `switch`       | an immediate-effect on/off setting                             | `checkbox`             |
| `toggle`       | a standalone pressed/unpressed action button                   | `checkbox` / `switch`  |
| `toggle_group` | related toggles with single- or multi-active enforcement       | `toggle`               |

<%= embed UI::SwitchComponentPreview %>

## Date & time

| Component     | Reach for it when                                        | Otherwise →    |
|---------------|-----------------------------------------------------------|----------------|
| `date_picker` | a disclosure button opening a calendar popover            | `calendar`     |
| `calendar`    | an inline, always-visible month grid                      | `date_picker`  |
| `timepicker`  | an hour/minute spinbutton popover                         | `date_picker`  |

<%= embed UI::DatePickerComponentPreview %>

## Field wiring & uploads

| Component    | Reach for it when                                                            | Otherwise →               |
|--------------|-------------------------------------------------------------------------------|---------------------------|
| `label`      | captioning a control via `for:` (self-labelling `checkbox`/`radio_group` don't need it) | —              |
| `form_field` | hand-composing a one-off labelled field with hint/error ARIA wiring           | `form_with` + the builder |
| `file_input` | an upload control with AAA styling + ARIA (inside `form_with`: `f.file_field`) | —                        |

<%= embed UI::FormFieldComponentPreview %>
```

- [ ] **Step 3: Create `choosing/02_navigation.md.erb`**

```erb
---
label: Navigation
---

# Choosing navigation

Page chrome frames the whole screen; link flyouts reveal grouped destinations; the last
fork answers "where am I". Action menus (`dropdown_menu` / `context_menu` / `menubar`)
are commands, not navigation — see *Choosing › Overlays*.

## Page chrome

| Component    | Reach for it when                                                  | Otherwise →  |
|--------------|---------------------------------------------------------------------|--------------|
| `navbar`     | a responsive top bar — links collapse behind a hamburger on mobile  | `sidebar`    |
| `sidebar`    | a collapsible application rail with grouped items                   | `navbar`     |
| `bottom_nav` | fixed mobile bottom destinations (icon + label)                     | `navbar`     |
| `footer`     | the closing contentinfo landmark with link columns                  | —            |

<%= embed UI::NavbarComponentPreview %>

## Link flyouts

| Component         | Reach for it when                                                          | Otherwise →        |
|-------------------|------------------------------------------------------------------------------|--------------------|
| `navigation_menu` | a horizontal site nav with disclosure flyouts (APG navigation, not `role="menu"`) | `mega_menu`    |
| `mega_menu`       | a full-width panel of grouped links behind one disclosure button             | `navigation_menu`  |

<%= embed UI::NavigationMenuComponentPreview %>

## Where am I

| Component    | Reach for it when                                          | Otherwise →           |
|--------------|-------------------------------------------------------------|-----------------------|
| `breadcrumb` | a hierarchy trail — the last item is the current page       | `tabs`                |
| `tabs`       | switching between in-page panels (APG tabs)                 | `breadcrumb` / `navbar` |

<%= embed UI::TabsComponentPreview %>
```

- [ ] **Step 4: Create `choosing/03_feedback.md.erb`**

```erb
---
label: Feedback & Status
---

# Choosing feedback & status

Messages speak to the user; status markers annotate other elements; the last fork covers
waiting. Ephemeral flashes are neither — use the app's toast system (`shared/_toasts`).

## Messages

| Component | Reach for it when                                                       | Otherwise →  |
|-----------|---------------------------------------------------------------------------|--------------|
| `alert`   | an inline message tied to surrounding content (form error summary)        | `banner`     |
| `banner`  | a page-level announcement strip — promo, cookie notice, system notice     | `alert`      |

<%= embed UI::AlertComponentPreview %>

## Status markers

| Component   | Reach for it when                                                     | Otherwise →  |
|-------------|-------------------------------------------------------------------------|--------------|
| `badge`     | a compact label pill classifying nearby content (a link when `href:`)   | `indicator`  |
| `indicator` | a corner dot or count anchored on an icon/avatar/button                 | `badge`      |

<%= embed UI::BadgeComponentPreview %>

## Progress & loading

| Component  | Reach for it when                                              | Otherwise →  |
|------------|------------------------------------------------------------------|--------------|
| `progress` | determinate progress toward a known max                          | `spinner`    |
| `spinner`  | an indeterminate wait, announced to assistive tech               | `progress`   |
| `skeleton` | loading placeholder blocks while content arrives                 | `spinner`    |
| `stepper`  | where-you-are in a multi-step flow (display, not links)          | `progress`   |

<%= embed UI::ProgressComponentPreview %>
```

- [ ] **Step 5: Create `choosing/04_data_display.md.erb`**

```erb
---
label: Data Display
---

# Choosing data display

Pick by the shape of the data: grouped content, disclosed sections, people & messages,
or ordered sequences and values.

## Containers & rows

| Component    | Reach for it when                                                     | Otherwise →                |
|--------------|-------------------------------------------------------------------------|----------------------------|
| `card`       | grouping related content on a bordered, raised surface                  | `list_group` / `data_table` |
| `list_group` | a short set of related rows or links (a real `<ul>` of `<li>`)          | `data_table` / `timeline`  |
| `data_table` | a bounded, already-loaded set of rows worth sorting/filtering client-side | server-side pages (Pagy) |

<%= embed UI::CardComponentPreview %>

## Disclosure

| Component     | Reach for it when                                                   | Otherwise →   |
|---------------|----------------------------------------------------------------------|---------------|
| `accordion`   | a stack of independent `<details>` rows (FAQs, settings groups)       | `collapsible` |
| `collapsible` | a single CSS-only disclosure behind your own trigger                  | `accordion`   |

<%= embed UI::AccordionComponentPreview %>

## People & messages

| Component     | Reach for it when                                                          | Otherwise →   |
|---------------|------------------------------------------------------------------------------|---------------|
| `avatar`      | a non-user avatar or explicit photo/initials (for `User` records: `avatar_for`) | —          |
| `chat_bubble` | one message in a chat or comment transcript (sent vs received)               | `list_group`  |

<%= embed UI::ChatBubbleComponentPreview %>

## Sequences & values

| Component  | Reach for it when                                                            | Otherwise →                 |
|------------|--------------------------------------------------------------------------------|-----------------------------|
| `timeline` | dated, ordered events — activity feed, audit trail, release history            | `list_group`                |
| `rating`   | displaying a fixed star score the user can't change                            | `rating_input` (user picks) |
| `chart`    | plotting a small set of series on a canvas (pin Chart.js; describe the data)   | `data_table`                |
| `kbd`      | an inline keyboard-key chip ("Press ⌘K")                                       | `badge`                     |

<%= embed UI::TimelineComponentPreview %>
```

- [ ] **Step 6: Create `choosing/05_media.md.erb`**

```erb
---
label: Media
---

# Choosing media

Three families: first-party images, playback surfaces, and third-party embeds with
their framing helpers.

## Images

| Component | Reach for it when                                                      | Otherwise →           |
|-----------|--------------------------------------------------------------------------|-----------------------|
| `image`   | content imagery with a forced `alt` decision, lazy loading, `srcset`      | `picture`             |
| `picture` | art direction or format fallbacks (AVIF/WebP → JPEG)                      | `image`               |
| `figure`  | content that needs a visible caption                                      | `image`               |
| `gallery` | an image grid with a lightbox (reuses the modal `<dialog>`)               | `image` / `carousel`  |
| `qr_code` | a scannable payload — pre-rendered image or rqrcode output                | `image`               |

<%= embed UI::ImageComponentPreview %>

## Playback

| Component  | Reach for it when                                                   | Otherwise →            |
|------------|------------------------------------------------------------------------|------------------------|
| `video`    | native video with `<source>` fallbacks and caption `<track>`s          | `embed` (third-party)  |
| `audio`    | native audio with `<source>` fallbacks                                 | `video`                |
| `carousel` | a slide deck with prev/next/dots and a pause control (APG)             | `gallery`              |

<%= embed UI::CarouselComponentPreview %>

## Embeds & framing

| Component       | Reach for it when                                                  | Otherwise →  |
|-----------------|----------------------------------------------------------------------|--------------|
| `embed`         | third-party content by URL — the provider is auto-detected           | `iframe`     |
| `iframe`        | a raw sandboxed, responsive frame for anything else                  | `embed`      |
| `aspect_ratio`  | holding media to a fixed ratio regardless of width                   | —            |
| `device_mockup` | a decorative phone/tablet/browser shell around a screenshot          | —            |
| `map_area`      | a legacy image map (prefer overlaid links or SVG regions when you can) | —          |

<%= embed UI::DeviceMockupComponentPreview %>
```

- [ ] **Step 7: Guard goes green**

Run: `mise exec -- bundle exec rspec spec/components/previews/pages/choosing_pages_spec.rb`
Expected: PASS, 0 failures (map example + per-page embed-form/preview-exists + 6 routing + 6 embed-count examples).

- [ ] **Step 8: Full suite**

Run: `mise exec -- bundle exec rspec`
Expected: 0 failures.

- [ ] **Step 9: Commit**

```bash
git add spec/components/previews/pages/choosing/ spec/components/previews/pages/choosing_pages_spec.rb
git commit -m "feat(lookbook): decision pages for all six sections + generalized Pages guard (Tier 3 Cycle 1, app)"
```

(`git mv` already staged the renames; confirm with `git status --porcelain` that ONLY the choosing pages + guard are staged.)

---

### Task 3: App — browser verification (render truth)

A dev server runs on :3000. Lookbook reads pages live from disk.

- [ ] **Step 1:** For each of the six pages, load `http://localhost:3000/lookbook/pages/choosing/<name>` (`forms`, `overlays`, `navigation`, `feedback`, `data_display`, `media`) and confirm: HTTP 200, **no** `ActionView::Template::Error`, and `lookbook-embed` tags present (2 × embed count). Scriptable via Net::HTTP — assert `template_error=false` for all six.
- [ ] **Step 2:** Eyeball the Choosing group in the Pages sidebar: order must be Forms & Inputs → Overlays → Navigation → Feedback & Status → Data Display → Media. Spot-check one page in light AND dark themes.
- [ ] **Step 3:** If anything fails: fix, re-run Task 2 Steps 7–8, amend the commit.

---

### Task 4: Gem — carry the pages, fix Overview, mirror the guard

**Work from:** `/Users/dschmura/Documents/code/modelrails_ui`. Prefix Ruby with `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH"`. Branch off `modelrails/harden`:

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
git switch -c lookbook/choosing-pages modelrails/harden
```

- [ ] **Step 1: Copy the six finished app pages into gem templates**

```bash
mkdir -p lib/generators/modelrails_ui/lookbook/templates/previews/pages/choosing
cp /Users/dschmura/Documents/code/modelrails_base/spec/components/previews/pages/choosing/*.md.erb \
   lib/generators/modelrails_ui/lookbook/templates/previews/pages/choosing/
```

- [ ] **Step 2: Add the two gem-only rows (sourced)**

The gem templates include `toaster` and `wysiwyg` previews (superseded in the host app, present for fresh apps). Read each preview's header (`lib/generators/modelrails_ui/lookbook/templates/previews/ui/{toaster,wysiwyg}_component_preview.rb`), confirm its `@logical_path`, and add one sourced row to the gem copy of the matching page — expected:

- `wysiwyg` → `choosing/00_forms.md.erb`, **Free text** table:
  `| `wysiwyg` | rich-text editing surface (Trix/Quill adapter) | `textarea` |`
- `toaster` → `choosing/03_feedback.md.erb`, **Messages** table:
  `| `toaster` | stacked ephemeral toast notifications | `alert` / `banner` |`

Adjust wording to match each preview's actual doc-comment (sourced, not invented). If a component's `@logical_path` differs from expected, put the row in that section's page instead.

- [ ] **Step 3: Fix the Overview template embeds**

In `lib/generators/modelrails_ui/lookbook/templates/previews/pages/00_overview.md.erb` replace:

```erb
<%= embed UI::ButtonComponentPreview, :primary %>
<%= embed UI::BannerComponentPreview, :info %>
<%= embed UI::CardComponentPreview, :default %>
```

with:

```erb
<%= embed UI::ButtonComponentPreview %>
<%= embed UI::BannerComponentPreview %>
<%= embed UI::CardComponentPreview %>
```

- [ ] **Step 4: Update `test/test_lookbook_overview_page.rb#test_every_embed_target_exists`**

Replace the method with:

```ruby
  def test_every_embed_target_exists
    # Scenario-less embeds only: the catalog-wide @!group grouping nests leaf scenarios
    # inside groups, so `embed Klass, :leaf` resolves nil at runtime (Lookbook looks up
    # top-level scenario names, which are now the group names) and 500s the page.
    offenders = page_src.scan(/embed\s+UI::\w+ComponentPreview\s*,\s*:\w+/)

    assert_empty offenders, "use the scenario-less embed form: #{offenders.join(", ")}"

    embeds = page_src.scan(/embed\s+UI::(\w+)ComponentPreview\b/).flatten

    assert_operator embeds.size, :>=, 3, "page should embed at least 3 live hero scenarios"
    embeds.each do |klass|
      file = File.join(PREVIEW_ROOT, "#{klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}_component_preview.rb")

      assert_path_exists file, "embed references missing preview #{klass}"
      assert_match(/^\s+def [a-z_]/, File.read(file), "#{klass} has no scenarios to embed")
    end
  end
```

- [ ] **Step 5: Create `test/test_lookbook_choosing_pages.rb`**

```ruby
# frozen_string_literal: true

require "test_helper"

# The "choosing" decision pages must exist for every section with real sibling overlap,
# route every sibling in their section, and embed only in the scenario-less form (a
# `embed Klass, :leaf` resolves nil under the catalog-wide @!group grouping and 500s).
class TestLookbookChoosingPages < Minitest::Test
  GEN_ROOT = File.expand_path("../lib/generators/modelrails_ui/lookbook/templates", __dir__)
  PAGES_ROOT = File.join(GEN_ROOT, "previews/pages")
  PREVIEW_ROOT = File.join(GEN_ROOT, "previews/ui")

  # Layout and Actions get no decision page by design (too little sibling overlap).
  SECTION_BY_PAGE = {
    "choosing/00_forms.md.erb" => "Forms & Inputs",
    "choosing/01_overlays.md.erb" => "Overlays",
    "choosing/02_navigation.md.erb" => "Navigation",
    "choosing/03_feedback.md.erb" => "Feedback & Status",
    "choosing/04_data_display.md.erb" => "Data Display",
    "choosing/05_media.md.erb" => "Media"
  }.freeze

  def test_no_unmapped_choosing_pages
    actual = Dir.glob(File.join(PAGES_ROOT, "choosing/*.md.erb")).map { |p| p.sub("#{PAGES_ROOT}/", "") }.sort

    assert_equal SECTION_BY_PAGE.keys.sort, actual
  end

  def test_embeds_use_the_scenario_less_form
    Dir.glob(File.join(PAGES_ROOT, "**/*.md.erb")).sort.each do |page|
      offenders = File.read(page).scan(/embed\s+UI::\w+ComponentPreview\s*,\s*:\w+/)

      assert_empty offenders, "#{page}: use the scenario-less embed form"
    end
  end

  def test_every_embed_target_exists
    Dir.glob(File.join(PAGES_ROOT, "choosing/*.md.erb")).sort.each do |page|
      File.read(page).scan(/embed\s+UI::(\w+)ComponentPreview\b/).flatten.each do |klass|
        file = File.join(PREVIEW_ROOT, "#{klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}_component_preview.rb")

        assert_path_exists file, "#{page} embeds missing preview #{klass}"
      end
    end
  end

  def test_every_section_sibling_is_routed
    SECTION_BY_PAGE.each do |rel, section|
      page = File.join(PAGES_ROOT, rel)

      assert_path_exists page
      source = File.read(page)
      siblings = Dir.glob(File.join(PREVIEW_ROOT, "*_component_preview.rb")).select do |path|
        File.read(path).match?(/^\s*#\s*@logical_path\s+#{Regexp.escape(section)}\s*$/)
      end.map { |path| File.basename(path, "_component_preview.rb") }.sort

      refute_empty siblings, "#{section}: no previews carry this @logical_path"
      # Backtick-delimited match so `dialog` is not falsely covered by `alert_dialog`.
      missing = siblings.reject { |name| source.match?(/`#{Regexp.escape(name)}`/) }

      assert_empty missing, "#{rel} is missing: #{missing.join(", ")}"
    end
  end
end
```

- [ ] **Step 6: Gem CI — bare `rake` (tests AND RuboCop)**

Run: `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" rake`
Expected: 0 failures, 0 offenses. If `test_every_section_sibling_is_routed` fails on a gem-only component not yet routed (e.g. a third gem-only preview), add a sourced row for it — that's the guard working.

- [ ] **Step 7: Commit (stage explicitly — never `git add -A`; do not touch `MODELRAILS_STATUS.md`)**

```bash
git add lib/generators/modelrails_ui/lookbook/templates/previews/pages/ \
        test/test_lookbook_overview_page.rb test/test_lookbook_choosing_pages.rb
git commit -m "feat(lookbook): carry the six choosing decision pages + fix Overview embeds under grouping"
```

---

### Task 5: Ship both PRs

- [ ] **Step 1 (app):** `mv docs/component-standards /tmp/component-standards-wip` → `git push -u origin feat/lookbook-tier3-completion` (Lefthook runs full CI; never `LEFTHOOK=0`) → `mv /tmp/component-standards-wip docs/component-standards` → `gh pr create --base main` titled `feat(lookbook): decision pages for all six sections (Tier 3 Cycle 1)`, body summarizing: 5 new pages + exemplar renamed into section order + generalized guard; spec + plan included.
- [ ] **Step 2 (gem):** `git push -u origin lookbook/choosing-pages` → `gh pr create --base modelrails/harden` titled `feat(lookbook): choosing decision pages + Overview embed fix`, body noting the embed-under-grouping rule, the two gem-only rows, and the mirrored guard.
- [ ] **Step 3:** Report both PR URLs. The user merges on green (`gh pr checks <N>` — read per-check states, never `--watch` exit codes).

---

## Self-Review (done at planning time)

- **Spec coverage:** Cycle 1 fully covered — fan-out (Task 2), renumber (Tasks 1–2), generalized guard (Task 1), gem carry + gem-only rows (Task 4 Steps 1–2), gem Overview fix (Step 3) **including the gem test that would break** (Step 4), mirrored guard (Step 5), browser truth (Task 3), ship choreography (Task 5). Cycles 2–3 are separate plans by design.
- **Placeholders:** none — all six pages' complete content is in Task 2; the only adjust-on-read step (gem-only rows) provides concrete draft rows + a verification rule.
- **Consistency:** section map identical in app guard and gem test; embed regexes identical to the proven 3a forms; sibling counts per fork sum to section totals (21/8/8/11/13 ✓).
