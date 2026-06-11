# Lookbook "Choosing an overlay" Decision Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one Lookbook Page that routes a developer to the right Overlays sibling (modal surfaces / floating / menus), guarded by a static drift spec.

**Architecture:** A markdown `.md.erb` Lookbook Page under a new `pages/choosing/` subdirectory (Lookbook recurses it into a "Choosing" nav group), built from the proven `00_overview.md.erb` pattern — reach-for-it-when tables + one live `<%= embed %>` per fork. A static RSpec guard (same idiom as `logical_path_coverage_spec.rb`) asserts every Overlays sibling is routed and every embed resolves.

**Tech Stack:** Lookbook 2.3.14 Pages (`config.lookbook.page_paths` already set), ViewComponent previews, RSpec static-source guards.

---

## Pre-flight facts (verified during planning — do not re-investigate)

- **Subdir → nav group is confirmed.** `lookbook-2.3.14` `page_collection.rb:49` globs `#{dir}/**/*.md.*` (recursive) and `page_entity.rb:19` derives `lookup_path` from the relative file path, split on `/` for the nav tree. So `pages/choosing/00_overlays.md.erb` nests under a **"Choosing"** group. No config change. (Flat fallback `pages/10_choosing_overlays.md.erb` exists only if Task 3 visual check somehow disproves this — not expected.)
- **The page file is NOT markdown-linted.** `rake markdown:check` runs `markdownlint '**/*.md'`; the file ends in `.md.erb` (extension `.erb`), so the glob misses it (as it does the existing `00_overview.md.erb`). No lint step for the page.
- **Embed scenarios confirmed present:** `UI::DialogComponentPreview` `:basic`, `UI::PopoverComponentPreview` `:basic`, `UI::DropdownMenuComponentPreview` `:basic`.
- **Toolchain:** prefix Ruby with `mise exec --` (matches Lefthook), e.g. `mise exec -- bundle exec rspec …`.
- **Project rule overrides TDD commit timing:** run the FULL suite green before any commit (no red commits). So: write test → see red (no commit) → implement → see green → full suite → commit both files together.

## File Structure

- **Create** `spec/components/previews/pages/choosing/00_overlays.md.erb` — the decision page (content + 3 embeds). One responsibility: route overlay choice.
- **Create** `spec/components/previews/pages/choosing_overlays_spec.rb` — static drift guard. One responsibility: prove coverage + embed validity.
- No other files. No config change. No component-preview change. App-only (no gem PR).

---

### Task 1: Static drift guard (the failing test)

**Files:**
- Create test: `spec/components/previews/pages/choosing_overlays_spec.rb`

- [ ] **Step 1: Write the guard spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

