# SP1: Button API Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `UI::ButtonComponent` fail loud on an unknown `variant` in development/test (and fall back to `:primary` only in production), establishing the "boundary guardrail" convention on one component — proven in the app, then upstreamed to the gem template.

**Architecture:** Pilot the change in the app's vendored component first (full context + test suite), then port the identical code to the gem's `.rb.tt` template so future generations carry it. The dev-vs-prod decision uses `defined?(Rails) && Rails.env.production?` so the same code is correct in the app (Rails present) and the gem's Rails-less Minitest. No gem version bump or app regeneration is needed: the app is hardened directly; the gem template is aligned for future apps (broad cross-app propagation is SP4).

**Tech Stack:** Ruby, ViewComponent 4, RSpec + Capybara (app), Minitest (gem).

---

## File Structure

**App (`/Users/dschmura/Documents/code/modelrails_base`):**
- Modify: `app/components/ui/button_component.rb` — add variant validation in `initialize`.
- Test: `spec/components/ui/button_component_spec.rb` — add raise + prod-fallback specs.

**Gem (`/Users/dschmura/Documents/code/view_primitives`, branch `modelrails/harden`):**
- Modify: `lib/generators/modelrails_ui/add/templates/button/button_component.rb.tt` — same validation.
- Test: `test/test_components.rb` (`TestButtonComponent`) — add raise spec.

---

## Task 0: App branch setup

- [ ] **Step 1: Branch off main**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
git checkout main && git pull --prune
git checkout -b feat/ui-button-variant-hardening
```

---

## Task 1: App — failing spec for unknown-variant raise (RED)

**Files:**
- Test: `spec/components/ui/button_component_spec.rb`

- [ ] **Step 1: Add the failing test**

Add inside the existing `RSpec.describe UI::ButtonComponent, "app .btn-* parity", type: :component do ... end` block (before its final `end`):

```ruby
  it "raises ArgumentError on an unknown variant (fail-loud in dev/test)" do
    expect {
      described_class.new("Save", variant: :bogus)
    }.to raise_error(ArgumentError, /unknown variant :bogus/)
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mise exec -- bundle exec rspec spec/components/ui/button_component_spec.rb -e "unknown variant"`
Expected: FAIL — no error is raised (the component currently silently falls back via `VARIANTS.fetch(@variant, VARIANTS[:primary])`), so RSpec reports "expected ArgumentError but nothing was raised".

---

## Task 2: App — implement the variant guard (GREEN)

**Files:**
- Modify: `app/components/ui/button_component.rb`

- [ ] **Step 1: Coerce/validate the variant in `initialize`**

Change the variant assignment line in `initialize` from:

```ruby
      @variant = variant.to_sym
```

to:

```ruby
      @variant = coerce_variant(variant.to_sym)
```

- [ ] **Step 2: Add the private `coerce_variant` helper**

In the `private` section (e.g., directly above `def component_classes`), add:

```ruby
    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :primary in production so a bad variant never
    # 500s a page. `defined?(Rails)` keeps this correct in the gem's Rails-less tests.
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.env.production?
        raise ArgumentError,
          "UI::ButtonComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :primary
    end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `mise exec -- bundle exec rspec spec/components/ui/button_component_spec.rb -e "unknown variant"`
Expected: PASS (1 example, 0 failures). Ignore any `SimpleCov ... below minimum coverage` line — that is the 40% floor tripping on a single-file run, not a test failure.

---

## Task 3: App — production-fallback spec (RED → GREEN, code already present)

**Files:**
- Test: `spec/components/ui/button_component_spec.rb`

- [ ] **Step 1: Add the fallback test**

Add inside the same describe block:

```ruby
  it "falls back to :primary in production instead of raising" do
    allow(Rails.env).to receive(:production?).and_return(true)
    render_inline(described_class.new("Save", variant: :bogus))
    expect(page.find("button")[:class]).to include("bg-interactive") # primary styling
  end
```

- [ ] **Step 2: Run it**

Run: `mise exec -- bundle exec rspec spec/components/ui/button_component_spec.rb -e "falls back to :primary"`
Expected: PASS — with `production?` stubbed true, `coerce_variant` returns `:primary` and the rendered button carries primary's `bg-interactive` class.

- [ ] **Step 3: Run the whole button spec to confirm no regressions**

Run: `mise exec -- bundle exec rspec spec/components/ui/button_component_spec.rb`
Expected: 7 examples, 0 failures (5 original parity examples + the 2 new ones).

---

## Task 4: App — full suite + commit

- [ ] **Step 1: Run the component specs (no coverage-floor noise)**

Run: `mise exec -- bundle exec rspec spec/components/ui/`
Expected: 22 examples, 0 failures (20 prior + 2 new).

- [ ] **Step 2: Run the full suite**

