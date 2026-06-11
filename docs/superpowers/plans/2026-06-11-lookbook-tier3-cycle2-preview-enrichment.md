# Lookbook Tier 3 Cycle 2 — Preview Enrichment (3b + 3c + 3e) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five form-control playgrounds with ARIA-rewire smoke coverage (3b), the `## Related` relationship graph encoded and guarded (3c), and full doc structure on the four thin nav-band previews (3e) — gem-first, app synced.

**Architecture:** All edits target preview files that exist in BOTH repos (gem generator templates are the source; app copies are vendored). Gem first: edit templates + add a gem Minitest guard, `bundle exec rake` green. Then app: apply the identical edits to the vendored copies, add the mirrored RSpec guard + smoke-spec extensions, full suite green. One PR pair.

**Tech Stack:** Lookbook `@param` playgrounds, YARD `@!group` scenario grouping (canonical order enforced by existing guards in both repos), static source-analysis guards.

**Spec:** `docs/superpowers/specs/2026-06-11-lookbook-tier3-completion-design.md` (Cycle 2)

---

## Pre-flight facts (verified — do not re-investigate)

- Playground idiom exemplar: `toggle_component_preview.rb` — `@!group Reference`, `@param x text|toggle|select [..]`, inline `def playground(...)` calling `ui :toggle, …`. Playgrounds are exempt from the template-backed test; `spec/system/ui/playground_smoke_spec.rb` is their only automated coverage.
- Grouping states of the 3b targets: `input`, `checkbox`, `radio_group` already have `@!group Examples` / `@!group Reference` (each with one `dont_*` in Reference — the playground must be inserted in Reference **before** the `dont_*`, per the canonical-order guards: playground rank 2 < dont rank 3). `form_field` and `range` are **flat** — adding a playground makes them "meta" and the grouping guards then REQUIRE the full `@!group Examples … @!endgroup … @!group Reference … @!endgroup` structure with labels exactly `["Examples", "Reference"]`.
- Component call shapes (from their own scenario templates): `ui :input, type:, name:, placeholder:, required:, invalid:, disabled:, describedby:` · `ui :checkbox, label:, name:, checked:, invalid:, disabled:, describedby:` · `ui :radio_group, name:, label:, items: [{value:,label:,checked:}], invalid:, describedby:` · `ui :range, id:, name:, min:, max:, step:, value:, show_value:, invalid:, disabled:` (arbitrary html attrs pass through) · `ui :form_field, label:, hint:, error:, required:, id:` yielding `f` with `f.input_attrs` for the control (slot block).
- `form_field`'s playground needs a slot block inline — **mirror the existing `sheet_component_preview.rb` playground idiom** (it already solved slots-in-a-playground). If sheet uses `render_with_template(locals: …)`, do the same with a `playground.html.erb`.
- 3e targets and their CURRENT thin headers: `breadcrumb` (1-line desc), `tabs` (2 lines), `navbar` (3 lines), `menubar` (2 lines; note: `@logical_path Overlays`, not Navigation — leave the tag untouched).
- 3c placement rule: the `## Related` block is the LAST doc section, inserted immediately before the `# @logical_path` line. Format: `# ## Related` + one comment line of backticked names separated by ` · `.
- Repos/branches: gem `/Users/dschmura/Documents/code/modelrails_ui` — branch `lookbook/preview-enrichment` off `modelrails/harden`; app branch `feat/lookbook-tier3-cycle2` off `origin/main`. File-disjoint from Cycle 1 (pages vs previews), so no merge dependency.
- Toolchain: gem `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rake` (bare `rake` crashes on a pre-existing standard↔rubocop conflict — use the CI form). App `mise exec -- bundle exec …`. Never `git add -A`; gem has dirty `MODELRAILS_STATUS.md` — never stage it.
- ViewComponent's preview host forwards query params to preview method kwargs (`…/playground?required=true`). The smoke-spec ARIA assertions rely on this; **verify with one curl/visit first** — if params do NOT forward, keep the render-smoke assertions and drop only the param-driven ones, noting it in the commit message.

## The Related graph (definitive — same in both repos)

| Component | Related line (backticked, ` · `-separated) |
|---|---|
| form_field | input · label · textarea · select · checkbox · radio_group |
| input | form_field · label · textarea · search_input · floating_label |
| textarea | form_field · input |
| label | form_field · input · select |
| select | combobox · radio_group · label |
| combobox | select · command |
| checkbox | switch · radio_group · toggle |
| radio_group | select · checkbox |
| switch | checkbox · toggle |
| toggle | switch · checkbox · toggle_group |
| toggle_group | toggle |
| dropdown_menu | context_menu · menubar |
| context_menu | dropdown_menu · menubar |
| menubar | dropdown_menu · context_menu |
| popover | tooltip · hover_card |
| tooltip | popover · hover_card |
| hover_card | popover · tooltip |
| dialog | alert_dialog · drawer · sheet |
| alert_dialog | dialog |
| drawer | sheet · dialog |
| sheet | drawer · dialog |
| gallery | dialog · image · carousel |
| card | list_group · avatar · badge |
| rating | rating_input |
| rating_input | rating |
| date_picker | calendar · timepicker |
| calendar | date_picker |
| timepicker | date_picker |

