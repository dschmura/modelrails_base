# Design: modelrails_ui component system — guided, guard-railed, propagating

**Date:** 2026-06-01
**Status:** Proposed (design approved in brainstorming; pending written-spec review)
**Spans two repos:** `modelrails_ui` (the gem) and `modelrails_base` (template + reference app)

## Goal

Give downstream developers a **consistent, ergonomically efficient way to build features
without compromising style or accessibility**. Concretely:

1. A developer who needs a UI primitive can **discover it**, see it "in full accessible
   beauty," and get **copy-paste implementation guidance**.
2. Using a component **as prescribed** yields accessible, on-brand output automatically
   (correct-by-construction).
3. **Guardrails** catch using a component *poorly*.
4. When a component improves, the improvement **propagates** — within an app (every call
   site updates) and across apps (future and existing apps can pull it forward) — **unless
   a downstream dev has explicitly overridden it.**

## Principles

- **Correct-by-construction.** Accessibility and styling live *inside* the component, not
  at the call site. The prescribed usage is the accessible usage.
- **Propagate unless overridden.** Improvements flow from the gem to apps; per-call-site
  and per-app overrides survive.
- **Dev-only, no runtime gem dependency** (non-negotiable, carried from the original
  adoption). Production loads only `view_component` + the vendored components. Everything
  the gem contributes is either *generated Ruby in your own file* or *dev/test-only tooling*.
- **Boundary vs. usage guardrails** (the organizing distinction — see Architecture).

## Topology (two layers)

- **Layer 1 — intra-app:** within a single app, a component is the single source of its
  own behavior; improving it updates every call site. Enforced by the app against its own
  code/pages/tokens.
- **Layer 2 — cross-app:** `modelrails_ui` is the shared source. Component improvements
  (and their docs/guardrails) propagate to apps via generation + an `:update` tool.

## Architecture: division of labor (gem vs. app)

The deciding test: **a guardrail/asset is intrinsic → gem; contextual → app.**

| Concern | Authored in | Runs/lives in | Rationale |
|---|---|---|---|
| Component behavior + **API hardening** (validate variant/enum + required props; fail-loud in dev, safe fallback in prod; a11y baked so it can't be silently dropped) | **Gem** (component `.rb.tt` templates) | App (vendored `app/components/ui/*`) | Intrinsic to the component; travels with it; an unknown variant must fail identically everywhere. Pure Ruby in the app's own file → no runtime dep. |
| **Teaching catalog** (Lookbook scenarios for every state/variant; prescribed-usage snippet; "when to use / when not"; the a11y contract; a "Don't" example) | **Gem** (lookbook preview templates) | App (Lookbook at `/lookbook`, dev-only) | A component's documentation should ship with the component. App layers on app-specific notes. |
| **Source lints** (hardcoded non-token colors; unambiguous component-bypass) | **Gem** ships the *rule/cop*; **App** owns the *config* | **App** (pre-commit/CI) | Lints check the *downstream dev's* code and need app-specific inputs (the app's semantic tokens; which primitives the app mandates). |
| **axe AAA gate** (outcome backstop, both themes) | **Gem** can share the *harness*; **App** writes the *specs* | **App** (system specs) | Only the app has rendered pages to audit. |
| **Propagation engine** (`modelrails_ui:update` 3-way merge) | **Gem** (generator + tooling) | Run in the app (dev) | The gem is the source; the tool reconciles new gem output with the app's vendored copy. |

**Why this keeps the gem dev-only:** every gem contribution is either (a) *generated Ruby
that becomes the app's own vendored file* (validation is just code in your file — no
`require "modelrails_ui"` at runtime), or (b) *dev/test-only tooling* (generators, RuboCop
cops, the Playwright/axe harness) that never loads in production.

## Developer experience (the "guided showroom")

The leverage is discovery + prescribed usage, not call-site terseness.

1. Dev needs a primitive → opens **Lookbook** (`/lookbook`).
2. Sees the component in every state "in full accessible beauty," reads the **a11y contract**
   (what it guarantees vs. what the dev must supply), and copies the **prescribed usage snippet**.
3. Pastes it. Output is accessible + on-brand by construction.

**Canonical access layer (per category — formalizes what already works):**

- **Form inputs** → `TailwindFormBuilder` (`f.text_field`, `f.text_area`, `f.file_field`).
  Already delegates to `UI::Input/Textarea/FileInput`. The builder owns label/help/error/ARIA.
- **Model-aware presentational** → helpers (`avatar_for`). Already delegates to `UI::AvatarComponent`.
- **Standalone primitives** → the generic `ui` helper: `ui :button, "Save", variant: :primary`
  (renders the named `UI::*` component, forwarding args; unknown name raises — a boundary
  guard). One ~5-line dispatcher covers every component, never drifts, and keeps the component
  class an implementation detail. Lookbook teaches this call (its previews call `ui`), so the
  catalog and call sites match. Chosen over `render UI::X.new(...)` (leaks the class, verbose)
  and over per-primitive named helpers (N to maintain, drift-prone).

**Buttons specifically (the worked example):**

- `UI::ButtonComponent` is the prescribed way for **new standalone buttons/links**
  (`render UI::ButtonComponent.new("Save", variant: :primary)` / `href:` → `<a>`).
