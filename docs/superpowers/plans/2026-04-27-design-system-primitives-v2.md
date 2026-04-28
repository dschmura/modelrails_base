# Design System Primitives v2 — Spacing Tokens & Component Utilities

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a small, deliberate spacing token layer and a `@layer components` block of utility classes that encapsulates recurring patterns (touch-target buttons, action groups, page containers). The repeated `min-h-[44px] min-w-[44px] inline-flex items-center justify-center px-2` string — currently duplicated 8+ times across views — becomes a single `.btn-touch-target` utility. Touchpoint inputs adopt a matching `--form-input-height` so buttons and inputs visually align.

**Architecture:**

- **Semantic spacing tokens are CSS-var-only.** They are *not* registered in `@theme` (no `mt-section-gap` utilities). They are consumed only inside `@layer components` rules.
- **Tailwind's default spacing scale is preserved.** No `--spacing-*` overrides. The "preferred 9-step subset" (`0/4/8/12/16/24/32/48/64`px) is a documented *convention*, enforced by code review, not by token-namespace surgery.
- **`page-container` is a utility, not a token.** Page horizontal padding belongs in a layout utility class — not as `--space-page-padding-x` exposed as `px-page-padding-x`.
- **Component utilities live in a new `@layer components` block in `application.css`.** This is the first such block in the codebase. The pattern set here governs future component additions.
- **Proof refactor scope:** [app/views/account/connected_accounts/index.html.erb](app/views/account/connected_accounts/index.html.erb) only. It contains all three recurring patterns (touch-target buttons, action group, page container) and exercises every new utility. Other views are intentionally left for a follow-up sweep so the system can be validated before mass migration.
- **Form builder migration:** [app/form_builders/tailwind_form_builder.rb](app/form_builders/tailwind_form_builder.rb) (the globally-registered default form builder) is migrated *in this branch* to consume `--form-input-height`. This unifies the touch-target height across buttons, inputs, and submit buttons under one token without requiring view-by-view migration — every existing `form_with` call benefits automatically. The change is naming-only: `min-h-[44px]` → `min-h-[var(--form-input-height)]`. Same value, named source of truth.

**Tech Stack:** TailwindCSS 4, `@theme inline` pattern, RSpec system specs (Capybara + Playwright + axe-core for accessibility regressions).

**Spec / Brainstorm Source:** Conversation review-panel synthesis (Adam Wathan + Steve Schoger) on 2026-04-27. Key blocker fixes adopted from that review:

1. Semantic spacing tokens are CSS-var-only, consumed only inside components (Adam).
2. Replace `--space-page-padding-x` with a `.page-container` utility (Adam + Steve, independent agreement).
3. Keep Tailwind's full default spacing scale; document the 9-step subset as preference, not as a hard cull (Adam).
4. Pair `.btn-touch-target` with a `--form-input-height` token so 44px buttons align with form input heights (Steve).

**Branch:** `chore/design-system-primitives-v2` off `main` (clean tree, OAuth + infra-leverage already merged at `2a38f4c`).

---

## File Map

| Path | Action | Purpose |
| ---- | ------ | ------- |
| `app/assets/tailwind/tokens/_spacing.css` | **Create** | Semantic CSS-var spacing tokens + `--form-input-height`. No `@theme`. |
| [app/assets/tailwind/application.css](app/assets/tailwind/application.css) | Modify | Import `_spacing.css`; add `@layer utilities { .page-container }`; add `@layer components { .btn-touch-target / .btn-text / .btn-text-danger / .btn-text-interactive / .action-group }`. |
| [app/views/account/connected_accounts/index.html.erb](app/views/account/connected_accounts/index.html.erb) | Modify | Apply `.page-container` to outer wrapper; replace repeated touch-target strings with `.btn-touch-target .btn-text .btn-text-{danger,interactive}`; replace ad-hoc trailing-button container with `.action-group`. |
| [app/form_builders/tailwind_form_builder.rb](app/form_builders/tailwind_form_builder.rb) | Modify | Replace 3 occurrences of `min-h-[44px]` with `min-h-[var(--form-input-height)]` so the global default form builder reads from the token (single source of truth for touch-target height). |
| [spec/system/oauth_link_verification_spec.rb](spec/system/oauth_link_verification_spec.rb) | Verify-only | Axe-core CI hook + existing scenarios must still pass; no spec changes expected. |
| [docs/design-system.md](docs/design-system.md) | **Create** | Document the preferred 9-step spacing convention, semantic-token policy, and component utility catalog. Single source of truth for future contributors. |
| [CHANGELOG.md](CHANGELOG.md) | Modify | New `[Unreleased]` entry describing the design system primitives v2 work. |