(28 files. Components not listed get NO Related section — the guard only validates files that have one.)

---

### Task 1: Gem — guards first (red), then all preview edits (green)

**Work from `/Users/dschmura/Documents/code/modelrails_ui`:**

```bash
git switch -c lookbook/preview-enrichment modelrails/harden
```

- [ ] **Step 1: Write the Related guard (failing only after content lands — it skips files without a Related block, so write it plus ONE seed edit to prove red).** Create `test/test_lookbook_related_links.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# `## Related` doc-comment sections encode the sibling-relationship graph. Every
# backticked name inside one must be a real component preview — typo/drift protection,
# same static-analysis idiom as the other lookbook guards.
class TestLookbookRelatedLinks < Minitest::Test
  PREVIEW_ROOT = File.expand_path(
    "../lib/generators/modelrails_ui/lookbook/templates/previews/ui", __dir__
  )

  def test_every_related_target_is_a_real_component
    names = Dir.glob(File.join(PREVIEW_ROOT, "*_component_preview.rb"))
      .map { |p| File.basename(p, "_component_preview.rb") }
    found_any = false

    Dir.glob(File.join(PREVIEW_ROOT, "*_component_preview.rb")).sort.each do |path|
      lines = File.read(path).lines
      idx = lines.index { |l| l.match?(/^\s*#\s*## Related\s*$/) }
      next unless idx

      found_any = true
      block = lines[(idx + 1)..].take_while { |l| l.match?(/^\s*#/) && !l.match?(/^\s*#\s*(##|@)/) }.join
      targets = block.scan(/`([a-z_]+)`/).flatten.uniq

      refute_empty targets, "#{path}: empty ## Related section"
      missing = targets - names

      assert_empty missing, "#{File.basename(path)} Related references unknown: #{missing.join(", ")}"
    end

    assert found_any, "no ## Related sections found — the cross-link graph is missing"
  end
end
```

Run `bundle exec ruby -Itest test/test_lookbook_related_links.rb` → FAILS on `found_any` (no Related sections exist yet). Clean red.

- [ ] **Step 2 (3c): Add the `## Related` blocks** to all 28 gem template previews per the graph table above. Placement: last doc section, immediately before the `# @logical_path` line. Exact format per file (example for `form_field`):

```ruby
  # ## Related
  # `input` · `label` · `textarea` · `select` · `checkbox` · `radio_group`
  # @logical_path Forms & Inputs
```

- [ ] **Step 3 (3e): Replace the four thin headers** in `templates/previews/ui/{breadcrumb,tabs,navbar,menubar}_component_preview.rb`. The blocks below are drafts sourced from the components' implementations — **before writing each, read the component template (`lib/components/ui/…` or wherever the gem's component lives — find with `grep -r "class BreadcrumbComponent" lib/`) and the existing description, and correct any claim that doesn't match the code.** Keep each file's existing description sentence(s) as the opening, keep `@logical_path` untouched, and add Related lines per the graph (breadcrumb/tabs/navbar are not in the graph table — they get NO Related section).

`breadcrumb` (after the existing description line):

```ruby
  # ## Use when
  # - Showing where the current page sits in a hierarchy, with links back up the trail.
  #
  # ## Don't use when
  # - You're switching between in-page panels — use `tabs`.
  # - It's the site's primary navigation — use `navbar`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark wrapping an ordered list; the last item
  #   is the current page — `aria-current="page"`, rendered as text, not a link.
  # - **You supply:** the trail items (label + href); the final item's label.
```

`tabs`:

```ruby
  # ## Use when
  # - Switching between a few in-page panels where one is visible at a time.
  #
  # ## Don't use when
  # - The destinations are different pages — use `navbar` or plain links.
  # - You need a hierarchy trail — use `breadcrumb`.
  #
  # ## Accessibility contract
  # - **Guarantees:** APG tabs with automatic activation — `role="tablist"/"tab"/"tabpanel"`
  #   wiring, roving tabindex (one Tab stop), ←/→ moves + reveals, Home/End jumps,
  #   disabled tabs are skipped, `aria-selected` stays in sync.
  # - **You supply:** tab labels and panel content.
```

`navbar`:

```ruby
  # ## Use when
  # - The site's primary top navigation, responsive out of the box.
  #
  # ## Don't use when
  # - You need a collapsible application rail — use `sidebar`.
  # - The links belong at the bottom on mobile — use `bottom_nav`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark; on narrow viewports the links collapse
  #   behind a hamburger disclosure (`aria-expanded`/`aria-controls`, Escape and
  #   outside-click close, focus returns to the trigger).
  # - **You supply:** the brand slot and the link items.
```

`menubar`:

```ruby
  # ## Use when
  # - A persistent application menu bar (File / Edit / View) exposing grouped commands.
  #
  # ## Don't use when
  # - Actions launch from a single button — use `dropdown_menu`.
  # - Actions open from right-click on a region — use `context_menu`.
  #
  # ## Accessibility contract
  # - **Guarantees:** WAI-ARIA APG menubar — one Tab stop, roving tabindex, ←/→ moves
  #   between top-level items (following an open submenu), ↓/Enter opens a submenu
  #   (the shared `menu` controller: ↑/↓, type-ahead, Escape closes and restores focus).
  # - **You supply:** `label:` (required — the bar's accessible name) and the items.
```

(menubar/dropdown_menu/context_menu Related lines come from the graph table — menubar's goes after its contract, before `@logical_path Overlays`.)

- [ ] **Step 4 (3b): Add the five playgrounds.** Insert each into the file's `@!group Reference` BEFORE any `dont_*` method; for the flat files (`form_field`, `range`) first add `# @!group Examples` after `include UIHelper` and `# @!endgroup` after the last existing scenario, then the Reference group. Exact code:

`input_component_preview.rb` (in Reference, before `dont_raw_input`):

```ruby
    # Flip `required` / `invalid` / `disabled` and watch the attributes rewire
    # (`required`, `aria-invalid`) live.
    # @param placeholder text
    # @param required toggle
    # @param invalid toggle
    # @param disabled toggle
    def playground(placeholder: "you@example.com", required: false, invalid: false, disabled: false)
      ui :input, type: "email", name: "pg_email", placeholder: placeholder,
        required: required, invalid: invalid, disabled: disabled
    end
```

`checkbox_component_preview.rb` (in Reference, before `dont_no_label`):

```ruby
    # Flip the states and watch `checked` / `aria-invalid` / `disabled` rewire live.
    # @param label text
    # @param checked toggle
    # @param invalid toggle
    # @param disabled toggle
    def playground(label: "Accept the terms", checked: false, invalid: false, disabled: false)
      ui :checkbox, label: label, name: "pg_terms", checked: checked,
        invalid: invalid, disabled: disabled
    end
```

`radio_group_component_preview.rb` (in Reference, before `dont_no_group_label`):

```ruby
    # Flip `invalid` and watch the group's `aria-invalid` rewire live.
    # @param label text
    # @param invalid toggle
    def playground(label: "Billing plan", invalid: false)
      ui :radio_group, name: "pg_plan", label: label, invalid: invalid,
        items: [{ value: "free", label: "Free" }, { value: "pro", label: "Pro" }]
    end
```

`range_component_preview.rb` (flat → full group structure; playground in the new Reference group):

```ruby
    # Drag the value and flip `show_value` / `invalid` / `disabled`; the `<output>`
    # readout and `aria-invalid` rewire live. (The slider's accessible name comes from
    # `aria-label` here — real callers supply an external `<label for>`.)
    # @param value select [0, 25, 50, 75, 100]
    # @param show_value toggle
    # @param invalid toggle
    # @param disabled toggle
    def playground(value: 50, show_value: true, invalid: false, disabled: false)
      ui :range, id: "pg_volume", name: "pg_volume", min: 0, max: 100, step: 1,
        value: value.to_i, show_value: show_value, invalid: invalid,
        disabled: disabled, "aria-label": "Volume"
    end
```

`form_field_component_preview.rb` (flat → full group structure; slot block — mirror the `sheet` playground idiom; if sheet renders inline with a block, use):

```ruby
    # The teaching playground: flip `required`, set/clear `hint` and `error`, and watch
    # the ARIA rewire — hint/error get real ids referenced by the control's
    # `aria-describedby`; an error also sets `aria-invalid`; required adds the
    # decorative `*` and the control's `required`.
    # @param label text
    # @param hint text
    # @param error text
    # @param required toggle
    def playground(label: "Email", hint: "We'll never share it.", error: "", required: false)
      ui :form_field, label: label, hint: hint.presence, error: error.presence,
        required: required, id: "pg_email" do |f|
        ui :input, type: "email", name: "email", **f.input_attrs
      end
    end
```

(If the inline block form doesn't render the slot content — check how `sheet`'s playground does it — switch to `render_with_template(locals: { label:, hint:, error:, required: })` with a `form_field_component_preview/playground.html.erb` template using the same call.)

- [ ] **Step 5: Gem CI green.** `bundle exec rake` → 0 failures (the grouping guard validates the new group structures; the Related guard goes green; template-backed test exempts playgrounds), 0 RuboCop offenses.
- [ ] **Step 6: Commit** (explicit paths only: the edited previews + the new test). Message: `feat(lookbook): form-control playgrounds, Related cross-links, nav-band doc contracts (Tier 3 Cycle 2)`.

---

### Task 2: App — identical preview edits + guards + smoke coverage

**Work from `/Users/dschmura/Documents/code/modelrails_base`:**

```bash
git switch -c feat/lookbook-tier3-cycle2 origin/main
```

- [ ] **Step 1:** Create `spec/components/previews/ui/related_links_spec.rb` — RSpec mirror of the gem guard (same line-walk logic; `preview_root = Rails.root.join("spec/components/previews/ui")`; one `it` per file with a Related block via the loop-at-load idiom, plus a final `it "encodes the relationship graph"` asserting at least one Related section exists). Run → red (`found_any`-equivalent fails).
- [ ] **Step 2:** Apply the IDENTICAL preview edits from Task 1 Steps 2–4 to the app's vendored copies in `spec/components/previews/ui/` (same 28 Related blocks, same 4 doc-structure replacements, same 5 playgrounds). Semantic parity: if app RuboCop wants different wrapping, let it — content identical.
- [ ] **Step 3:** Extend `spec/system/ui/playground_smoke_spec.rb` with:

```ruby
  it "input playground renders and rewires ARIA from params" do
    visit "/rails/view_components/ui/input_component/playground?required=true&invalid=true"
    expect(page).to have_css('input[aria-invalid="true"][required]', visible: :all)
  end

  it "checkbox playground renders" do
    visit "/rails/view_components/ui/checkbox_component/playground?invalid=true"
    expect(page).to have_css('input[type="checkbox"][aria-invalid="true"]', visible: :all)
  end

  it "radio_group playground renders" do
    visit "/rails/view_components/ui/radio_group_component/playground?invalid=true"
    expect(page).to have_css('[role="radiogroup"][aria-invalid="true"]', visible: :all)
  end

  it "range playground renders with a live readout" do
    visit "/rails/view_components/ui/range_component/playground"
    expect(page).to have_css('input[type="range"]', visible: :all)
    expect(page).to have_css("output", visible: :all)
  end

  it "form_field playground rewires describedby/invalid from params" do
    visit "/rails/view_components/ui/form_field_component/playground?error=Required&required=true"
    expect(page).to have_css('input[aria-invalid="true"][aria-describedby*="error"]', visible: :all)
  end
```

**First** verify param forwarding with the input case alone; if the VC preview host does NOT forward query params to kwargs, replace the param-driven selectors with default-render assertions (`have_css('input[type="email"]')` etc.) and note the limitation in the commit message.

- [ ] **Step 4:** Guards green: `mise exec -- bundle exec rspec spec/components/previews/ui/related_links_spec.rb spec/components/previews/ui/scenario_grouping_spec.rb spec/system/ui/playground_smoke_spec.rb` → 0 failures (grouping guard validates the new structures).
- [ ] **Step 5:** Full suite: `mise exec -- bundle exec rspec` → 0 failures.
- [ ] **Step 6:** Browser check (server on :3000): each of the five playgrounds renders under `/lookbook` (`…/ui/<name>/playground` inspector) with its `@param` controls; the four nav-band previews show the new doc sections; spot-check light + dark.
- [ ] **Step 7:** Commit (explicit paths: edited previews + new spec + smoke spec). Same message as gem.

---

### Task 3: Ship the pair

- [ ] App: move `docs/component-standards` aside → push `feat/lookbook-tier3-cycle2` (Lefthook full CI) → restore → `gh pr create --base main` (title `feat(lookbook): playgrounds + Related graph + nav-band contracts (Tier 3 Cycle 2)`).
- [ ] Gem: push `lookbook/preview-enrichment` → `gh pr create --base modelrails/harden`.
- [ ] Report both URLs; user merges on green.

---

## Self-Review (planning time)

- **Spec coverage:** 3b (Task 1 Step 4 + Task 2 Steps 2–3, ARIA assertions), 3c (Steps 2/1 + guards both repos), 3e (Step 3 with verify-against-code rule). Gem-first ✓. Smoke-spec ARIA-rewire requirement ✓ with documented fallback.
- **Placeholders:** none — full code for guards, playgrounds, doc blocks (drafts carry an explicit verify-by-reading rule, mirroring the proven gem-only-rows approach).
- **Consistency:** group-insertion rules match the existing grouping guards' ranks; the Related placement rule (`before @logical_path`) is deterministic; graph table = single source for both repos.