Run: `mise exec -- bundle exec rspec`
Expected: 2138 examples, 0 failures (2136 baseline + 2 new). Coverage ~94%.

- [ ] **Step 3: Commit**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
git add app/components/ui/button_component.rb spec/components/ui/button_component_spec.rb
git commit -m "feat(ui): UI::ButtonComponent raises on unknown variant (dev), falls back in prod

Boundary guardrail: an unknown variant now fails loud in development/test instead
of silently rendering primary, so misuse is caught at the call site. Production
keeps the safe :primary fallback so a bad variant never 500s a page."
```

---

## Task 5: Gem — failing Minitest for unknown-variant raise (RED)

**Files:**
- Test: `/Users/dschmura/Documents/code/view_primitives/test/test_components.rb`

- [ ] **Step 1: Confirm you are on the harden branch**

```bash
cd /Users/dschmura/Documents/code/view_primitives
git branch --show-current   # expect: modelrails/harden
```

- [ ] **Step 2: Add the failing test**

Inside `class TestButtonComponent < Minitest::Test` (before its closing `end`), add:

```ruby
  def test_unknown_variant_raises
    assert_raises(ArgumentError) { UI::ButtonComponent.new("Save", variant: :bogus) }
  end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mise exec -- bundle exec rake test TEST=test/test_components.rb`
(If `mise exec` does not pick up Ruby here, prefix instead: `PATH="/Users/dschmura/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rake test TEST=test/test_components.rb`.)
Expected: FAIL — `TestButtonComponent#test_unknown_variant_raises` reports "ArgumentError expected but nothing was raised" (the template still silently falls back).

---

## Task 6: Gem — port the guard to the template (GREEN)

**Files:**
- Modify: `/Users/dschmura/Documents/code/view_primitives/lib/generators/modelrails_ui/add/templates/button/button_component.rb.tt`

- [ ] **Step 1: Apply the identical change**

In the template, change:

```ruby
      @variant = variant.to_sym
```

to:

```ruby
      @variant = coerce_variant(variant.to_sym)
```

and add, in the `private` section above `def component_classes`:

```ruby
    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :primary in production so a bad variant never
    # 500s a page. `defined?(Rails)` keeps this correct in the gem's Rails-less tests.
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.env.production?
        raise ArgumentError,
          "UI::ButtonComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :primary
    end
```

- [ ] **Step 2: Run the gem test to verify it passes**

Run: `mise exec -- bundle exec rake test TEST=test/test_components.rb`
Expected: PASS — `test_unknown_variant_raises` green; all other `TestButtonComponent` tests still pass (they use valid/default variants).

- [ ] **Step 3: Run the gem's default task (full suite + rubocop)**

Run: `mise exec -- bundle exec rake`
Expected: all tests green, RuboCop clean. (If RuboCop flags the new method, run `mise exec -- bundle exec rubocop -A lib/generators/modelrails_ui/add/templates/button/button_component.rb.tt` and re-run.)

---

## Task 7: Gem — commit

- [ ] **Step 1: Commit on the harden branch**

```bash
cd /Users/dschmura/Documents/code/view_primitives
git add lib/generators/modelrails_ui/add/templates/button/button_component.rb.tt test/test_components.rb
git commit -m "feat: ButtonComponent raises on unknown variant (dev), falls back in prod

Mirror of the app pilot: the generated component now validates variant at the
boundary. defined?(Rails) keeps it correct in the gem's Rails-less Minitest."
```

---

## Task 8: Parity check (app vendored == gem template)

- [ ] **Step 1: Diff the two files — the guard must be identical**

```bash
diff /Users/dschmura/Documents/code/modelrails_base/app/components/ui/button_component.rb \
     /Users/dschmura/Documents/code/view_primitives/lib/generators/modelrails_ui/add/templates/button/button_component.rb.tt
```

Expected: no differences (the button component template and the vendored component are byte-identical, as they were before this change — only the shared guard was added to both). If they differ, reconcile so the vendored file and the template match.

---

## Self-Review

**Spec coverage (against the design doc's SP1):** "Harden UI::ButtonComponent (validate variant, dev-raise/prod-fallback) + regenerate into the app + add hardening specs." → Task 2 (guard), Tasks 1/3 (app specs), Tasks 5–6 (gem template + test), Task 8 (parity in lieu of regeneration, since the app is hardened directly). Covered.

**Placeholder scan:** No TBD/TODO; every code/command step shows actual content. Clear.

**Type/signature consistency:** `coerce_variant(variant)` defined once and called identically in app (Task 2) and gem template (Task 6); `VARIANTS` (existing constant) is the single source of valid keys in both. Consistent.

**Scope:** One component, one guardrail, two repos — self-contained and testable on its own. Good.
