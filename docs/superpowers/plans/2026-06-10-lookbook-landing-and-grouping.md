# Lookbook landing page + sidebar grouping — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the modelrails_ui Lookbook catalog a teaching Overview landing page and group its flat 78/80-component sidebar into 8 functional sections, shipped gem-first then app-adopted.

**Architecture:** Grouping is one `@logical_path "<Section>"` magic comment per preview (no file moves, no class renames). The landing page is a markdown `.md.erb` Lookbook Page that embeds already-AAA-proven scenarios. The gem's `directory "previews"` generator glob already copies a new `previews/pages/` dir, so only the initializer needs a `page_paths` line.

**Tech Stack:** Ruby 4.0.4, Rails 8.1, Lookbook 2.3.14, ViewComponent, Minitest (gem), RSpec (app). Two repos: `modelrails_ui` (gem, branch off `modelrails/harden`) and `modelrails_base` (app, branch `feat/lookbook-landing-and-grouping`).

**Spec:** `docs/superpowers/specs/2026-06-10-lookbook-landing-and-grouping-design.md`

**Reference — verified mechanisms (lookbook-2.3.14):**
- `@logical_path` tag: `lib/lookbook/entities/concerns/locatable_entity.rb:71` ("Can be altered using the `@logical_path` tag"); read via `fetch_config(:logical_path)`.
- **EXEMPLAR FINDING (Task 1, live-verified):** use the **UNQUOTED** form `# @logical_path Forms & Inputs` — lookbook-2.3.14 consumes the tag text verbatim (`PathUtils.to_path` just string-joins), so a quoted `"Forms & Inputs"` leaks the quotes into the nav label + URL. The tag value is the trimmed rest of the line. All 8 section names round-trip cleanly through `name.titleize` (the label derivation), so the unquoted names render exactly as the approved labels.
- Pages load from `config.lookbook.page_paths`; page route `/lookbook/pages/*path`; `00_` prefix sets priority + is stripped (`page_entity.rb:21`).
- Embed helper: `lib/lookbook/helpers/page_helper.rb:27` — `embed(preview, scenario = nil, **opts)`.

**Test-strategy note (refinement of spec):** The spec listed "Overview page passes axe AAA in CI." On investigation the page's only app-owned markup is the embedded scenarios, which are **independently AAA-proven by their existing 0b specs**; the surrounding page chrome is Lookbook's own UI (outside our AAA contract). This plan therefore proves the page via a **consistency test** (correct bucketing) + an **embed-target test** (every hero references a real preview+scenario) + a **manual dev render check**, instead of a browser axe spec. Flagged for confirmation in Task 7.

---

## The authoritative taxonomy map (source of truth)

Used verbatim by the gem test, the app spec, and both annotation scripts. 80 entries (gem); the app omits `toaster` and `wysiwyg` (hardened-superseded in-app), = 78.

```
Forms & Inputs:  input, textarea, select, checkbox, radio_group, switch, toggle,
                 toggle_group, range, number_input, search_input, file_input, input_otp,
                 combobox, date_picker, timepicker, calendar, rating_input, floating_label,
                 label, form_field, wysiwyg
Actions:         button, button_group, speed_dial, command
Overlays:        dialog, alert_dialog, drawer, sheet, popover, tooltip, hover_card,
                 dropdown_menu, context_menu, menubar
Navigation:      navbar, sidebar, breadcrumb, tabs, bottom_nav, mega_menu,
                 navigation_menu, footer
Feedback & Status: alert, banner, badge, progress, spinner, skeleton, indicator,
                 stepper, toaster
Data Display:    card, list_group, data_table, timeline, accordion, collapsible,
                 chat_bubble, avatar, kbd, rating, chart
Media:           image, picture, figure, gallery, audio, video, embed, iframe, carousel,
                 qr_code, device_mockup, map_area, aspect_ratio
Layout:          separator, scroll_area, resizable
```

---

## Task 1: Exemplar — annotate `button` in both repos, prove the mechanism live

Prove `@logical_path` groups a preview AND that the tag does not leak into the rendered Notes, on ONE component, before any bulk work. Mirrors the hardening program's exemplar-first groove.

**Files:**
- Modify (gem): `/Users/dschmura/Documents/code/modelrails_ui/lib/generators/modelrails_ui/lookbook/templates/previews/ui/button_component_preview.rb`
- Modify (app): `/Users/dschmura/Documents/code/modelrails_base/spec/components/previews/ui/button_component_preview.rb`