Six files touched by hand; one new directory entry (`docs/design-system.md`) if `docs/` doesn't already host it.

---

## Out of scope (explicit)

These were considered and deliberately deferred per the panel review:

- Typography token scale (font-size, line-height, font-weight). Defer 4 weeks post-ship.
- Border-radius token scale. Same trigger.
- Shadow token scale. Same trigger.
- Modal padding token (`--space-modal-padding-x: 24px`). Add only if a 2nd modal-padding mismatch emerges.
- Stylelint enforcement of the 9-step preferred subset. Defer until convention slippage is observed; tracked as a follow-up.
- Mass migration of every view. Scope is the proof refactor only.

---

## Task 1 — Branch setup and pre-flight

- [ ] **Step 1.1: Confirm clean tree on main**

```bash
git status --short
git log --oneline -1
```

Expected: working tree clean; HEAD at `2a38f4c Merge branch 'chore/oauth-infra-leverage'`.

- [ ] **Step 1.2: Create the feature branch**

```bash
git checkout -b chore/design-system-primitives-v2
```

- [ ] **Step 1.3: Verify Tailwind builds at HEAD**

```bash
bundle exec rspec spec/system/oauth_link_verification_spec.rb --format documentation
```

Expected: all examples pass. We're establishing a green baseline so any later failures are clearly attributable to the design system changes.

---

## Task 2 — Define semantic spacing tokens (CSS-var-only)

**Files:** Create `app/assets/tailwind/tokens/_spacing.css`.

- [ ] **Step 2.1: Write the spacing tokens file**

Create `app/assets/tailwind/tokens/_spacing.css` with this content:

```css
/* ==========================================================================
   Semantic Spacing Tokens — CSS-var-only (NOT registered in @theme)
   ==========================================================================
   These tokens encode reusable composition rules for the design system.
   They are intentionally NOT registered as Tailwind utilities.

   POLICY:
   - Consume these only inside @layer components rules in application.css.
   - Templates should never reference them directly (no `mt-section-gap` etc.).
   - For one-off spacing in templates, use Tailwind utilities directly (mt-3, gap-3).

   PREFERRED PRIMITIVE SPACING SCALE (convention — see docs/design-system.md):
   When choosing a Tailwind spacing utility, prefer this 9-step subset of the
   default scale for visual rhythm:
       0    → 0
       1    →  4px
       2    →  8px
       3    → 12px
       4    → 16px
       6    → 24px
       8    → 32px
       12   → 48px
       16   → 64px
   The full Tailwind default scale (0.5, 1.5, 2.5, etc.) remains available
   for cases where the rhythm requires intermediate values; reach for those
   only when the preferred steps would compromise the layout.
   ========================================================================== */

:root {
  /* Reusable composition tokens — consumed only inside components. */
  --space-section-gap: 2rem;          /* 32px — vertical gap between top-level page sections */
  --space-row-padding: 0.75rem;       /* 12px — internal vertical padding on list-row items */
  --space-action-group-gap: 0.75rem;  /* 12px — gap between trailing action buttons */

  /* Form input height — 44px matches WCAG 2.2 AAA touch-target minimum.
     Used by `.btn-touch-target` and any form input rule so buttons and
     inputs visually align. */
  --form-input-height: 2.75rem;       /* 44px */
}
```

Note: there's no `--space-page-padding-x` token — page horizontal padding is encoded in `.page-container` (Task 3) instead, per the panel's verdict that layout decisions don't belong in the token layer.

- [ ] **Step 2.2: Import the new tokens file in application.css**

