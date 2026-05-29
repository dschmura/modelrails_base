# Design: Split `presets.md` into a hub + per-preset pages

**Date:** 2026-05-29
**Status:** Approved (pending spec review)
**Scope:** Documentation information architecture only. No application code changes.

## Motivation

`app/docs/presets.md` has grown to ~270 lines covering three presets (Solo-default ~53 lines, Single-tenant ~80, Open SaaS ~98) plus shared concepts. As each preset's documentation deepens, a single page will overwhelm a reader who only needs one preset.

This framework is reused by the same developer across multiple projects, each potentially on a different preset. The dominant access pattern is therefore: **a returning developer jumping straight to "how do I stand up *this* preset"** — not reading the whole page top to bottom. The IA should serve both the first-time reader comparing options (serial) and the returning reader referencing one preset (jump).

## Key decisions

1. **Granularity:** A hub page + three self-contained spoke pages (one per preset).
2. **Hub/spoke boundary — hybrid by content-type:**
   - Preset-*agnostic* concepts live in the hub, linked (not duplicated) from spokes.
   - Each spoke is *self-contained* for its own setup + behavior — a returning dev stands up their preset from one page without bouncing.
   - Deep machinery (`Workspace#admit`, the `Tenanted` concern, membership-grant internals) is *architecture*, not preset docs — spokes link to `architecture.md` / `extending.md` rather than copy it.
3. **Vocabulary (consistency = discoverability):** the word "preset" is used for the category, the filenames, and the slugs. No parallel "app shapes" term.
4. **Presets are alternatives, not a sequence.** No prev/next between spokes (it would imply a false ordering). The hub is the comparison surface; each spoke flows onward to `extending`.

## File structure

```
app/docs/
  presets.md                 # HUB — "App Presets" (keeps the canonical /docs/presets slug)
  presets-solo.md            # "Solo-default"
  presets-single-tenant.md   # "Single-tenant"
  presets-open-saas.md       # "Open SaaS"
```

The hub keeps the `presets` slug, so existing inbound links (`getting-started` → `/docs/presets`) do not break.

## Content map

### Hub — `presets.md`

- What a preset is (always multi-tenant at the data layer; the four configuration knobs)
- The **decision matrix** table — doubles as the *jump table*: each preset name links to its spoke
- "Quick decision" chooser (links to spokes)
- **"Switching presets is a migration"** — the one cross-cutting caveat; lives here, spokes link to it
- Next steps: → your chosen spoke, → `extending`

### Spoke — `presets-solo.md` ("Solo-default")

- What it is / who it's for · knob table (Solo values) · "ships by default"
- The three behaviors worth knowing (personal hidden from switcher; email-bound invitations; `generates_token_for` verification)
- Verification (console + browser)
- "When to switch away" → links to the other two spokes

### Spoke — `presets-single-tenant.md` ("Single-tenant")

- What it is / who it's for · knob table
- Setup steps: ENV table **including `APP_HOST`**, `bin/setup`/seed, **Letter Opener** note (dev email capture), `bin/rails tenancy:owner_setup_link`
- **`:shared` role-reconciliation** note (re-admitting an existing member updates their role)
- Verification (console + browser)
- "When to switch away"

### Spoke — `presets-open-saas.md` ("Open SaaS")

- What it is / who it's for · knob table
- **Signup posture — pick one** (fully-public vs controlled-growth) + the `SIGNUP_MODE`-is-not-how-you-get-an-admin callout + the **two-knobs-are-independent** note
- Setup (Flow A — existing user; Flow B — new user via link)
- Key behaviors · verification
- **Tightening the allowlist on a live app** + the **reset command**
- "When to switch away"

### Linked, never duplicated

`Workspace#admit`, `Tenanted`, membership-grant internals → `architecture.md` / `extending.md`. Spokes link out; they do not restate.

## Navigation

- **Hub → spokes:** decision-matrix rows and the "Quick decision" bullets link to each spoke.
- **Spoke → hub:** a one-line breadcrumb at the top (`App Presets › Single-tenant`).
- **Spoke → onward:** each ends with "Next: [Extending](/docs/extending)" and "‹ Compare all presets" (back to the hub).
- **No prev/next between spokes** — they are alternatives.
- All internal links use the absolute `/docs/<slug>` form (never a `.md` suffix, which the engine rejects with 406).

## Docs-engine integration

- **New "Presets" category** in `config/initializers/markdowndocs.rb` containing `[presets, presets-solo, presets-single-tenant, presets-open-saas]`.
  - The `/docs` index groups the four together.
  - The related-docs sidebar (category-based) auto-cross-links the four, so a returning dev hops between presets without returning to the index.
- `presets` is **removed from "Getting Started"** and moves to "Presets." `getting-started` stays in "Getting Started"; the explicit body link (`getting-started` → "choose your app preset") remains the bridge.
- The `spec/docs/index_coverage_spec.rb` orphan guard will fail until all three new docs are categorized — built-in safety that they don't go unlinked.

## Migration approach

- Content is **moved, not rewritten.** Every line from the prior preset work (#201, #205, #206, #208) is preserved and relocated — no re-litigating settled wording.
- Front-matter (`title`, `description`, `keywords`, `audience`) is authored per spoke, mirroring the existing convention.

## Testing / verification

- `rake markdown:check` passes.
- `spec/docs/index_coverage_spec.rb` green (all four docs categorized, no stale slugs).
- Link-target check: `curl` each `/docs/<slug>` (hub + 3 spokes) → HTTP 200, and grep the docs for any `]( ...md)` relative links (must be none).
- Full RSpec suite green (docs-only change; no behavior impact expected).

## Out of scope

- No application/model/controller changes.
- No changes to `getting-started.md` / `extending.md` / `architecture.md` beyond the hub→spoke link updates already described.
- The deferred typed-errors `admit` refactor and Reshape 3 strategies are unrelated and untouched.