- [ ] **Step 1: Confirm gem branch**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
git fetch origin -q
git switch modelrails/harden -q && git pull --ff-only -q
git switch -c harden/lookbook-landing-grouping
git branch --show-current   # => harden/lookbook-landing-grouping
```

- [ ] **Step 2: Add the `@logical_path` tag to the gem button preview**

In `button_component_preview.rb`, insert the tag as the last line of the class doc-comment, immediately above the `class` line:

```ruby
  #   `solid/primary` · `solid/danger` · `outline/neutral` · `text/primary` · `text/danger`
  # @logical_path Actions
  class ButtonComponentPreview < ViewComponent::Preview
```

(Insertion anchor for all previews: the line `  class <Name>ComponentPreview < ViewComponent::Preview`; the tag goes on the line directly above it, contiguous with the existing comment block.)

- [ ] **Step 3: Mirror the same tag into the app button preview**

Apply the identical edit to the app file `spec/components/previews/ui/button_component_preview.rb` (same anchor, same `# @logical_path Actions`).

- [ ] **Step 4: Verify live in the app's Lookbook**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bin/rails server -p 3000
```

Open `http://localhost:3000/lookbook`. Confirm:
- The sidebar now shows an **"Actions"** group containing **Button** (instead of `button` at the flat top level).
- Open Button → the Notes panel shows the normal docs with **no literal `@logical_path "Actions"`** text leaking in.

Stop the server (Ctrl-C). If the tag leaks into Notes, STOP and report — placement/stripping needs adjustment before bulk work.

- [ ] **Step 5: Commit both repos**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git add -A && \
  git commit -m "feat(lookbook): logical_path grouping — button exemplar (Actions)"
cd /Users/dschmura/Documents/code/modelrails_base && git add -A && \
  git commit -m "feat(lookbook): logical_path grouping — button exemplar (Actions)"
