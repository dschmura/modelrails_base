# Lookbook Tier 3 Cycle 3 — Per-Preview Backgrounds (3d) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raised components show visible edges and page-chrome components render edge-to-edge in Lookbook, via per-preview `@display background:` tags consumed by the preview layout.

**Architecture:** The `component_preview.html.erb` layout (gem template + app copy, parity) maps `params.dig(:lookbook, :display, :background)` to body classes. Per-preview YARD `# @display background: <value>` tags set the value — Lookbook merges them into the preview iframe params (the same pipeline the theme toolbar uses). No global toolbar option. Static guards in both repos validate tag values.

**Spec:** `docs/superpowers/specs/2026-06-11-lookbook-tier3-completion-design.md` (Cycle 3) — amended by verified facts below.

---

## Verified facts (override the spec's guesses — do not re-investigate)

- **Tokens:** `--color-surface-raised` (white / neutral-800) and `--color-surface-sunken` (neutral-100 / neutral-950) exist in `app/assets/tailwind/tokens/_semantic.css` for both themes. **There is NO `bg-page` token** — `bg-surface` is the page-default background. Allowed background values are therefore: `raised` (default), `sunken`, `surface`, `bleed` (= `bg-surface` + no padding).
- **Surface reality:** dialog/sheet/popover/hover_card panels use `bg-surface-overlay` and open over scrims — they do NOT have the invisible-edge problem; the spec's "dialog/sheet sunken" guess is dropped. True raised containers to tag `sunken`: **card, data_table**. Page-chrome to tag `bleed`: **navbar, footer, banner, bottom_nav, mega_menu, sidebar, navigation_menu**. (Extending later = one comment line per preview; the browser check may add candidates.)
- **Branch stacking:** Cycle 3 edits preview files Cycle 2 also touched. App branch `feat/lookbook-tier3-cycle3` stacks on `feat/lookbook-tier3-cycle2`; gem branch `lookbook/preview-backgrounds` stacks on `lookbook/preview-enrichment`. PR bases = the cycle-2 branches if those PRs (#289 / gem #52) are still open at ship time, else `main` / `modelrails/harden`. Note merge order in PR bodies.
- 0b/AAA axe specs visit the VC preview host, which ignores `@display` — unaffected.
- Toolchain as Cycles 1–2 (gem: `bundle exec rake`; app: `mise exec --`; explicit staging only).

## File structure

- Layout (both): gem `lib/generators/modelrails_ui/lookbook/templates/component_preview.html.erb` · app `app/views/layouts/component_preview.html.erb` — identical change.
- Tags: 9 preview `.rb` files per repo (card, data_table → `sunken`; navbar, footer, banner, bottom_nav, mega_menu, sidebar, navigation_menu → `bleed`). Tag line goes directly ABOVE `# @logical_path` (after `## Related` where present).
- Guards: gem `test/test_lookbook_display_backgrounds.rb` (new) · app `spec/components/previews/ui/display_backgrounds_spec.rb` (new).

---

### Task 1: Gem — guard (red) → layout + tags (green) → rake → commit

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git switch -c lookbook/preview-backgrounds lookbook/preview-enrichment
```

- [ ] **Step 1: failing guard.** Create `test/test_lookbook_display_backgrounds.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# Per-preview `@display background:` tags drive the preview-layout body background
# (raised default · sunken · surface · bleed). Guard the vocabulary and require the
# two tagged families to exist (raised containers + page chrome).
class TestLookbookDisplayBackgrounds < Minitest::Test
  GEN_ROOT = File.expand_path("../lib/generators/modelrails_ui/lookbook/templates", __dir__)
  PREVIEW_ROOT = File.join(GEN_ROOT, "previews/ui")
  LAYOUT = File.join(GEN_ROOT, "component_preview.html.erb")
  ALLOWED = %w[sunken surface bleed].freeze

  def tags
    Dir.glob(File.join(PREVIEW_ROOT, "*_component_preview.rb")).to_h do |path|
      [File.basename(path, "_component_preview.rb"),
       File.read(path)[/^\s*#\s*@display background:\s*(\S+)/, 1]]
    end.compact
  end

  def test_background_values_are_in_vocabulary
    bad = tags.reject { |_c, v| ALLOWED.include?(v) }

    assert_empty bad, "unknown @display background values: #{bad.inspect} (allowed: #{ALLOWED.join(", ")})"
  end

  def test_tagged_families_exist
    refute_empty tags, "no @display background tags found"
    assert_includes tags.keys, "card", "card must opt into the sunken background"
    assert_includes tags.keys, "navbar", "navbar must opt into the bleed background"
  end

  def test_layout_consumes_the_background_param
    assert_match(/lookbook.*display.*background/m, File.read(LAYOUT),
      "component_preview layout must read params.dig(:lookbook, :display, :background)")
  end
end
```

Run `bundle exec ruby -Itest test/test_lookbook_display_backgrounds.rb` → 3 failures (no tags, layout doesn't consume). Clean red.

- [ ] **Step 2: layout.** In `templates/component_preview.html.erb`, replace the `<body class="bg-surface-raised text-text-body p-6">` line with:

```erb
  <%# Background is driven by a per-preview `@display background:` tag (sunken ·
      surface · bleed); default is the raised host surface. Raised containers (card,
      data_table) opt into `sunken` so their edges are visible; page chrome (navbar,
      footer, …) opts into `bleed` for edge-to-edge rendering. %>
  <body class="<%= {
        "sunken" => "bg-surface-sunken p-6",
        "surface" => "bg-surface p-6",
        "bleed" => "bg-surface p-0"
      }.fetch(params.dig(:lookbook, :display, :background), "bg-surface-raised p-6") %> text-text-body">
```

(Keep the existing theme comment that follows the body tag.)

- [ ] **Step 3: tags.** Add one line directly above `# @logical_path` in each of the 9 previews:
  - `card`, `data_table`: `# @display background: sunken`
  - `navbar`, `footer`, `banner`, `bottom_nav`, `mega_menu`, `sidebar`, `navigation_menu`: `# @display background: bleed`
- [ ] **Step 4:** `bundle exec rake` → 0 failures, 0 offenses (new guard green).
- [ ] **Step 5:** Commit (explicit paths: layout template + 9 previews + test). Message: `feat(lookbook): per-preview backgrounds — sunken containers, full-bleed chrome (Tier 3 Cycle 3)`.

### Task 2: App — mirror + guard + browser truth

```bash
cd /Users/dschmura/Documents/code/modelrails_base && git switch -c feat/lookbook-tier3-cycle3 feat/lookbook-tier3-cycle2
```

- [ ] **Step 1:** App guard `spec/components/previews/ui/display_backgrounds_spec.rb` — RSpec mirror of the gem test (preview_root `spec/components/previews/ui`, layout `app/views/layouts/component_preview.html.erb`; same three behaviors as loop-at-load examples). Red first.
- [ ] **Step 2:** Apply the identical layout change to `app/views/layouts/component_preview.html.erb` and the identical 9 tags (use the gem commit as the hunk source, as Cycle 2 did).
- [ ] **Step 3:** Guards + full suite green (`mise exec -- bundle exec rspec`).
- [ ] **Step 4 (render truth):** With the dev server, fetch a Lookbook **preview iframe** for a tagged and an untagged component and assert the body class actually switches — e.g. `Net::HTTP` against the card preview frame URL contains `bg-surface-sunken`, navbar's contains `p-0`, button's keeps `bg-surface-raised p-6`. (The Lookbook preview frame URL pattern: find via the inspector HTML's iframe src — it carries the display params.) If the param does NOT arrive (tag pipeline assumption fails), STOP — report with evidence; fallback design is a small Lookbook hook, needs a human decision.
- [ ] **Step 5:** Commit. Message as gem.

### Task 3: Ship the stacked pair

- [ ] App: WIP shuffle → push `feat/lookbook-tier3-cycle3` → PR (base = `feat/lookbook-tier3-cycle2` if #289 still open, else `main`); note "merge after Cycle 2".
- [ ] Gem: push `lookbook/preview-backgrounds` → PR (base = `lookbook/preview-enrichment` if #52 still open, else `modelrails/harden`); same note.
- [ ] Report URLs.

---

## Self-review

- Spec coverage: 3d fully (layout, tags, guards, no toolbar option, render-truth check). Spec's token/candidate guesses corrected by verified facts (documented above).
- No placeholders; all code complete; the one STOP-condition (param pipeline) is a genuine human-decision gate, with evidence required.
- Consistency: value vocabulary (`sunken|surface|bleed`) identical in layout map and both guards; tag placement rule deterministic.