Open [app/assets/tailwind/application.css](app/assets/tailwind/application.css). Locate the `Design token layers` import block (around line 7-10):

```css
/* Design token layers */
@import "./tokens/_primitives.css";
@import "./tokens/_semantic.css";
@import "./tokens/_signals.css";
```

Add the `_spacing.css` import on a new line after `_signals.css`:

```css
@import "./tokens/_signals.css";
@import "./tokens/_spacing.css";
```

- [ ] **Step 2.3: Verify the build still succeeds**

```bash
bundle exec rspec spec/system/oauth_link_verification_spec.rb --format documentation
```

Expected: green. CSS files are statically imported; an unused token file should not break the build.

---

## Task 3 — Add `.page-container` layout utility

**Files:** Modify [app/assets/tailwind/application.css](app/assets/tailwind/application.css).

- [ ] **Step 3.1: Locate the right insertion point**

The file has implicit utilities (`.bg-hue-initials`, dialog `::backdrop` rules, `.prose`). We're adding our first true `@layer utilities` block near the top — after the `@theme inline` block (~line 86) and before the OKLCH hue utilities (~line 96), so layout primitives precede component decoration.

- [ ] **Step 3.2: Add the `@layer utilities` block**

After line 86 (closing brace of `@theme inline`), insert:

```css
/* ==========================================================================
   Layout utilities
   ==========================================================================
   These wrap recurring layout primitives so templates can express intent
   directly. Currently: page-level container with consistent horizontal
   padding and max-width.
   ========================================================================== */

@layer utilities {
  .page-container {
    @apply max-w-2xl mx-auto px-4;
  }
}
```

Rationale on `max-w-2xl`: matches the existing connected-accounts wrapper (`max-w-2xl mx-auto px-4 py-16`). If a future page needs a wider container, introduce `.page-container-wide` or pass `--page-container-max` as a CSS var override on the element. Don't pre-engineer that now.

- [ ] **Step 3.3: Verify the build**

```bash
bundle exec rspec spec/system/oauth_link_verification_spec.rb --format documentation
```

Expected: green. The utility isn't applied yet, so no behavior change.

---

## Task 4 — Add component utilities in `@layer components`

**Files:** Modify [app/assets/tailwind/application.css](app/assets/tailwind/application.css).

- [ ] **Step 4.1: Add the `@layer components` block**

Insert immediately after the `@layer utilities` block from Task 3, before the OKLCH hue utilities. Add:

```css
/* ==========================================================================
   Component utilities
   ==========================================================================
   Encapsulate recurring view patterns. These are NOT theme tokens — they
   are composition rules for repeated structural and interactive patterns.

   Naming policy:
   - .btn-text* are a color-variant family of one base text-button style.
     They share .btn-touch-target sizing/centering when used as buttons.
   - .action-group is a flex container with consistent inline gap; will
     grow constraints (flex-wrap, flex-row-reverse, etc.) over time.
   ========================================================================== */

@layer components {
  /* Touch-target sizing for interactive buttons.
     44x44 minimum matches WCAG 2.2 AAA target size + --form-input-height,
     so buttons paired with form inputs visually align. */
  .btn-touch-target {
    @apply inline-flex items-center justify-center;
    min-height: var(--form-input-height);
    min-width: var(--form-input-height);
    @apply px-2;
  }

  /* Base text-only button styling.
     Color, font-size, and weight stay in the template — this rule only
     handles cross-cutting concerns (focus ring base, hover behavior,
     rounded corners, semantic underline). */
  .btn-text {
    @apply font-medium underline rounded;
    @apply focus:outline-none focus:ring-2;
    @apply hover:no-underline;
  }

  /* Color variants of .btn-text. Apply alongside .btn-text. */
  .btn-text-danger {
    @apply text-danger focus:ring-danger;
  }

  .btn-text-interactive {
    @apply text-interactive focus:ring-interactive-focus;
  }

  /* Inline flex container for trailing button groups (Resend / Cancel,
     Edit / Delete, etc.). Consumes --space-action-group-gap so spacing
     stays consistent across the app. */
  .action-group {
    display: inline-flex;
    align-items: center;
    gap: var(--space-action-group-gap);
  }
}
```