```

---

## Task 2: Gem — consistency test + bulk-annotate the remaining 79 previews

**Files:**
- Create (gem): `test/test_lookbook_logical_paths.rb`
- Create (gem, one-off): `bin/annotate_logical_paths.rb`
- Modify (gem): all `lib/generators/modelrails_ui/lookbook/templates/previews/ui/*_component_preview.rb` (the 79 not done in Task 1)

- [ ] **Step 1: Write the failing consistency test**

Create `test/test_lookbook_logical_paths.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# Every Lookbook preview must declare a @logical_path that buckets it into one of the
# 8 canonical catalog sections. Guards against a new/renamed component landing ungrouped
# or in the wrong section. EXPECTED is the single source of truth for the taxonomy.
class TestLookbookLogicalPaths < Minitest::Test
  PREVIEW_ROOT = File.expand_path(
    "../lib/generators/modelrails_ui/lookbook/templates/previews/ui", __dir__
  )

  SECTIONS = [
    "Forms & Inputs", "Actions", "Overlays", "Navigation",
    "Feedback & Status", "Data Display", "Media", "Layout"
  ].freeze

  EXPECTED = {
    # Forms & Inputs
    "input" => "Forms & Inputs", "textarea" => "Forms & Inputs", "select" => "Forms & Inputs",
    "checkbox" => "Forms & Inputs", "radio_group" => "Forms & Inputs", "switch" => "Forms & Inputs",
    "toggle" => "Forms & Inputs", "toggle_group" => "Forms & Inputs", "range" => "Forms & Inputs",
    "number_input" => "Forms & Inputs", "search_input" => "Forms & Inputs",
    "file_input" => "Forms & Inputs", "input_otp" => "Forms & Inputs", "combobox" => "Forms & Inputs",
    "date_picker" => "Forms & Inputs", "timepicker" => "Forms & Inputs", "calendar" => "Forms & Inputs",
    "rating_input" => "Forms & Inputs", "floating_label" => "Forms & Inputs", "label" => "Forms & Inputs",
    "form_field" => "Forms & Inputs", "wysiwyg" => "Forms & Inputs",
    # Actions
    "button" => "Actions", "button_group" => "Actions", "speed_dial" => "Actions", "command" => "Actions",
    # Overlays
    "dialog" => "Overlays", "alert_dialog" => "Overlays", "drawer" => "Overlays", "sheet" => "Overlays",
    "popover" => "Overlays", "tooltip" => "Overlays", "hover_card" => "Overlays",
    "dropdown_menu" => "Overlays", "context_menu" => "Overlays", "menubar" => "Overlays",
    # Navigation
    "navbar" => "Navigation", "sidebar" => "Navigation", "breadcrumb" => "Navigation",
    "tabs" => "Navigation", "bottom_nav" => "Navigation", "mega_menu" => "Navigation",
    "navigation_menu" => "Navigation", "footer" => "Navigation",
    # Feedback & Status
    "alert" => "Feedback & Status", "banner" => "Feedback & Status", "badge" => "Feedback & Status",
    "progress" => "Feedback & Status", "spinner" => "Feedback & Status", "skeleton" => "Feedback & Status",
    "indicator" => "Feedback & Status", "stepper" => "Feedback & Status", "toaster" => "Feedback & Status",
    # Data Display
    "card" => "Data Display", "list_group" => "Data Display", "data_table" => "Data Display",
    "timeline" => "Data Display", "accordion" => "Data Display", "collapsible" => "Data Display",
    "chat_bubble" => "Data Display", "avatar" => "Data Display", "kbd" => "Data Display",
    "rating" => "Data Display", "chart" => "Data Display",
    # Media
    "image" => "Media", "picture" => "Media", "figure" => "Media", "gallery" => "Media",
    "audio" => "Media", "video" => "Media", "embed" => "Media", "iframe" => "Media",
    "carousel" => "Media", "qr_code" => "Media", "device_mockup" => "Media",
    "map_area" => "Media", "aspect_ratio" => "Media",
    # Layout
    "separator" => "Layout", "scroll_area" => "Layout", "resizable" => "Layout"
  }.freeze

  def all_preview_components
    Dir.glob(File.join(PREVIEW_ROOT, "*_component_preview.rb"))
      .map { |p| File.basename(p, "_component_preview.rb") }
  end

  def declared_logical_path(component)
    src = File.read(File.join(PREVIEW_ROOT, "#{component}_component_preview.rb"))
    # Unquoted form: value is the trimmed rest of the line (see EXEMPLAR FINDING).
    src[/^\s*#\s*@logical_path\s+(.+?)\s*$/, 1]
  end

  def test_every_preview_is_in_the_expected_map
    extra = all_preview_components - EXPECTED.keys
    missing = EXPECTED.keys - all_preview_components
    assert_empty extra, "previews with no EXPECTED section (add them to the map): #{extra.sort}"
    assert_empty missing, "EXPECTED components with no preview file: #{missing.sort}"
  end

  def test_every_preview_declares_its_expected_logical_path
    all_preview_components.each do |component|
      actual = declared_logical_path(component)
      refute_nil actual, "#{component}: missing `@logical_path` tag"
      assert_includes SECTIONS, actual, "#{component}: `#{actual}` is not a canonical section"
      assert_equal EXPECTED[component], actual, "#{component}: expected `#{EXPECTED[component]}`, got `#{actual}`"
    end
  end
end
```

- [ ] **Step 2: Run the test — verify it fails**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby -Itest test/test_lookbook_logical_paths.rb
```

Expected: FAIL — `test_every_preview_declares_its_expected_logical_path` reports ~79 components "missing `@logical_path` tag" (only `button` from Task 1 has it).

- [ ] **Step 3: Write the one-off annotation script**

Create `bin/annotate_logical_paths.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off: insert `# @logical_path "<Section>"` into each preview, on the line directly
# above its `class ...ComponentPreview` declaration. Idempotent (skips files already tagged).
# Reuses the taxonomy from the test so the two cannot drift.
require_relative "../test/test_lookbook_logical_paths"

root = TestLookbookLogicalPaths::PREVIEW_ROOT
TestLookbookLogicalPaths::EXPECTED.each do |component, section|
  path = File.join(root, "#{component}_component_preview.rb")
  next unless File.exist?(path)
  src = File.read(path)
  next if src.match?(/^\s*#\s*@logical_path\s/)        # already tagged (e.g. button)

  updated = src.sub(/^(\s*)(class \w+ComponentPreview < ViewComponent::Preview)/) do
    "#{Regexp.last_match(1)}# @logical_path #{section}\n#{Regexp.last_match(1)}#{Regexp.last_match(2)}"
  end
  abort "FAILED to anchor #{component}" if updated == src
  File.write(path, updated)
  puts "tagged #{component} => #{section}"
end
```

- [ ] **Step 4: Run the script**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby bin/annotate_logical_paths.rb
```

Expected: prints `tagged <component> => <section>` for the 79 untagged previews.

- [ ] **Step 5: Review the diff (do NOT trust the count)**

```bash
git diff --stat        # expect ~79 files, +1 line each
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/alert_component_preview.rb
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/data_table_component_preview.rb
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/qr_code_component_preview.rb
```

Confirm each inserted line sits immediately above the `class` line, is correctly indented, and the section is right. (Per the bulk-replace discipline: verify the diff, not the "N changed" count.)

- [ ] **Step 6: Run the consistency test — verify it passes**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby -Itest test/test_lookbook_logical_paths.rb
```

Expected: PASS (2 runs, 0 failures).

- [ ] **Step 7: Run the full gem test suite (regression — template-backed test must stay green)**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" rake test 2>&1 | tail -20
```

Expected: 0 failures, 0 errors. (Confirms the added comment lines did not break `test_lookbook_previews_template_backed.rb`.)

- [ ] **Step 8: Remove the one-off script and commit**

```bash
git rm -f bin/annotate_logical_paths.rb
git add -A
git commit -m "feat(lookbook): bucket all previews into 8 sections via @logical_path

Adds a consistency test (test_lookbook_logical_paths) as the taxonomy source of
truth; a future ungrouped or mis-bucketed preview now fails CI."
```

---

## Task 3: Gem — Overview landing page + page structure test + initializer `page_paths`

**Files:**
- Create (gem): `lib/generators/modelrails_ui/lookbook/templates/previews/pages/00_overview.md.erb`
- Modify (gem): `lib/generators/modelrails_ui/lookbook/templates/lookbook.rb`
- Create (gem): `test/test_lookbook_overview_page.rb`

- [ ] **Step 1: Write the failing page test**

Create `test/test_lookbook_overview_page.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# The Overview landing page must exist, teach the core conventions, and embed only
# scenarios that actually exist (a broken embed target would 500 the page at runtime).
class TestLookbookOverviewPage < Minitest::Test
  GEN_ROOT = File.expand_path("../lib/generators/modelrails_ui/lookbook/templates", __dir__)
  PAGE = File.join(GEN_ROOT, "previews/pages/00_overview.md.erb")
  PREVIEW_ROOT = File.join(GEN_ROOT, "previews/ui")
  INITIALIZER = File.join(GEN_ROOT, "lookbook.rb")

  SECTIONS = [
    "Forms & Inputs", "Actions", "Overlays", "Navigation",
    "Feedback & Status", "Data Display", "Media", "Layout"
  ].freeze

  def page_src
    File.read(PAGE)
  end

  def test_page_exists_and_sorts_first
    assert_path_exists PAGE, "Overview page must exist at previews/pages/00_overview.md.erb"
    assert_match(/label:\s*Overview/, page_src, "page needs a front-matter `label: Overview`")
  end

  def test_page_teaches_core_conventions
    assert_includes page_src, "ui :button", "page must show the ui() facade call"
    assert_includes page_src, "f.submit", "page must teach 'reach for the Rails built-in first'"
    SECTIONS.each do |section|
      assert_includes page_src, section, "page BROWSE index must list the `#{section}` section"
    end
  end

  def test_every_embed_target_exists
    embeds = page_src.scan(/embed\s+UI::(\w+)ComponentPreview,\s*:(\w+)/)
    assert_operator embeds.size, :>=, 3, "page should embed at least 3 live hero scenarios"
    embeds.each do |klass, scenario|
      file = File.join(PREVIEW_ROOT, "#{klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}_component_preview.rb")
      assert_path_exists file, "embed references missing preview #{klass}"
      assert_match(/def #{scenario}\b/, File.read(file), "embed references missing scenario :#{scenario} on #{klass}")
    end
  end

  def test_initializer_wires_page_paths
    assert_match(/page_paths\s*=/, File.read(INITIALIZER), "lookbook.rb must set config.lookbook.page_paths")
  end
end
```

- [ ] **Step 2: Run it — verify it fails**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby -Itest test/test_lookbook_overview_page.rb
```

Expected: FAIL — page file does not exist; `page_paths` not set.

- [ ] **Step 3: Create the Overview page**

Create `lib/generators/modelrails_ui/lookbook/templates/previews/pages/00_overview.md.erb`:

```erb
---
label: Overview
---

# modelrails_ui

An **AAA-proven** (7:1 contrast, verified in CI) · **OKLCH-themed** · **Hotwire-native**
ViewComponent library. Call every component through the `ui()` facade:

```erb
<%%= ui :button, "Save changes", variant: :solid, tone: :primary %>
```

## Reach for the Rails built-in first

Before reaching for a component, prefer the framework primitive:

- **`f.submit`** — form submits (already styled primary)
- **`f.text_field`** &c. — form inputs
- **`button_to`** — destructive / non-GET actions (CSRF-protected)

## The four laws

1. **Semantic tokens, never raw values** — `bg-surface`, `text-text-body`, `bg-hue-*`; no hex.
2. **Two-axis variants** — `variant:` (shape) × `tone:` (signal).
3. **`data-slot` is the contract** — compound parts tag their roles; spacing + ARIA key off it.
4. **Focus is an offset `outline`** — the `focus-ring` utility, never a `ring`.

## Live examples

<%= embed UI::ButtonComponentPreview, :primary %>
<%= embed UI::BannerComponentPreview, :info %>
<%= embed UI::CardComponentPreview, :default %>

## Browse

The sidebar groups all components into eight sections. Start typing in the sidebar
filter to jump to any component by name.

- **Forms & Inputs** — text fields, selection controls, pickers, field wrappers
- **Actions** — buttons and command launchers
- **Overlays** — dialogs, drawers, sheets, popovers, menus
- **Navigation** — bars, sidebars, breadcrumbs, tabs
- **Feedback & Status** — alerts, banners, badges, progress
- **Data Display** — cards, tables, timelines, avatars
- **Media** — images, audio, video, embeds
- **Layout** — separators, scroll areas, resizables
```

(Note: `<%%=` escapes the ERB so the facade renders as a literal `<%=` code sample; the `embed` lines use real `<%= %>`.)

- [ ] **Step 4: Wire `page_paths` into the initializer template**

In `lib/generators/modelrails_ui/lookbook/templates/lookbook.rb`, add the page path inside the `if Rails.env.development?` block, after the `preview_paths` line:

```ruby
  # Lookbook keeps its OWN preview_paths (separate from ViewComponent's).
  Rails.application.config.lookbook.preview_paths = [preview_dir]
  Rails.application.config.lookbook.page_paths = [Rails.root.join("spec/components/previews/pages").to_s]
```

- [ ] **Step 5: Run the page test — verify it passes**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby -Itest test/test_lookbook_overview_page.rb
```

Expected: PASS (4 runs, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(lookbook): teaching Overview landing page + wire page_paths"
```

---

## Task 4: App — bulk-annotate the 78 app previews + app consistency spec

**Files:**
- Create (app): `spec/components/previews/ui/logical_path_coverage_spec.rb`
- Create (app, one-off): `bin/annotate_logical_paths.rb`
- Modify (app): all `spec/components/previews/ui/*_component_preview.rb` (the 77 not done in Task 1)

- [ ] **Step 1: Write the failing app consistency spec**

Create `spec/components/previews/ui/logical_path_coverage_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Mirror of the gem's taxonomy guard: every vendored app preview must declare a
# @logical_path in one of the 8 canonical sections. (toaster/wysiwyg are gem-only —
# superseded in this app — so they are absent here by design.)
RSpec.describe "Lookbook preview logical_path coverage" do
  preview_root = Rails.root.join("spec/components/previews/ui")

  sections = [
    "Forms & Inputs", "Actions", "Overlays", "Navigation",
    "Feedback & Status", "Data Display", "Media", "Layout"
  ]

  expected = {
    "input" => "Forms & Inputs", "textarea" => "Forms & Inputs", "select" => "Forms & Inputs",
    "checkbox" => "Forms & Inputs", "radio_group" => "Forms & Inputs", "switch" => "Forms & Inputs",
    "toggle" => "Forms & Inputs", "toggle_group" => "Forms & Inputs", "range" => "Forms & Inputs",
    "number_input" => "Forms & Inputs", "search_input" => "Forms & Inputs",
    "file_input" => "Forms & Inputs", "input_otp" => "Forms & Inputs", "combobox" => "Forms & Inputs",
    "date_picker" => "Forms & Inputs", "timepicker" => "Forms & Inputs", "calendar" => "Forms & Inputs",
    "rating_input" => "Forms & Inputs", "floating_label" => "Forms & Inputs", "label" => "Forms & Inputs",
    "form_field" => "Forms & Inputs",
    "button" => "Actions", "button_group" => "Actions", "speed_dial" => "Actions", "command" => "Actions",
    "dialog" => "Overlays", "alert_dialog" => "Overlays", "drawer" => "Overlays", "sheet" => "Overlays",
    "popover" => "Overlays", "tooltip" => "Overlays", "hover_card" => "Overlays",
    "dropdown_menu" => "Overlays", "context_menu" => "Overlays", "menubar" => "Overlays",
    "navbar" => "Navigation", "sidebar" => "Navigation", "breadcrumb" => "Navigation",
    "tabs" => "Navigation", "bottom_nav" => "Navigation", "mega_menu" => "Navigation",
    "navigation_menu" => "Navigation", "footer" => "Navigation",
    "alert" => "Feedback & Status", "banner" => "Feedback & Status", "badge" => "Feedback & Status",
    "progress" => "Feedback & Status", "spinner" => "Feedback & Status", "skeleton" => "Feedback & Status",
    "indicator" => "Feedback & Status", "stepper" => "Feedback & Status",
    "card" => "Data Display", "list_group" => "Data Display", "data_table" => "Data Display",
    "timeline" => "Data Display", "accordion" => "Data Display", "collapsible" => "Data Display",
    "chat_bubble" => "Data Display", "avatar" => "Data Display", "kbd" => "Data Display",
    "rating" => "Data Display", "chart" => "Data Display",
    "image" => "Media", "picture" => "Media", "figure" => "Media", "gallery" => "Media",
    "audio" => "Media", "video" => "Media", "embed" => "Media", "iframe" => "Media",
    "carousel" => "Media", "qr_code" => "Media", "device_mockup" => "Media",
    "map_area" => "Media", "aspect_ratio" => "Media",
    "separator" => "Layout", "scroll_area" => "Layout", "resizable" => "Layout"
  }

  components = Dir.glob(preview_root.join("*_component_preview.rb"))
    .map { |p| File.basename(p, "_component_preview.rb") }

  it "covers every preview in the expected taxonomy map" do
    expect(components - expected.keys).to be_empty
    expect(expected.keys - components).to be_empty
  end

  components.each do |component|
    it "#{component} declares its expected @logical_path" do
      src = File.read(preview_root.join("#{component}_component_preview.rb"))
      actual = src[/^\s*#\s*@logical_path\s+(.+?)\s*$/, 1]
      expect(actual).not_to be_nil, "#{component}: missing @logical_path tag"
      expect(sections).to include(actual)
      expect(actual).to eq(expected[component])
    end
  end
end
```

- [ ] **Step 2: Run it — verify it fails**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec spec/components/previews/ui/logical_path_coverage_spec.rb 2>&1 | tail -15
```

Expected: FAIL — 77 examples report "missing @logical_path tag" (only `button` from Task 1 has it).

- [ ] **Step 3: Write + run the app annotation script**

Create `bin/annotate_logical_paths.rb` (app version — embeds the same 78-entry map inline, since the app spec defines it in a `let`/local rather than a reusable constant):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off: insert `# @logical_path "<Section>"` above each app preview's class line.
EXPECTED = {
  "input" => "Forms & Inputs", "textarea" => "Forms & Inputs", "select" => "Forms & Inputs",
  "checkbox" => "Forms & Inputs", "radio_group" => "Forms & Inputs", "switch" => "Forms & Inputs",
  "toggle" => "Forms & Inputs", "toggle_group" => "Forms & Inputs", "range" => "Forms & Inputs",
  "number_input" => "Forms & Inputs", "search_input" => "Forms & Inputs", "file_input" => "Forms & Inputs",
  "input_otp" => "Forms & Inputs", "combobox" => "Forms & Inputs", "date_picker" => "Forms & Inputs",
  "timepicker" => "Forms & Inputs", "calendar" => "Forms & Inputs", "rating_input" => "Forms & Inputs",
  "floating_label" => "Forms & Inputs", "label" => "Forms & Inputs", "form_field" => "Forms & Inputs",
  "button" => "Actions", "button_group" => "Actions", "speed_dial" => "Actions", "command" => "Actions",
  "dialog" => "Overlays", "alert_dialog" => "Overlays", "drawer" => "Overlays", "sheet" => "Overlays",
  "popover" => "Overlays", "tooltip" => "Overlays", "hover_card" => "Overlays",
  "dropdown_menu" => "Overlays", "context_menu" => "Overlays", "menubar" => "Overlays",
  "navbar" => "Navigation", "sidebar" => "Navigation", "breadcrumb" => "Navigation",
  "tabs" => "Navigation", "bottom_nav" => "Navigation", "mega_menu" => "Navigation",
  "navigation_menu" => "Navigation", "footer" => "Navigation",
  "alert" => "Feedback & Status", "banner" => "Feedback & Status", "badge" => "Feedback & Status",
  "progress" => "Feedback & Status", "spinner" => "Feedback & Status", "skeleton" => "Feedback & Status",
  "indicator" => "Feedback & Status", "stepper" => "Feedback & Status",
  "card" => "Data Display", "list_group" => "Data Display", "data_table" => "Data Display",
  "timeline" => "Data Display", "accordion" => "Data Display", "collapsible" => "Data Display",
  "chat_bubble" => "Data Display", "avatar" => "Data Display", "kbd" => "Data Display",
  "rating" => "Data Display", "chart" => "Data Display",
  "image" => "Media", "picture" => "Media", "figure" => "Media", "gallery" => "Media",
  "audio" => "Media", "video" => "Media", "embed" => "Media", "iframe" => "Media",
  "carousel" => "Media", "qr_code" => "Media", "device_mockup" => "Media",
  "map_area" => "Media", "aspect_ratio" => "Media",
  "separator" => "Layout", "scroll_area" => "Layout", "resizable" => "Layout"
}.freeze

root = File.expand_path("../spec/components/previews/ui", __dir__)
EXPECTED.each do |component, section|
  path = File.join(root, "#{component}_component_preview.rb")
  next unless File.exist?(path)
  src = File.read(path)
  next if src.match?(/^\s*#\s*@logical_path\s/)
  updated = src.sub(/^(\s*)(class \w+ComponentPreview < ViewComponent::Preview)/) do
    "#{Regexp.last_match(1)}# @logical_path #{section}\n#{Regexp.last_match(1)}#{Regexp.last_match(2)}"
  end
  abort "FAILED to anchor #{component}" if updated == src
  File.write(path, updated)
  puts "tagged #{component} => #{section}"
end
```

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby bin/annotate_logical_paths.rb
```

- [ ] **Step 4: Review the diff**

```bash
git diff --stat   # expect ~77 files, +1 line each
git diff spec/components/previews/ui/alert_component_preview.rb spec/components/previews/ui/stepper_component_preview.rb
```

Confirm placement/indent/section on a sample.

- [ ] **Step 5: Run the app consistency spec — verify it passes**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec spec/components/previews/ui/logical_path_coverage_spec.rb 2>&1 | tail -10
```

Expected: PASS (79 examples, 0 failures).

- [ ] **Step 6: Remove the one-off script and commit**

```bash
git rm -f bin/annotate_logical_paths.rb
git add -A
git commit -m "feat(lookbook): bucket the 78 app previews into 8 sections via @logical_path"
```

---

## Task 5: App — Overview page + initializer `page_paths`

**Files:**
- Create (app): `spec/components/previews/pages/00_overview.md.erb`
- Modify (app): `config/initializers/modelrails_ui_lookbook.rb`

- [ ] **Step 1: Copy the Overview page from the gem verbatim**

```bash
mkdir -p spec/components/previews/pages
cp /Users/dschmura/Documents/code/modelrails_ui/lib/generators/modelrails_ui/lookbook/templates/previews/pages/00_overview.md.erb \
   spec/components/previews/pages/00_overview.md.erb
```

- [ ] **Step 2: Wire `page_paths` into the app initializer**

In `config/initializers/modelrails_ui_lookbook.rb`, inside the existing `if Rails.env.development?` portion (the block that sets `lookbook.preview_paths`), add:

```ruby
  Rails.application.config.lookbook.preview_paths = [ preview_dir ] if Rails.env.development?
  Rails.application.config.lookbook.page_paths = [ Rails.root.join("spec/components/previews/pages").to_s ] if Rails.env.development?
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(lookbook): adopt Overview landing page + wire page_paths"
```

---

## Task 6: App — live verification + full suite

**Files:** none (verification only; commit only if a fix is needed).

- [ ] **Step 1: Boot the app and verify the grouped catalog + landing page**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bin/rails server -p 3000
```

Open `http://localhost:3000/lookbook`. Confirm:
- The default view is the **Overview** page (sorted first), showing the facade snippet, the four laws, **three live hero components** (button, banner, card) rendered correctly, and the BROWSE list.
- Direct URL `http://localhost:3000/lookbook/pages/overview` loads.
- The sidebar shows **8 collapsible sections**; every component appears under exactly one; no leftover flat top-level components.
- Toggle one component to dark mode (the in-canvas `◐` toggle) to confirm previews still render. Stop the server.

- [ ] **Step 2: Run the full app test suite (must be 0 failures before any push)**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec 2>&1 | tail -25
```

Expected: 0 failures, 0 errors. Investigate any pending. If a real failure surfaces, fix it, re-run, and commit the fix with a descriptive message.

---

## Task 7: Cross-repo merge choreography

Ship gem-first, validate app 0b locally before the gem merges, per the hardening groove. **Confirm with the user before opening PRs** (and confirm the Task-strategy note about axe-AAA).

- [ ] **Step 1: Push the gem branch and open its PR**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
git push -u origin harden/lookbook-landing-grouping
gh pr create --base modelrails/harden --title "feat(lookbook): Overview landing page + 8-section sidebar grouping" \
  --body "Tier 1 of the Lookbook panel review. @logical_path grouping (taxonomy guard test) + teaching Overview page. App PR: dschmura/modelrails_base (pending)."
```

- [ ] **Step 2: Temp-pin the app Gemfile to the gem branch and validate**

In the app `Gemfile`, point the `modelrails_ui` line at `branch: "harden/lookbook-landing-grouping"`, then:

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle install
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec 2>&1 | tail -15
```

Expected: green. (Validates the gem branch against the app before the gem PR merges.)

- [ ] **Step 3: Push the app branch and open its PR; let CI run**

```bash
git push -u origin feat/lookbook-landing-and-grouping
gh pr create --base main --title "feat(lookbook): Overview landing page + 8-section sidebar grouping" \
  --body "Tier 1 of the Lookbook panel review. Mirrors gem PR (logical_path grouping + Overview page). Temp-pinned to harden/lookbook-landing-grouping; will re-pin to modelrails/harden once the gem PR merges."
```

Watch CI to green: `gh pr checks --watch`.

- [ ] **Step 4: Merge gem PR (careful-merge), then re-pin the app**

Once the app CI is green against the gem branch, merge the gem PR with the full-SHA careful-merge primitive:

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
SHA=$(gh pr view <GEM_PR> --json headRefOid -q .headRefOid)
gh api -X PUT /repos/dschmura/modelrails_ui/pulls/<GEM_PR>/merge -f sha="$SHA" -f merge_method=squash
```

Then re-pin the app `Gemfile` back to `branch: "modelrails/harden"`, `bundle install`, commit, and push to the app PR branch.

- [ ] **Step 5: Merge the app PR (careful-merge) after its CI is green**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
SHA=$(gh pr view <APP_PR> --json headRefOid -q .headRefOid)
gh api -X PUT /repos/dschmura/modelrails_base/pulls/<APP_PR>/merge -f sha="$SHA" -f merge_method=squash
```

- [ ] **Step 6: Flip the gem ledger + clean up**

Update the gem's `COMPONENT_STATUS.md` (or a Lookbook ledger note) if it tracks catalog state, delete merged branches, and update memory `project_component_hardening_program` with the landing-page/grouping milestone.

---

## Self-review (against the spec)

- **Spec goal 1 (Overview page):** Tasks 3 (gem) + 5 (app). ✅
- **Spec goal 2 (8-section grouping):** Tasks 1–2 (gem) + 4 (app). ✅
- **Spec goal 3 (durable / gem-first):** Tasks structured gem→app; Task 7 choreography. ✅
- **Spec goal 4 (consistency guard):** `test_lookbook_logical_paths` (gem) + `logical_path_coverage_spec` (app). ✅
- **Spec taxonomy table (78/80):** encoded verbatim in both guards + both scripts; `wysiwyg`/`toaster` gem-only handled. ✅
- **Spec edge cases (stepper→Feedback, rating/rating_input split, command/chart/footer/aspect_ratio):** encoded in the maps. ✅
- **Spec open risk (`embed`):** resolved (page_helper.rb:27); `test_every_embed_target_exists` guards it. ✅
- **Spec success "axe AAA on page":** refined to embed-target + consistency + manual render check (see Test-strategy note); flagged in Task 7 Step for confirmation. ⚠️ (deliberate, surfaced)
- **Placeholder scan:** no TBD/TODO; every code step shows complete content. ✅
- **Type/name consistency:** `@logical_path` regex, `EXPECTED`/`expected` map keys, and section strings are identical across the gem test, app spec, and both scripts. ✅
