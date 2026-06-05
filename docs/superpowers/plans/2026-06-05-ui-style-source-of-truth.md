# UI style source-of-truth reconciliation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `.btn-*` / `.form-field` / `.form-input` / `.form-file` CSS classes the single source of truth for button/field styling; have the components and FormBuilder *apply* those classes instead of re-listing utilities; delete the duplicated copies and dead code. No visual change.

**Architecture:** CSS-class-canonical. `application.css` defines the classes; `UI::*` components and `TailwindFormBuilder` apply them. Error state is attribute-driven via `.form-field[aria-invalid="true"]`. App-only — the app's copied components intentionally diverge from the gem's self-contained versions.

**Tech Stack:** Rails 8.1, Ruby 4, ViewComponent, TailwindCSS v4 (OKLCH tokens, `@layer components`, `@apply`), RSpec. Work on branch `refactor/ui-style-source-of-truth` (already created off `origin/main`).

**Conventions:**
- Run specs: `bundle exec rspec <path>`. Build CSS: `bin/rails tailwindcss:build` (compiled output: `app/assets/builds/tailwind.css`).
- Component specs assert the **class attribute string** (`page.find(...)[:class]`) — Capybara, no raw-HTML regexes.
- The real "no visual change" gate is the existing **system + AAA-axe specs** (they render the *compiled* CSS); component specs only assert the component hands off the right class.
- Commit messages: Conventional Commits, no `Co-Authored-By`/AI attribution. Don't push (the user pushes).

---

## File Structure

| File | Change |
|---|---|
| `app/assets/tailwind/application.css` | ADD `.form-field` (+ `[aria-invalid]`) and `.form-file` inside `@layer components`, after `.form-input`, with a disambiguation comment. `.btn-*` and `.form-input` unchanged. |
| `app/components/ui/button_component.rb` | `VARIANTS` → class-name strings; delete `FILLED`/`TEXT`; update docstring. |
| `app/components/ui/input_component.rb` | apply `cn("form-field", @extra_class)`; delete `BASE`/`NORMAL`/`ERROR`; update docstring. |
| `app/components/ui/textarea_component.rb` | apply `cn("form-field", @extra_class)`; delete `BASE`/`NORMAL`/`ERROR`. |
| `app/components/ui/file_input_component.rb` | apply `cn("form-file", @extra_class)`; delete `BASE`. |
| `app/form_builders/tailwind_form_builder.rb` | `submit` → `.btn-primary`; `select_html_options` → `.form-field`; delete `SUBMIT_CLASSES`/`FIELD_BASE`/`FIELD_NORMAL`/`FIELD_ERROR`/`FILE_FIELD_CLASSES`/`field_options`. |
| `spec/components/ui/{button,input,textarea,file_input}_component_spec.rb` | Rewrite utility assertions → class-name assertions; keep behavior/aria assertions. |

**Out of scope (separate efforts):** the `.modelrails_ui/house-rules.md` agent-rules wording (lands with app-adoption); removing unused `.bg-hue-interactive`; splitting prose/Rouge CSS.

---

### Task 1: Add the canonical field classes to CSS

**Files:**
- Modify: `app/assets/tailwind/application.css` (inside `@layer components { … }`, after the `.form-input` rule, ~line 208)

- [ ] **Step 1: Add the classes + disambiguation comment**

Inside the `@layer components` block, immediately after the closing `}` of `.form-input` (line 208) and before the block's closing `}` (line 209), insert:

```css

  /* Two field-control variants — pick by surface context, not by element:
     - .form-field  (raised: bg-surface-raised + text-text-heading): form-builder-managed
       inputs / textareas / selects. Error state is attribute-driven (.form-field[aria-invalid]).
     - .form-input  (flat:   bg-surface + text-text-body): inline / chrome controls
       (header search, user-menu, footer) sitting directly on the page surface.
     Both are AAA-tuned and aligned to --form-input-height. */
  .form-field {
    @apply block w-full rounded-md border px-3 py-2 placeholder:text-text-muted focus:outline-none focus:ring-2 min-h-[var(--form-input-height)];
    @apply border-border-strong bg-surface-raised text-text-heading focus:ring-interactive-focus disabled:cursor-not-allowed disabled:opacity-50;
  }

  .form-field[aria-invalid="true"] {
    @apply border-danger ring-2 ring-danger bg-danger-surface text-danger focus:ring-danger;
  }

  /* File input — the file:* button styling; error state via aria-invalid:* utilities
     (a 1:1 move of the component's former FILE_FIELD_CLASSES). */
  .form-file {
    @apply block w-full text-sm text-text-body;
    @apply file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium;
    @apply file:bg-interactive file:text-text-on-interactive hover:file:bg-interactive-hover;
    @apply file:cursor-pointer file:min-h-[var(--form-input-height)];
    @apply disabled:cursor-not-allowed disabled:opacity-50;
    @apply aria-invalid:border-danger-border aria-invalid:ring-danger;
  }
```

`.form-field` equals the components' current `BASE + NORMAL` exactly; `.form-field[aria-invalid="true"]` equals their `ERROR`. `.form-file` equals `FileInputComponent::BASE` exactly.

- [ ] **Step 2: Build the CSS and verify the classes compile (positive control)**

Run:
```bash
bin/rails tailwindcss:build
grep -c 'form-field' app/assets/builds/tailwind.css
grep -o 'background-color:var(--color-surface-raised)' app/assets/builds/tailwind.css | head -1
```
Expected: `form-field` count ≥ 1; the `background-color:var(--color-surface-raised)` value is present (positive control that `@apply bg-surface-raised` resolved). If `@apply aria-invalid:*` errors during build, replace the two `aria-invalid:*` lines in `.form-file` with a sibling rule: `.form-file[aria-invalid="true"] { @apply border-danger-border ring-danger; }`.

- [ ] **Step 3: Confirm nothing else broke**