- The `.btn-*` CSS `@layer` **stays** as the shared style vocabulary, because the correct
  Rails idioms for the majority of existing call sites are **`f.submit`** (form submit; the
  builder already applies primary styling) and **`button_to`** (CSRF form actions) — neither
  is a `UI::ButtonComponent` use case. `.btn-*` is the right, concise tool there.
- **Single source of truth for button styling** is guarded by the existing
  `button_component_spec` ("app `.btn-*` parity"): it asserts the component reproduces the
  `.btn-*` classes, so the two representations can't silently drift.
- **No broad call-site migration.** (Confirmed by inspection: 7 of 9 `.btn-*` sites are
  `f.submit`/`button_to`; the other 2 would only swap a concise class for verbose utilities.)

## Guardrails (by layer, cheapest → strongest)

1. **API hardening (gem, boundary).** Each component validates inputs:
   - Unknown `variant`/enum → raise `ArgumentError` in `development`/`test`; safe fallback
     (current behavior: primary) in `production`. *Today an unknown variant silently falls
     back — this is the high-leverage change.*
   - Required props enforced (e.g., a primitive that needs a name/label).
   - A11y attributes are computed internally and can't be silently dropped by the caller
     (e.g., the avatar always emits `alt`; an icon-only button without an accessible name is
     flagged — see "Don't" docs + dev warning).
2. **Lookbook "Don't" examples (gem, teaching).** Each component page shows the common
   misuse and *why* it's wrong, next to the prescribed usage.
3. **Targeted source lints (gem rule + app config, usage).** Small, high-signal, low-false-
   positive only: hardcoded non-token colors; unambiguous component-bypass (e.g., a raw
   `<dialog>`). Deliberately **not** broad (no "flag every `<button>`") — noisy lints erode trust.
4. **axe AAA gate (app, outcome).** Existing Playwright + axe-core `wcag2aaa`, both themes,
   already gates rendered pages. Formalized here as the outcome-level guarantee.

## Propagation model

- **Intra-app (automatic):** call sites render the component; improving the vendored
  component updates every site. Per-call-site override via `class:`/props merged through `cn`
  (override wins).
- **Cross-app (`modelrails_ui:update`):** a generator regenerates components/previews and
  performs a **3-way merge** — base = the gem version last generated into this app, theirs =
  the new gem version, mine = the app's current vendored file. Clean changes apply silently;
  divergences surface as git-style conflicts for the dev to resolve. Requires the gem to
  record a per-component "last generated" baseline (e.g., a manifest with version/digest).
- **Override semantics:** a per-app customization is just a local edit; the 3-way merge
  preserves it (or conflicts if the gem changed the same lines), exactly like a rebase.

## Error handling

- **Component boundary:** raise in dev/test on invalid input (loud, early); degrade safely
  in production (never 500 a page over a bad variant).
- **`:update` merge:** non-interactive-safe; write conflict markers + a summary of
  conflicted files; never silently overwrite a diverged file.

## Testing strategy

- **Component specs** (per component, in the app): markup/ARIA/parity contracts (exist for
  the 6 components).
- **Parity specs**: `button_component_spec` etc. keep component output == `.btn-*`/builder
  styling (drift guard).
- **API-hardening specs**: invalid variant raises in test; required-prop enforcement; a11y
  invariants hold.
- **axe AAA system specs** (app): unchanged backstop, both themes.
- **Lint specs** (gem): each cop has positive/negative fixtures.
- **`:update` tooling specs** (gem): clean apply, local-edit-preserved, conflict-surfaced.

## Decomposition into buildable sub-projects (recommended order)

Each gets its own spec → plan → implement cycle.

- **SP1 — API hardening pattern + buttons pilot.** Harden `UI::ButtonComponent` (validate
  variant, dev-raise/prod-fallback) in the gem template; regenerate into the app; add
  hardening specs. Establishes the boundary-guardrail convention on one component. *(Smallest,
  highest-leverage; proves the pattern.)*
- **SP2 — Lookbook teaching catalog.** Enrich the gem's preview templates for all 6
  components: every state, prescribed-usage source, when-to/when-not, a11y contract, a "Don't".
  Regenerate; the app's `/lookbook` becomes the guided showroom.
- **SP3 — App-side guardrails.** The hardcoded-color cop + one component-bypass cop (gem
  ships rule, app configures with its tokens/adoption); wire into Lefthook/CI; formalize the
  axe AAA harness as shared support.
- **SP4 — `modelrails_ui:update` propagation engine.** The 3-way-merge generator + baseline
  manifest. *(Largest, most novel; the manual version-bump-and-regenerate flow — as used for
  v0.1→v0.2 — is the interim until this lands.)*
- **Cross-cutting — conventions doc** for downstream devs (likely `app/docs/` + gem README):
  the "use X for Y" map, the override rules, how to run `:update`.

## Open questions / risks

- **`:update` baseline tracking** (SP4): where the per-component last-generated version/digest
  is recorded, and the merge UX. Biggest unknown.
- **Hardening rollout**: dev-raise on unknown variant could surprise existing apps on update;
  gate behind the version bump + changelog.
- **Two-repo coordination**: most authoring is gem-side; the app consumes via generate/update.
  Implementation plans must target the correct repo per sub-project.
- **Icon-only-button accessible-name enforcement**: how loud (raise vs. dev-warn) without
  false positives.
