# UI style source-of-truth reconciliation — design

- **Date:** 2026-06-05
- **Status:** Approved (brainstorm complete) — ready for implementation plan
- **Scope:** Collapse the duplicated button/field style definitions in `modelrails_base` to one
  canonical CSS-class source each. Behavior-preserving (no visual change). App-only.

## Problem

The same button and field styling is currently defined in multiple hand-synced places that
will drift:

**Button — 3 copies:**
- `.btn-primary` / `.btn-secondary` / `.btn-danger` / `.btn-text*` — `app/assets/tailwind/application.css` (`@layer components`).
- `UI::ButtonComponent::VARIANTS` (raw utility strings) — `app/components/ui/button_component.rb`; its own comment says *"Reproduces the host app's .btn-* button system."*
- `TailwindFormBuilder::SUBMIT_CLASSES` (raw utility string, ≡ `.btn-primary`) — `app/form_builders/tailwind_form_builder.rb`.

**Field — overlapping definitions + dead code:**
- `UI::InputComponent::BASE/NORMAL/ERROR` and the FormBuilder's `FIELD_BASE/FIELD_NORMAL/FIELD_ERROR` are byte-identical (the component comment confirms it).
- `<select>` styling uses the raw `FIELD_BASE` constant (not a component).
- `.form-input` (`application.css`) is a *fourth*, visually distinct field look (flat `bg-surface`/`text-text-body`) used directly in ~32 files (chrome/inline controls).
- `TailwindFormBuilder#field_options` (lines ~200–211) is **orphaned dead code** — no caller routes through it.

**Consequence:** an agent (or human) choosing how to render a button/field sees several
valid-looking options that can silently diverge — and the gem-shipped agent-rules directive
("prefer a documented `UI::*` primitive over a hand-rolled utility stack") is not fully
truthful while the app itself hand-rolls `SUBMIT_CLASSES`/`FIELD_BASE` that duplicate both the
classes and the components.

## Decisions (resolved in brainstorming)

1. **Canonical source = the CSS class.** `.btn-*` / `.form-*` classes are the one definition;
   the component and FormBuilder *apply* them. Chosen because a CSS class applies uniformly to
   every Hotwire call site (`<button>`, `link_to`, `button_to`, `form.submit`) whereas a
   ViewComponent cannot wrap `form.submit`.
2. **App-only, intentional divergence.** Reconcile in `modelrails_base` only. The gem keeps its
   self-contained raw-utility components for vanilla hosts; `modelrails_base` is the
   token-owning host, so its copied components applying its own classes is the documented
   "adopt the app's superior implementation" pattern. One app PR.
3. **Two named field variants (no visual change).** Keep both field looks as two canonical
   classes: `.form-field` (raised, for form inputs) and `.form-input` (flat, for chrome/inline
   controls). Dedup each to one source; do not unify the looks.

## Design

### Buttons (3 → 1)

`.btn-*` in `application.css` stays canonical and unchanged. The other two copies apply it:

- **`UI::ButtonComponent`** — `VARIANTS` becomes class-name strings, and `FILLED`/`TEXT`
  constants are deleted. Verified 1:1 against current output:

  | variant | classes |
  |---|---|
  | `primary` | `btn-primary` |
  | `secondary` | `btn-secondary` |
  | `danger` | `btn-danger` |
  | `text`, `text_interactive` | `btn-touch-target btn-text btn-text-interactive` |
  | `text_danger` | `btn-touch-target btn-text btn-text-danger` |

  (`.btn-touch-target` + `.btn-text` reproduces the old `TEXT` constant; `FILLED` + per-variant
  color ≡ `.btn-secondary`/`.btn-danger`.) `coerce_variant`, the `destructive`→`danger` alias,
  `href`/`tag` handling, and `cn(...)` all stay.

- **`TailwindFormBuilder#submit`** applies `class: "btn-primary"` (merged with any caller
  `class:`); `SUBMIT_CLASSES` is deleted.

- The ~8 direct `class: "btn-primary"` call sites are already correct and **do not change**.