Run: `bundle exec rspec spec/components/ui`
Expected: PASS (the new classes aren't referenced yet, so all existing component specs are unaffected).

- [ ] **Step 4: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat(ui): add canonical .form-field/.form-file CSS classes"
```

---

### Task 2: ButtonComponent applies `.btn-*`

**Files:**
- Modify: `app/components/ui/button_component.rb:8-21` (constants) and the docstring at `:5-7`
- Test: `spec/components/ui/button_component_spec.rb`

- [ ] **Step 1: Rewrite the spec's utility assertions to class-name assertions**

In `spec/components/ui/button_component_spec.rb`, replace the bodies of the four utility-asserting examples (keep `destructive` alias, `href`→link, and unknown-variant examples as-is):

```ruby
  it "primary applies .btn-primary" do
    render_inline(described_class.new("Save", variant: :primary))
    b = page.find("button")
    expect(b.text).to eq("Save")
    expect(b[:class]).to eq("btn-primary")
  end

  it "secondary applies .btn-secondary" do
    render_inline(described_class.new("Cancel", variant: :secondary))
    expect(page.find("button")[:class]).to eq("btn-secondary")
  end

  it "danger applies .btn-danger" do
    render_inline(described_class.new("Delete", variant: :danger))
    expect(page.find("button")[:class]).to eq("btn-danger")
  end

  it "text_interactive applies the text-button class trio" do
    render_inline(described_class.new("Learn more", variant: :text_interactive))
    expect(page.find("button")[:class]).to eq("btn-touch-target btn-text btn-text-interactive")
  end
```

- [ ] **Step 2: Run the spec — expect FAIL**

Run: `bundle exec rspec spec/components/ui/button_component_spec.rb`
Expected: FAIL — the component still emits raw utilities (e.g. `bg-interactive …`), not `btn-primary`.

- [ ] **Step 3: Change VARIANTS to class names + update docstring**

In `app/components/ui/button_component.rb`, replace the `FILLED`, `TEXT`, and `VARIANTS` constants (lines 8-21) with:

```ruby
    # Applies the app's .btn-* classes (app/assets/tailwind/application.css @layer
    # components). This app-local copy intentionally diverges from modelrails_ui's
    # self-contained (raw-utility) ButtonComponent: this app owns its design tokens,
    # so the component points at the canonical CSS classes instead of re-listing them.
    VARIANTS = {
      primary: "btn-primary",
      secondary: "btn-secondary",
      danger: "btn-danger",
      text: "btn-touch-target btn-text btn-text-interactive",
      text_interactive: "btn-touch-target btn-text btn-text-interactive",
      text_danger: "btn-touch-target btn-text btn-text-danger"
    }.freeze
```

Also update the class docstring (lines 5-7) from "Reproduces the host app's .btn-* button system" to "Applies the host app's .btn-* button classes (see VARIANTS)." Leave `SIZES`, `VARIANT_ALIASES`, `initialize`, `call`, `coerce_variant`, and `component_classes` unchanged.

- [ ] **Step 4: Run the spec — expect PASS**

Run: `bundle exec rspec spec/components/ui/button_component_spec.rb`
Expected: PASS (all examples, incl. destructive alias, href link, unknown-variant raise).

- [ ] **Step 5: Commit**

```bash
git add app/components/ui/button_component.rb spec/components/ui/button_component_spec.rb
git commit -m "refactor(ui): ButtonComponent applies .btn-* classes (one source of truth)"
```

---

### Task 3: Input + Textarea components apply `.form-field`

**Files:**
- Modify: `app/components/ui/input_component.rb` (constants `:8-12`, `input_attrs` `:36`, docstring `:5-7`)
- Modify: `app/components/ui/textarea_component.rb` (constants `:7-11`, `textarea_attrs` `:33`)
- Test: `spec/components/ui/input_component_spec.rb`, `spec/components/ui/textarea_component_spec.rb`

- [ ] **Step 1: Rewrite the spec class assertions**

In `spec/components/ui/input_component_spec.rb`, replace the third example ("applies disabled styling…") with:

```ruby
  it "applies the .form-field class" do
    render_inline(described_class.new(name: "q"))

    expect(page.find("input")[:class]).to eq("form-field")
  end
```

(Keep examples 1 and 2 — the aria wiring and the omits-optional-aria tests — unchanged.)

In `spec/components/ui/textarea_component_spec.rb`, replace both examples' class assertions:

```ruby
  it "renders value as content, .form-field class, and a11y params (builder-driven)" do
    render_inline(described_class.new(
      name: "post[body]", value: "Hello", required: true, invalid: true, describedby: "post_body-error"
    ))

    ta = page.find("textarea")
    expect(ta.text.strip).to eq("Hello")
    expect(ta[:name]).to eq("post[body]")
    expect(ta["aria-required"]).to eq("true")
    expect(ta["aria-invalid"]).to eq("true")
    expect(ta["aria-describedby"]).to eq("post_body-error")
    expect(ta[:class]).to eq("form-field")
  end

  it "uses .form-field and block content by default (standalone)" do
    render_inline(described_class.new(name: "q")) { "typed" }

    ta = page.find("textarea")
    expect(ta.text.strip).to eq("typed")
    expect(ta[:class]).to eq("form-field")
    expect(ta["aria-invalid"]).to be_nil
  end
```

- [ ] **Step 2: Run the specs — expect FAIL**

Run: `bundle exec rspec spec/components/ui/input_component_spec.rb spec/components/ui/textarea_component_spec.rb`
Expected: FAIL — components still emit `cn(BASE, … )` utilities, not `form-field`.

- [ ] **Step 3: Change the components**

In `app/components/ui/input_component.rb`: delete the `BASE`, `NORMAL`, `ERROR` constants (lines 8-12); change `input_attrs` line 36 from `class: cn(BASE, @invalid ? ERROR : NORMAL, @extra_class)` to:

```ruby
      attrs = { type: @type, class: cn("form-field", @extra_class) }
```

Update the docstring (lines 5-7) to: "Applies the app's `.form-field` class; error styling is attribute-driven via `.form-field[aria-invalid]` in application.css. The component sets `aria-invalid` when `invalid:`." Leave `@invalid`/`aria-invalid` handling (line 41) intact.

In `app/components/ui/textarea_component.rb`: delete `BASE`, `NORMAL`, `ERROR` (lines 7-11); change `textarea_attrs` line 33 from `class: cn(BASE, @invalid ? ERROR : NORMAL, @extra_class)` to:

```ruby
      attrs = { class: cn("form-field", @extra_class) }
```

Leave the `aria-invalid` line intact.

- [ ] **Step 4: Run the specs — expect PASS**

Run: `bundle exec rspec spec/components/ui/input_component_spec.rb spec/components/ui/textarea_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/ui/input_component.rb app/components/ui/textarea_component.rb spec/components/ui/input_component_spec.rb spec/components/ui/textarea_component_spec.rb
git commit -m "refactor(ui): Input/Textarea components apply .form-field"
```

---

### Task 4: FileInput component applies `.form-file`

**Files:**
- Modify: `app/components/ui/file_input_component.rb` (constant `BASE` `:8-13`, `call` `:29`)
- Test: `spec/components/ui/file_input_component_spec.rb`

- [ ] **Step 1: Rewrite the spec's utility assertions**

In `spec/components/ui/file_input_component_spec.rb`, replace the four `expect(inp[:class]).to include(...)` lines with one:

```ruby
    expect(inp[:class]).to eq("form-file")
```

(Keep the name/accept/aria-invalid/aria-describedby assertions.)

- [ ] **Step 2: Run the spec — expect FAIL**

Run: `bundle exec rspec spec/components/ui/file_input_component_spec.rb`
Expected: FAIL — component emits `cn(BASE, …)` utilities, not `form-file`.

- [ ] **Step 3: Change the component**

In `app/components/ui/file_input_component.rb`: delete the `BASE` constant (lines 8-13); change `call` line 29 from `class: cn(BASE, @extra_class)` to:

```ruby
      attrs = { type: "file", class: cn("form-file", @extra_class) }
```

Update the docstring (lines 5-7) to: "Applies the app's `.form-file` class (file:* styling + aria-invalid error utilities, defined in application.css)."

- [ ] **Step 4: Run the spec — expect PASS**

Run: `bundle exec rspec spec/components/ui/file_input_component_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/ui/file_input_component.rb spec/components/ui/file_input_component_spec.rb
git commit -m "refactor(ui): FileInput component applies .form-file"
```

---

### Task 5: FormBuilder applies the classes; delete dead constants

**Files:**
- Modify: `app/form_builders/tailwind_form_builder.rb`

- [ ] **Step 1: Confirm the to-delete constants are now unused**

Run:
```bash
grep -rIn 'SUBMIT_CLASSES\|FIELD_BASE\|FIELD_NORMAL\|FIELD_ERROR\|FILE_FIELD_CLASSES\|field_options' app lib spec
```
Expected: matches ONLY inside `app/form_builders/tailwind_form_builder.rb` (their definitions + the two call sites changed below). No references elsewhere. (`FILE_FIELD_CLASSES` is already dead — `file_field` delegates to `ui_file`/`UI::FileInputComponent`.)

- [ ] **Step 2: Apply the classes in `submit` and `select_html_options`**

In `app/form_builders/tailwind_form_builder.rb`, change `submit` (line 131) to:

```ruby
  def submit(value = nil, options = {})
    super(value, options.merge(class: merge_classes("btn-primary", options[:class])))
  end
```

Change `select_html_options` (lines 213-219) to:

```ruby
  def select_html_options(method, wrapper_opts)
    {
      class: "form-field",
      id: field_id(method)
    }.merge(aria_attributes(method, wrapper_opts))
  end
```

(`aria_attributes` already sets `aria-invalid` on error, so `<select>` error styling triggers via `.form-field[aria-invalid]`.)

- [ ] **Step 3: Delete the dead constants and method**

Delete from `app/form_builders/tailwind_form_builder.rb`:
- `FIELD_BASE` (line 6), `FIELD_NORMAL` (line 9), `FIELD_ERROR` (line 10), `SUBMIT_CLASSES` (line 17), `FILE_FIELD_CLASSES` (line 21)
- the entire `field_options` method (lines 200-211)

Keep `FIELD_NORMAL`-unrelated constants: `LABEL_CLASSES`, `ERROR_LABEL_CLASSES`, `HELP_TEXT_CLASSES`, `ERROR_MESSAGE_CLASSES`, `CHECKBOX_CLASSES`.

- [ ] **Step 4: Run the form + builder specs — expect PASS**

Run:
```bash
bundle exec rspec spec/system/registration_validation_spec.rb spec/form_builders 2>/dev/null; \
bundle exec rspec --tag type:system -e form 2>/dev/null || true
```
Then the focused form/component coverage:
```bash
bundle exec rspec spec/components/ui
```
Expected: PASS. (If `spec/form_builders` doesn't exist, the registration_validation system spec + component specs are the coverage; both must be green.)

- [ ] **Step 5: Commit**

```bash
git add app/form_builders/tailwind_form_builder.rb
git commit -m "refactor(ui): FormBuilder applies .btn-primary/.form-field; drop duplicated + dead constants"
```

---

### Task 6: Full verification — the real "no visual change" gate

**Files:** none (verification only)

- [ ] **Step 1: Build CSS and run the full suite**

Run:
```bash
bin/rails tailwindcss:build
bundle exec rspec
```
Expected: 0 failures, 0 errors. The system + AAA-axe specs render the compiled CSS — a broken `.btn-*`/`.form-field` would fail them. This is the actual visual-parity gate.

- [ ] **Step 2: Confirm no orphaned references remain**

Run:
```bash
grep -rIn 'SUBMIT_CLASSES\|FIELD_BASE\|FIELD_NORMAL\|FIELD_ERROR\|FILE_FIELD_CLASSES\|field_options\|FILLED\|TEXT\b' app/components/ui app/form_builders
```
Expected: no matches for the deleted button/field constants (matches for unrelated words are fine — eyeball them).

- [ ] **Step 3: Manual screenshot review (pre-push checklist — per project workflow)**

Render and visually compare against `origin/main`, **light and dark**:
- A form page (e.g. account/theme preferences or workspace settings) — inputs, a `<select>`, submit button, and a field in error state.
- A page with `.btn-primary`/`.btn-secondary` and a `.btn-text*` link.
- A file-upload field; a disabled `<select>` (confirm the newly-gained `disabled:opacity-50` reads acceptably on `bg-surface-raised`).
Confirm pixel-parity (the disabled-select affordance is the one intentional difference).

- [ ] **Step 4: Final commit (if any review tweaks)**

Only if Step 3 surfaced a fix; otherwise nothing to commit. Do **not** push — the user pushes after review.

---

## Self-Review

**Spec coverage:**
- Button 3→1 → Task 2 + Task 5 (submit). ✓
- Field two-variants (`.form-field` raised + `.form-input` unchanged) → Task 1 + Tasks 3/5. ✓
- `.form-file` → Task 1 + Task 4. ✓
- `aria-invalid` error mechanism → Task 1 (`.form-field[aria-invalid]`) + components keep setting it. ✓
- Dead code (`SUBMIT_CLASSES`/`FIELD_*`/`FILE_FIELD_CLASSES`/`field_options`) → Task 5. ✓
- `<select>` aria-invalid parity (DHH) → Task 5 Step 2 (relies on existing `aria_attributes`; verified in Task 6 system spec). ✓
- Component docstrings + CSS disambiguation comment (Dave) → Tasks 1, 2, 3, 4. ✓
- Button call-site override scan (DHH) → already run during planning: **0 found**, so no call-site task needed. ✓
- Disabled-select micro-change (Adam) → Task 6 Step 3 screenshot check. ✓
- Testing gate = existing system/axe specs (Joël/Sandi decision) → Task 6 Step 1. ✓
- Turbo Stream sanity (Jorge) → covered by existing system specs rendering streams; called out in spec Testing §4. ✓
- House-rules wording → out of scope (app-adoption), noted. ✓

**Placeholder scan:** No TBD/TODO; every code step shows exact code; the `@apply aria-invalid:*` fallback is specified inline. ✓

**Name consistency:** `.form-field`, `.form-file`, `btn-primary/secondary/danger`, `btn-touch-target btn-text btn-text-interactive/danger`, `cn("form-field"/"form-file"/...)` consistent across CSS, components, FormBuilder, and specs. ✓