Notes:

- `.btn-text` does NOT include `text-sm` per Adam's recommendation — text size stays in the template so a developer reading markup can see the size without diving into CSS.
- `.btn-touch-target` uses `var(--form-input-height)` (not a hardcoded `44px`) so future adjustments propagate automatically.
- Focus rings use `ring-danger` and `ring-interactive-focus` — these are existing semantic color tokens. Verify they exist:

```bash
grep -n 'ring-danger\|ring-interactive-focus' app/assets/tailwind/tokens/_semantic.css app/assets/tailwind/tokens/_signals.css
```

If `ring-danger` resolves to `--color-danger` and `ring-interactive-focus` resolves to `--color-interactive-focus`, the focus rings work as-is. If not, switch to direct `focus:ring-[color:var(--color-danger)]` syntax — but check first; a name match almost certainly exists.

- [ ] **Step 4.2: Verify the build**

```bash
bundle exec rspec spec/system/oauth_link_verification_spec.rb --format documentation
```

Expected: green. Utilities are defined but not applied — no visual change.

---

## Task 5 — Proof refactor: `connected_accounts/index.html.erb`

**Files:** Modify [app/views/account/connected_accounts/index.html.erb](app/views/account/connected_accounts/index.html.erb).

This is the proof. Apply every new utility once. If anything is awkward to use, the system has a flaw — fix the system, not the template.

- [ ] **Step 5.1: Read current template state**

Use Read to load the file. Current outer wrapper (line 2):

```erb
<div class="max-w-2xl mx-auto px-4 py-16">
```

Replace with:

```erb
<div class="page-container py-16">
```

Note `py-16` stays — vertical padding is page-specific layout, not a container concern.

- [ ] **Step 5.2: Refactor the Resend button (~lines 46-53)**

Current:

```erb
<%= button_to t("account.connected_accounts.index.resend_action"),
      resend_verification_account_connected_account_path(authentication),
      method: :post,
      aria: { label: t("account.connected_accounts.index.resend_action_aria_label", provider: authentication.display_provider) },
      class: "text-sm text-interactive underline hover:no-underline
              focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded
              min-h-[44px] min-w-[44px] inline-flex items-center justify-center px-2",
      form: { class: "inline" } %>
```

Replace `class:` with:

```erb
class: "btn-touch-target btn-text btn-text-interactive text-sm",
```

- [ ] **Step 5.3: Refactor the Cancel button (~lines 54-61)**

Current `class:` (danger variant):

```text
text-sm font-medium text-danger underline hover:no-underline
focus:outline-none focus:ring-2 focus:ring-danger rounded
min-h-[44px] min-w-[44px] inline-flex items-center justify-center px-2
```

Replace with:

```erb
class: "btn-touch-target btn-text btn-text-danger text-sm",
```

- [ ] **Step 5.4: Refactor the Disconnect button (~lines 62-71)**

This is a `<button type="button">` not a `button_to`. Current class:

```text
text-sm font-medium text-danger underline hover:no-underline
focus:outline-none focus:ring-2 focus:ring-danger rounded
min-h-[44px] min-w-[44px] inline-flex items-center justify-center px-2
```

Replace with:

```erb
class="btn-touch-target btn-text btn-text-danger text-sm"
```

- [ ] **Step 5.5: Refactor the inline action-group containers**

The pending row has a `<div class="flex items-center gap-3 text-sm">` wrapper around Resend/Cancel (~line 44). Replace with:

```erb
<div class="action-group text-sm">
```

The verified row has `<div data-controller="modal" class="inline">` — leave this alone. It's a single button with a Stimulus controller, not a multi-button group.

- [ ] **Step 5.6: Confirm visual parity**