**Accepted consequence:** once the component applies an opaque `.btn-primary` class instead of
raw utilities, `cn`/tailwind-merge can no longer override an individual utility (e.g. a caller
passing `class: "bg-red-500"` no longer wins over the button's background). Callers add
non-conflicting utilities (`w-full`, `mt-2`) or pick a different variant. This is treated as a
feature (it enforces "don't hand-tune a primitive"), not a regression.

### Fields (two named variants, dedup each)

Introduce one new canonical class; keep the existing flat one:

```css
.form-field {
  @apply block w-full rounded-md border px-3 py-2 min-h-[var(--form-input-height)];
  @apply placeholder:text-text-muted focus:outline-none focus:ring-2;
  @apply border-border-strong bg-surface-raised text-text-heading focus:ring-interactive-focus;
  @apply disabled:cursor-not-allowed disabled:opacity-50;
}
.form-field[aria-invalid="true"] {
  @apply border-danger ring-2 ring-danger bg-danger-surface text-danger focus:ring-danger;
}
```

This equals the components'/FormBuilder's current `BASE` + `NORMAL` (+ `ERROR` via the
attribute selector) **exactly**, so every form input/select is pixel-identical. The error
appearance now follows the `aria-invalid` attribute the components already set — no separate
Ruby normal-vs-error branch.

- **`UI::InputComponent` / `UI::TextareaComponent`** apply `cn("form-field", @extra_class)` and
  keep setting `aria-invalid` when `invalid:`. Their `BASE`/`NORMAL`/`ERROR` constants are
  deleted. (Textarea/file components to be read during planning; same treatment.)
- **`UI::FileInputComponent`** → new `.form-file` class (the `file:*` styling currently in
  `FILE_FIELD_CLASSES`); component applies it. `.form-file` is canonical for file inputs.
- **`TailwindFormBuilder`** — `FIELD_BASE`/`FIELD_NORMAL`/`FIELD_ERROR`/`FILE_FIELD_CLASSES`
  deleted; `select_html_options` applies `.form-field` **and sets `aria-invalid="true"` on error**
  (parity check — DHH: verify input/textarea/file already do, then bring `<select>` in line so the
  `[aria-invalid]` error styling actually triggers for selects); the orphaned `field_options` method
  is **removed**.
- **`.form-input`** (flat, direct-use in ~32 files) is **unchanged** (kept, not renamed — avoids
  32-file churn; a CSS comment disambiguates it from `.form-field`).
- **Disabled-select micro-change (Adam, accepted):** `.form-field` includes
  `disabled:cursor-not-allowed disabled:opacity-50` (matching the component); the old `FIELD_NORMAL`
  used by `<select>` did **not**, so disabled selects *gain* that affordance. This is the one
  intentional pixel-difference — a consistency fix, not a regression. Verify it reads acceptably
  (opacity-50 on `bg-surface-raised`) in screenshot review.

### Tie-back to the agent-rules paradigm

This reconciliation exists to make the agent-rules truthful. During app-adoption of the
agent-rules generator, seed **`.modelrails_ui/house-rules.md`** with:

> Documented UI primitives here are **both** the `.btn-*` / `.form-field` / `.form-input` /
> `.form-file` classes **and** the `UI::*` components that wrap them. Reach for a named
> primitive; never hand-roll the `inline-flex … px-4 …` utility stack. `form.submit` /
> `link_to` / `button_to` → `.btn-*`; new component markup → `UI::*`.

(House-rules seeding lands with app-adoption; this spec only needs the wording to exist so the
adoption step can use it.)

## Scope boundaries (deliberately excluded)

Smaller-PR discipline — this PR is only the button/field reconciliation + its dead code + the
house-rules wording. **Not** bundled (separate tiny PRs): removing the unused `.bg-hue-interactive`,
and splitting `.prose`/Rouge syntax CSS into partials.

## Testing

Contract is **no visual change**. The gate is layered (panel decision: lean on existing real-CSS
coverage rather than build a bespoke compiled-CSS CI step):

1. **Component specs → class-name assertions.** The *current* `button_component_spec.rb` asserts
   individual utilities (`bg-interactive`, `hover:bg-interactive-hover`, …) — those **will break**
   once the component emits `class="btn-primary"`, so the plan rewrites them to assert the mapped
   class(es): `UI::ButtonComponent(variant: :primary)` → `btn-primary`; `UI::InputComponent(invalid: true)`
   → `form-field` + `aria-invalid="true"`; `UI::FileInputComponent` → `form-file`. Comment the
   input test to note the `aria-invalid` → `.form-field[aria-invalid]` CSS coupling it locks.
   (This asserts the component hands off to the right class — *not* that the CSS is correct.)
2. **Real-CSS visual gate = existing specs.** A class-name assertion can't catch a broken/deleted
   `.btn-primary` rule. That is gated by the **existing system + AAA-axe specs**, which render real
   pages through the *compiled* Tailwind — a button that lost its background fails axe contrast / the
   system expectation. These stay green; that's the actual "no visual change" enforcement.
3. **Screenshot review pre-push** — a form page + a `.btn-*` page, light and dark — for human
   confidence on pixel-parity (per the project's design-change workflow).
4. **Turbo Stream sanity** (Jorge): confirm a `.btn-primary` submit / `.form-field` input rendered
   inside a Turbo Stream response displays correctly — safe by construction (CSS arrives with the
   HTML; Turbo morphing doesn't re-run styles), documented so it isn't a surprise.

When manually probing compiled Tailwind, grep the **declaration value** (resolved `background-color`),
not the escaped selector, and run a positive control first. (A standing compiled-CSS CI check was
considered and deferred — the system+axe specs already exercise the real CSS.)

## Panel review refinements (2026-06-05)

Expert panel (Adam Wathan, Dave Thomas, DHH, Jorge Manrubia, Joël Quenneville, Léonie Watson;
Sandi Metz + Jim Weirich synthesis) **signed off on the architecture — 0 blockers.** Endorsed as
correct: CSS-class-canonical, the `aria-invalid`-driven error state, and the accepted tailwind-merge
override loss (treated as variant-discipline enforcement, not a regression). Incorporated refinements:

- **Pre-implementation call-site scan (DHH):** grep for `UI::ButtonComponent(... class: "<utility>")`
  call sites that rely on `cn`/tailwind-merge overriding a button utility (e.g. `class: "bg-…"`).
  Rewrite any to a `variant:` (or a non-conflicting utility like `w-full`). Document the small,
  in-app breaking change in the PR. Non-conflicting layout utilities (`w-full`, `mt-2`) still work.
- **Component docstrings (Dave):** update `UI::ButtonComponent` / `UI::InputComponent` docs so the
  stale "Reproduces the host app's .btn-* system" comment becomes "**applies** the app's `.btn-*` /
  `.form-field` classes; this copy intentionally diverges from the gem's self-contained version
  (token-owning host)."
- **CSS disambiguation comment:** in `application.css`, document the two field variants —
  `.form-field` (raised: `bg-surface-raised`, form-builder inputs/selects) vs `.form-input` (flat:
  `bg-surface`, inline/chrome controls). Names kept; comment carries the intent.
- **Léonie verify during implementation:** confirm `text-danger` on `bg-danger-surface` clears 7:1
  AAA (already CI-gated — double-check on a rendered error); and that focus moves to the
  `role="alert"` error summary on form re-render (best practice, not a blocker).

## Files touched

- `app/assets/tailwind/application.css` — add `.form-field` (+ `[aria-invalid]`) and `.form-file`; `.btn-*`/`.form-input` unchanged.
- `app/components/ui/button_component.rb` — VARIANTS → class names; delete `FILLED`/`TEXT`.
- `app/components/ui/input_component.rb`, `textarea_component.rb` — apply `.form-field`; delete `BASE`/`NORMAL`/`ERROR`.
- `app/components/ui/file_input_component.rb` — apply `.form-file`.
- `app/form_builders/tailwind_form_builder.rb` — `submit` → `.btn-primary`; `select_html_options` → `.form-field`; delete `SUBMIT_CLASSES`/`FIELD_*`/`FILE_FIELD_CLASSES`/`field_options`.
- `spec/` — parity render test.