# Guards the Overlays decision page (the exemplar "choosing" Lookbook Page).
# Static source analysis only — same idiom as logical_path_coverage_spec.rb and
# scenario_grouping_spec.rb (read files, scan, assert; no render).
RSpec.describe "Choosing an overlay decision page" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  page_path = Rails.root.join("spec/components/previews/pages/choosing/00_overlays.md.erb")
  source = File.exist?(page_path) ? File.read(page_path) : ""

  # Source of truth for the Overlays sibling set: the @logical_path Overlays previews.
  overlays = Dir.glob(preview_root.join("*_component_preview.rb")).select do |path|
    File.read(path).match?(/^\s*#\s*@logical_path\s+Overlays\s*$/)
  end.map { |path| File.basename(path, "_component_preview.rb") }.sort

  it "routes every Overlays sibling" do
    expect(overlays).not_to be_empty
    missing = overlays.reject { |name| source.include?(name) }
    expect(missing).to be_empty, "decision page is missing: #{missing.join(", ")}"
  end

  embeds = source.scan(/embed\s+(UI::\w+ComponentPreview),\s*:(\w+)/)

  it "embeds at least one live scenario" do
    expect(embeds).not_to be_empty
  end

  embeds.each do |class_name, scenario|
    it "embed #{class_name} :#{scenario} resolves to a real scenario" do
      file = class_name.sub(/\AUI::/, "").sub(/ComponentPreview\z/, "").underscore
      preview_file = preview_root.join("#{file}_component_preview.rb")
      expect(File).to exist(preview_file), "no preview file for #{class_name}"
      expect(File.read(preview_file)).to match(/^\s*def #{scenario}\b/),
        "#{class_name} has no `def #{scenario}`"
    end
  end
end
```

- [ ] **Step 2: Run the guard, confirm it FAILS (clean red)**

Run: `mise exec -- bundle exec rspec spec/components/previews/pages/choosing_overlays_spec.rb`
Expected: FAIL — "routes every Overlays sibling" reports `missing: alert_dialog, context_menu, dialog, drawer, dropdown_menu, hover_card, menubar, popover, sheet, tooltip` (page absent → `source` is `""`), and "embeds at least one live scenario" fails (no embeds). No load error (the `File.exist?` guard prevents it).

- [ ] **Step 3: Confirm the guard is rubocop-clean**

Run: `mise exec -- bundle exec rubocop spec/components/previews/pages/choosing_overlays_spec.rb`
Expected: no offenses. (If `Layout/LineLength` flags the `match` message line, wrap per the offense — do not disable the cop.)

Do **not** commit yet — the suite is red by design.

---

### Task 2: The decision page (makes the guard green)

**Files:**
- Create: `spec/components/previews/pages/choosing/00_overlays.md.erb`

- [ ] **Step 1: Create the page**

Every row below is sourced from the target component's own documented purpose (Wave-4 modal family: `## Use when` blocks; Waves 5–6 floating/menu families: title description + a11y contract). Write exactly:

```erb
---
label: Overlays
---

# Choosing an overlay

Overlays differ on three axes: whether they **block the page** with a scrim, how they're
**triggered**, and whether they **carry actions**. Start with the fork that matches your need —
each component is one sidebar click from its full preview.

## Modal surfaces — block the page with a scrim

| Component      | Reach for it when                                                    | Otherwise →        |
|----------------|----------------------------------------------------------------------|--------------------|
| `dialog`       | a focused task (form, detail, confirm) needs a focus-trapped modal    | `drawer` / `sheet` |
| `alert_dialog` | a destructive or irreversible action must be confirmed before it runs | `dialog`           |
| `sheet`        | a side panel — navigation, filters, a secondary form — slides in from an edge | `drawer`   |
| `drawer`       | a mobile-friendly bottom sheet of secondary actions slides up         | `sheet`            |

<%= embed UI::DialogComponentPreview, :basic %>

## Floating — anchored to a trigger, no scrim

| Component    | Reach for it when                                                          | Otherwise →            |
|--------------|----------------------------------------------------------------------------|------------------------|
| `popover`    | interactive content sits in a panel anchored to a trigger button (click toggles) | `tooltip` / `hover_card` |
| `hover_card` | a rich preview enhances a link on hover or focus (not the only path to it)  | `popover`              |
| `tooltip`    | a short text hint describes an element on hover or focus                    | `hover_card`           |

<%= embed UI::PopoverComponentPreview, :basic %>

## Menus — a list of commands

| Component       | Reach for it when                                                     | Otherwise →     |
|-----------------|----------------------------------------------------------------------|-----------------|
| `dropdown_menu` | actions launch from a button trigger (the WAI-ARIA menu-button)       | `context_menu`  |
| `context_menu`  | actions open from a right-click / long-press / Shift+F10 on a region  | `dropdown_menu` |
| `menubar`       | a persistent app menu bar (File / Edit / View) exposes grouped commands | `dropdown_menu` |

<%= embed UI::DropdownMenuComponentPreview, :basic %>
```

- [ ] **Step 2: Run the guard, confirm it PASSES**

Run: `mise exec -- bundle exec rspec spec/components/previews/pages/choosing_overlays_spec.rb`
Expected: PASS — all examples green ("routes every Overlays sibling", "embeds at least one live scenario", and 3 × "embed … resolves").

- [ ] **Step 3: Run the full suite (green before commit)**

Run: `mise exec -- bundle exec rspec`
Expected: 0 failures. (AAA axe is CI-only; locally this runs AA, which is fine — no new component or contrast was introduced, only catalog content.)

- [ ] **Step 4: Commit both files together**

```bash
git add spec/components/previews/pages/choosing/00_overlays.md.erb \
        spec/components/previews/pages/choosing_overlays_spec.rb
git commit -m "feat(lookbook): 'Choosing an overlay' decision page + drift guard (Tier 3, 3a)"
```

---

### Task 3: Manual visual verification (not automated)

Honors the design-system house rule ("check both themes" before calling UI work done) and empirically confirms the subdir-group behavior.

- [ ] **Step 1: Boot the dev server**

Run: `mise exec -- bin/rails server` (or the project's usual `bin/dev`).

- [ ] **Step 2: Open the page and verify**

Navigate to `http://localhost:3000/lookbook` → Pages. Confirm:
- A **"Choosing"** group appears in the Pages sidebar (beneath **Overview**), containing **Overlays**.
- The page renders three sections; each table is intact and each of the three `embed`s renders a **live** component (a real Dialog / Popover / Dropdown menu trigger, not an error).
- Toggle the Lookbook theme (light **and** dark): tables and embedded components render correctly in both.

- [ ] **Step 3: If the "Choosing" group does NOT appear (unexpected)**

Fallback only: rename to `spec/components/previews/pages/10_choosing_overlays.md.erb`, set frontmatter `label: Choosing: Overlays`, update the `page_path` in the guard spec, re-run Task 2 Step 2–4. (Pre-flight gem-source analysis says this won't be needed.)

---

## Ship (after Task 3 passes)

- [ ] Move the untracked WIP aside so the Lefthook `markdown_lint` push gate (which lints `**/*.md` including untracked working-dir files) doesn't fail: `mv docs/component-standards /tmp/component-standards-wip` (restore after push). Do **not** `git add -A` (leave `config/credentials/`, `db/development.sqlite3` untracked).
- [ ] Push the branch `docs/lookbook-choosing-overlays` (Lefthook pre-push runs full CI locally — never `LEFTHOOK=0`).
- [ ] `mv /tmp/component-standards-wip docs/component-standards` to restore the WIP.
- [ ] Open the PR against `main`. App-only — no `modelrails/harden` gem PR this cycle.

---

## Self-Review (completed during planning)

- **Spec coverage:** ✅ File & nav structure → Task 2. Page content (3 forks, sourced rows, `:basic` embeds) → Task 2 Step 1. Sourcing rule → row copy in Task 2. Static guard (coverage + embed validity) → Task 1. Scope boundaries (app-only, no gem PR, no component change) → File Structure + Ship. Subdir-group verify item → resolved in Pre-flight + Task 3. Guard placement item → resolved (`pages/choosing_overlays_spec.rb`). Copy reconciliation item → resolved (rows sourced from real doc-comments).
- **Placeholder scan:** ✅ No TBD/TODO; the only conditional ("fallback") is a fully-specified contingency, not a gap. All code blocks complete.
- **Type/name consistency:** ✅ `page_path` points at `pages/choosing/00_overlays.md.erb` in both the guard and Task 2. Embed class names (`UI::DialogComponentPreview` / `UI::PopoverComponentPreview` / `UI::DropdownMenuComponentPreview`) and scenario (`:basic`) match between page and guard's derivation regex. Overlays set (10) derived dynamically, not hardcoded — can't drift.