Start the dev server and inspect [http://localhost:3000/account/connected_accounts](http://localhost:3000/account/connected_accounts) in a browser:

```bash
bin/dev
```

Sign in, ensure at least one verified and one pending authentication exist (you can use `rails console` to create a `pending` Authentication if needed). Verify:

- Page padding looks identical to `main` branch (`max-w-2xl`, `px-4`, `py-16`).
- Buttons are 44×44 minimum, touch-target compliant.
- Resend (info) and Cancel/Disconnect (danger) colors render correctly.
- Focus rings appear on Tab navigation; ring color matches the button family.
- Hover state removes the underline.
- Spacing between Resend and Cancel buttons matches the original (12px gap).

If anything looks off, fix the *system* (`@layer components` rules) rather than re-introducing utility classes in the template.

- [ ] **Step 5.7: Run the system spec**

```bash
bundle exec rspec spec/system/oauth_link_verification_spec.rb --format documentation
```

Expected: all examples pass, including the axe-core accessibility audit (in CI). The button changes are pure CSS extraction — semantics, ARIA labels, and DOM structure are unchanged.

- [ ] **Step 5.8: Run the connected-accounts request specs**

```bash
bundle exec rspec spec/requests/account/connected_accounts_spec.rb --format documentation
```

Expected: green. Request specs assert content and flash, not classes.

---

## Task 6 — Migrate `TailwindFormBuilder` to consume `--form-input-height`

**Files:** Modify [app/form_builders/tailwind_form_builder.rb](app/form_builders/tailwind_form_builder.rb).

**Why this task exists:** The codebase has a globally-registered default form builder ([config/initializers/form_builder.rb:2](config/initializers/form_builder.rb#L2)) that already enforces `min-h-[44px]` on all text inputs (line 3, `FIELD_BASE`), submit buttons (line 14, `SUBMIT_CLASSES`), and file fields (line 18, `FILE_FIELD_CLASSES`). Steve Schoger's blocker — "buttons and inputs must align at the same height" — is **already solved at the form builder level**. The only thing missing is naming: `44px` is a magic number repeated three times. This task makes the form builder consume the new `--form-input-height` token so the entire system has one source of truth.

After this task: changing the touch-target height (e.g., to 48px) is a one-line edit in `_spacing.css`. Today, it would require coordinated edits across the form builder constants and the `.btn-touch-target` utility.

- [ ] **Step 6.1: Replace the literal in `FIELD_BASE`**

Open [app/form_builders/tailwind_form_builder.rb](app/form_builders/tailwind_form_builder.rb). Locate line 3:

```ruby
FIELD_BASE = "block w-full rounded-md border px-3 py-2 placeholder:text-text-muted focus:outline-none focus:ring-2 min-h-[44px]"
```

Replace `min-h-[44px]` with `min-h-[var(--form-input-height)]`:

```ruby
FIELD_BASE = "block w-full rounded-md border px-3 py-2 placeholder:text-text-muted focus:outline-none focus:ring-2 min-h-[var(--form-input-height)]"
```

Tailwind 4 supports CSS variables inside arbitrary value syntax (`min-h-[var(--…)]`), so this compiles to `min-height: var(--form-input-height)` on the rendered element.

- [ ] **Step 6.2: Replace the literal in `SUBMIT_CLASSES`**

Locate line 14:

```ruby
SUBMIT_CLASSES = "min-h-[44px] inline-flex items-center justify-center px-4 rounded-md bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus cursor-pointer"
```

Replace `min-h-[44px]` with `min-h-[var(--form-input-height)]`.

- [ ] **Step 6.3: Replace the literal in `FILE_FIELD_CLASSES`**

Locate line 18:

```ruby
FILE_FIELD_CLASSES = "block w-full text-sm text-text-body file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-interactive file:text-text-on-interactive hover:file:bg-interactive-hover file:cursor-pointer file:min-h-[44px]"
```

Note the `file:` prefix variant — this scopes the class to the input's pseudo-element. Replace `file:min-h-[44px]` with `file:min-h-[var(--form-input-height)]`.

- [ ] **Step 6.4: Run the form builder spec suite**

```bash
bundle exec rspec spec/form_builders/ --format documentation
```

Expected: all examples pass. The form builder's tests assert class strings on rendered elements; the new value will appear in those strings, so adjust the spec expectations only if a test pins on the exact `min-h-[44px]` literal. Read the spec output carefully — most likely the assertions check for the *presence* of `block w-full rounded-md` etc., not the exact arbitrary-value class.

If a spec does pin on `min-h-[44px]`, update the expectation to `min-h-[var(--form-input-height)]`. Document the change with a one-line comment in the spec explaining why (the form builder now reads from a token).

- [ ] **Step 6.5: Manual browser verification**

```bash
bin/dev
```

Visit any form-bearing page — [/users/sign_in](http://localhost:3000/users/sign_in), [/account/profile/edit](http://localhost:3000/account/profile/edit), or [/account/passwords/new](http://localhost:3000/account/passwords/new). Open DevTools and inspect a text input. Confirm:

- Computed `min-height` resolves to `2.75rem` / `44px`.
- The CSS rule cites `var(--form-input-height)` rather than a literal `44px`.

Then inspect a submit button on the same page. Same check.

If either resolves to anything other than 44px, the import order or token definition is wrong — re-read `_spacing.css` and the `application.css` import chain.

- [ ] **Step 6.6: Run the full system spec suite to confirm no visual regression**

```bash
bundle exec rspec spec/system/ --format documentation
```

Expected: all examples pass. System specs that interact with forms (sign-in, registration, profile edit, etc.) exercise the rendered HTML; if any class-pinned assertions exist, they'll surface here.

---

## Task 7 — Documentation

**Files:** Create `docs/design-system.md`.

- [ ] **Step 7.1: Write the design-system reference**

Create `docs/design-system.md`:

```markdown
# Design System

ModelRails uses a layered design system anchored on TailwindCSS 4. This document is the source of truth for spacing, component utilities, and naming conventions.

## Spacing

### Preferred scale (convention)

When applying Tailwind spacing utilities (`mt-*`, `p-*`, `gap-*`), prefer this 9-step subset of the default scale for visual rhythm:

| Step | Value | Pixels |
|------|-------|--------|
| `0`  | `0`        | 0   |
| `1`  | `0.25rem`  | 4   |
| `2`  | `0.5rem`   | 8   |
| `3`  | `0.75rem`  | 12  |
| `4`  | `1rem`     | 16  |
| `6`  | `1.5rem`   | 24  |
| `8`  | `2rem`     | 32  |
| `12` | `3rem`     | 48  |
| `16` | `4rem`     | 64  |

The full Tailwind default scale (`0.5`, `1.5`, `2.5`, etc.) remains available. Reach for intermediate values only when the preferred steps would compromise the layout — and prefer to add a semantic token (see below) over inline arbitrariness.

### Semantic spacing tokens (CSS-var-only)

Defined in `app/assets/tailwind/tokens/_spacing.css`. These encode reusable composition rules:

| Token | Value | Meaning |
|-------|-------|---------|
| `--space-section-gap`        | `2rem`    (32px) | Vertical gap between top-level page sections |
| `--space-row-padding`        | `0.75rem` (12px) | Internal vertical padding on list-row items |
| `--space-action-group-gap`   | `0.75rem` (12px) | Gap between trailing action buttons |
| `--form-input-height`        | `2.75rem` (44px) | Touch-target height for buttons + form inputs |

**Policy:** These are CSS variables only. They are *not* registered in `@theme` and have no Tailwind utility equivalents. Consume them only inside `@layer components` rules in `app/assets/tailwind/application.css` or inside the `TailwindFormBuilder` constants.

**`--form-input-height` consumers:**

- `.btn-touch-target` (in `application.css`) — uses `var(--form-input-height)` for `min-height` and `min-width` so buttons hit the WCAG 2.2 AAA touch-target minimum.
- `TailwindFormBuilder::FIELD_BASE` (text inputs, selects, textareas) — uses `min-h-[var(--form-input-height)]`.
- `TailwindFormBuilder::SUBMIT_CLASSES` (submit buttons) — same.
- `TailwindFormBuilder::FILE_FIELD_CLASSES` (file uploads, via `file:` prefix) — same.

To change the touch-target height app-wide (e.g., bump to 48px), edit `--form-input-height` in `tokens/_spacing.css`. All four consumers update automatically.

## Component utilities

Defined in `application.css` under `@layer components`. Apply via class names in templates.

### Buttons

| Class | Purpose |
|-------|---------|
| `.btn-touch-target` | 44×44 minimum sizing + flex centering. Applies WCAG 2.2 AAA touch-target compliance. |
| `.btn-text`         | Base text-only button styling: font-weight, underline, focus ring base, hover. |
| `.btn-text-danger`     | Color variant — danger semantic color + matching focus ring. |
| `.btn-text-interactive` | Color variant — interactive semantic color + matching focus ring. |

**Composition pattern:**

```erb
<%= button_to "Cancel",
      cancel_path,
      class: "btn-touch-target btn-text btn-text-danger text-sm" %>
```

Note: text size (e.g., `text-sm`) stays in the template, not inside `.btn-text`. This keeps inheritance transparent for readers.

### Layout

| Class | Purpose |
|-------|---------|
| `.page-container` | `max-w-2xl mx-auto px-4` — apply to outer wrapper of any page. |
| `.action-group`   | Inline-flex with `--space-action-group-gap` — wrap groups of trailing action buttons. |

## Adding new tokens or utilities

1. Spacing primitives → don't add. Use Tailwind defaults.
2. Spacing composition (a recurring pattern across views) → add a semantic CSS var to `_spacing.css`, consume it inside a `@layer components` rule.
3. Color tokens → see `tokens/_primitives.css`, `_semantic.css`, `_signals.css`.
4. New component utility → add to the existing `@layer components` block in `application.css`. Keep the class name structural (`.btn-text`, not `.danger-button`).
```

- [ ] **Step 7.2: Add a brief reference to README.md**

Open [README.md](README.md). Locate the "What's included (Phase 1)" section. Under "UI" (around line 110), the existing bullets describe accessibility and theming. Append:

```markdown
- Design system primitives — see [docs/design-system.md](docs/design-system.md) for spacing tokens, component utilities, and naming conventions.
```

---

## Task 8 — CHANGELOG and commit

**Files:** Modify [CHANGELOG.md](CHANGELOG.md).

- [ ] **Step 8.1: Add an Unreleased entry**

At the top of `CHANGELOG.md`, under `## [Unreleased]` (create the section if it doesn't exist), add:

```markdown
### Added
- Design system primitives v2: semantic spacing tokens (`--space-section-gap`, `--space-row-padding`, `--space-action-group-gap`, `--form-input-height`) in `app/assets/tailwind/tokens/_spacing.css`.
- Component utilities under `@layer components`: `.btn-touch-target`, `.btn-text`, `.btn-text-danger`, `.btn-text-interactive`, `.action-group`.
- Layout utility `.page-container` (`max-w-2xl mx-auto px-4`) for page-level wrappers.
- `docs/design-system.md` — single-source reference for the spacing convention, semantic tokens, component utilities.

### Changed
- Refactored `app/views/account/connected_accounts/index.html.erb` to consume the new utilities (proof refactor — visual output unchanged).
- `TailwindFormBuilder` now consumes `--form-input-height` via `min-h-[var(--form-input-height)]` instead of hardcoded `min-h-[44px]` in three constants. Single source of truth for touch-target height across all form inputs, submit buttons, and file fields.
```

- [ ] **Step 8.2: Run the full test suite**

Per project policy, run the full suite before commit:

```bash
bundle exec rspec
```

Expected: all examples pass, no new failures. (Per memory: "Full suite before commit".)

- [ ] **Step 8.3: Commit**

```bash
git add -A
git status
git commit -m "$(cat <<'EOF'
feat: design system primitives v2 — spacing tokens + component utilities

Establish a small, deliberate spacing token layer and a @layer components
block of utility classes. Replaces the repeated touch-target string with
.btn-touch-target, introduces .page-container as a layout primitive, and
adds .action-group / .btn-text-* for recurring patterns. Migrates the
default TailwindFormBuilder to consume --form-input-height, unifying the
44px touch-target value across buttons and form inputs under one token.

Architecture decisions (per review-panel synthesis 2026-04-27):
- Semantic spacing tokens are CSS-var-only, not registered in @theme.
- Tailwind default scale is preserved; the 9-step preferred subset is
  documented as a convention in docs/design-system.md.
- .page-container is a utility, not a token — layout decisions don't
  belong in the token layer.
- .btn-touch-target and TailwindFormBuilder both read --form-input-height,
  so future touch-target adjustments propagate from one source.

Proof refactor: connected_accounts/index.html.erb is the only view
migrated in this branch — it exercises every new utility and validates
the system before mass migration. The form builder migration is
naming-only (same 44px value); inputs and submit buttons render
identically, just consuming the named token.
EOF
)"
```

- [ ] **Step 8.4: Push and let Lefthook run full CI locally**

```bash
git push -u origin chore/design-system-primitives-v2
```

Lefthook pre-push runs RuboCop, Brakeman, and the full RSpec suite. Wait for green. Per memory: never bypass with `LEFTHOOK=0`.

---

## Verification checklist (post-merge)

| Item | How to verify |
|------|---------------|
| `_spacing.css` imported into `application.css` | `grep '_spacing' app/assets/tailwind/application.css` |
| Semantic tokens are NOT in `@theme inline` | `grep -A 80 '@theme inline' app/assets/tailwind/application.css \| grep -c 'space-section-gap'` → must be `0` |
| `.btn-touch-target` consumed by 3 buttons in connected-accounts | `grep -c 'btn-touch-target' app/views/account/connected_accounts/index.html.erb` → `3` |
| `.page-container` consumed by 1 wrapper | `grep -c 'page-container' app/views/account/connected_accounts/index.html.erb` → `1` |
| `docs/design-system.md` exists and is linked from README | `ls docs/design-system.md && grep -c 'design-system.md' README.md` |
| TailwindFormBuilder no longer contains `min-h-[44px]` literals | `grep -c 'min-h-\[44px\]' app/form_builders/tailwind_form_builder.rb` → `0` |
| TailwindFormBuilder consumes the token | `grep -c 'var(--form-input-height)' app/form_builders/tailwind_form_builder.rb` → `3` |
| Axe accessibility audit still clean in CI | `CI=true bundle exec rspec spec/system/oauth_link_verification_spec.rb` |
| Full suite green | `bundle exec rspec` |

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Focus-ring color names (`ring-danger`, `ring-interactive-focus`) don't resolve | Step 4.1 verifies via grep before commit. Fallback: explicit `focus:ring-[color:var(--color-danger)]`. |
| Visual regression after refactor (proof view looks different) | Step 5.6 manual browser check + axe-core CI audit. The classes encode the same behavior; expected visual change = none. |
| Future contributor adds `mt-section-gap` etc. | Documented in `docs/design-system.md` as policy + tokens are explicitly not in `@theme` so the utility class doesn't exist. Stylelint enforcement deferred until convention slippage is observed. |
| `@layer components` cascades unexpectedly with prose / dialog rules | `@layer components` has well-defined cascade order in TW4 (later than utilities? — no, utilities override components). The proof refactor should expose any conflict. |

---

## Success metrics

After this branch merges:

- Zero visual regressions on `account/connected_accounts/index.html.erb` (Steve's expectation: refactoring, not redesign).
- Zero visual regressions on every form-bearing page (sign-in, registration, profile, password reset, workspace forms, etc.) — the form builder migration is naming-only.
- Repeated 48-character touch-target string deleted from 3 places in connected_accounts, replaced by 3 short class composites.
- Magic-number `44px` deleted from 3 form builder constants, replaced by `var(--form-input-height)` reading from a named token.
- Future contributors landing in `connected_accounts/index.html.erb` see a clear, named structure (`.page-container`, `.action-group`, `.btn-touch-target btn-text btn-text-{danger,interactive}`) instead of long ad-hoc class strings.
- A single doc (`docs/design-system.md`) answers "what spacing should I use?", "is there a utility for this pattern?", and "where does the 44px touch-target live?"
- Touch-target height app-wide is changeable from one place (`_spacing.css`) — across `.btn-touch-target`, all 9 form-input field types, submit buttons, and file uploads.
- The next view migration (e.g., `app/views/sessions/new.html.erb`) becomes a 5-minute swap, not a design discussion.
