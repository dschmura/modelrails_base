# Docs reorg: user/developer audiences via markdowndocs directory routing — Design

**Date:** 2026-06-23
**Status:** Approved direction (brainstorm complete); ready for plan after user review.
**Depends on:** Phase C auth-docs (`docs/phase-c-auth-docs`) **merged first** — the reorg moves the exact docs Phase C rewrote, so it must build on the accurate content.

## Goal

Reorganize the `/docs` site (`app/docs/`) from a flat 30-doc set in 5 categories into markdowndocs 0.7.0+ **path-based audience routing** — a `user/` and `developer/` subdirectory split plus shared root — so the catalog reads coherently for its two hats, and retire the deprecated `audience:` frontmatter + the `-technical` filename suffix.

## Audience model (decided in brainstorming)

The template's `/docs` has essentially **one reader — the forker** — wearing two hats:

- **`user/`** = the *feature & behavior reference*: "how the app works from the user's side" (auth, invitations, accounts, notifications, workspaces). Read by forkers to understand what they ship, and reusable as the seed for a fork's own help center. **Default mode.**
- **`developer/`** = internals / build / configure / extend / operate.
- **root** = shared entry/help docs visible in both modes.
- **Contribution docs are out of scope** for `/docs` — they live in the README, per standard OSS practice. Literal end-user help for a *deployed fork* is the fork's job (it customizes the UX), not the template's.

`config.modes = %w[user developer]`, `config.default_mode = "user"`. The mode switcher labels read "User guide" / "Developer guide".

## Section 1 — Audience mapping (single-home; 30 existing + 2 carved = 32)

**`root/` (shared):** `getting-started`, `troubleshooting`

**`user/` (feature & behavior — 11):**
`accounts` · `workspaces` · `projects` · `onboarding` · `clientside` · `project-tools` · `notifications` · `emails` · `application-flows` · **`authentication`** (new) · **`invitations`** (new)

**`developer/` (internals/build/operate — 19):**
`presets` + 4 spokes (`presets-solo`, `presets-single-tenant`, `presets-open-saas`, `presets-none`) · `architecture` · `extending` · `forking` · `components` · `ui-patterns` · `accessibility` · `background-jobs` · `deployment` · `security` · `qa-flows` · `identity-system` · `accounts-and-identity` · `notifications` (from `notifications-technical`) · `passkeys`

Notable placements (judgment calls confirmed in brainstorming):
- `presets` (×5) → `developer` (a forker build-time decision, not user behavior).
- `passkeys` → `developer` (current doc is RP-config + local-HTTPS + troubleshooting = operator-facing).
- `notifications` pair → `user/notifications` + `developer/notifications` (the `-technical` suffix retires; folder conveys it).
- `application-flows` → `user`.
- `accounts-and-identity` + `identity-system` → `developer`; flagged as **consolidation candidates** with `accounts` (deferred content cleanup, not part of this reorg).

**Carved-from-existing new user docs** (assembled from scattered current material — `accounts`/`passkeys`/`emails`/`workspaces` + the merged Phase C content):
- `user/authentication` — how signing in works (passwordless magic link + passkeys + OAuth), from the user's perspective.
- `user/invitations` — accepting/declining a workspace, project, or client invitation.

## Section 2 — Category structure (one `config.categories`, path-prefixed slugs; index filters by mode)

**`user` mode:**
- **Getting Started** — getting-started *(root)*
- **Accounts & Authentication** — authentication · accounts
- **Workspaces & Collaboration** — workspaces · projects · invitations · onboarding · clientside
- **Features** — notifications · emails · project-tools · application-flows
- **Troubleshooting** — troubleshooting *(root)*

**`developer` mode:**
- **Getting Started** — getting-started *(root)*
- **Presets (Tenancy)** — presets + 4 spokes
- **Architecture & Data Model** — architecture · accounts-and-identity · identity-system
- **Building & Extending** — extending · forking · components · ui-patterns
- **Operations** — deployment · background-jobs · security
- **Quality & Testing** — accessibility · qa-flows
- **Auth & Notifications (internals)** — passkeys · notifications
- **Troubleshooting** — troubleshooting *(root)*

## Section 3 — Migration mechanics (HYBRID)

1. **Reference copy.** Copy the merged `app/docs/` → untracked `working_files/docs-reference/` for side-by-side viewing while building. (Copy, not move — `/docs` and git history stay intact.)
2. **`git mv` the developer docs** into `app/docs/developer/` (preserve history; clean rename diff). Light edits only: drop `audience:` frontmatter, fix cross-links. (`notifications-technical.md` → `developer/notifications.md`.)
3. **Rebuild the user docs** from the reference into `app/docs/user/`: move the 9 existing behavior docs, refocus framing where needed, and carve `authentication` + `invitations` fresh. (`notifications.md` → `user/notifications.md`.)
4. **Root:** leave `getting-started.md` + `troubleshooting.md` at `app/docs/` root.
5. **Config:** rewrite `config/initializers/markdowndocs.rb` — `config.modes`, `config.default_mode = "user"`, the path-prefixed `config.categories` from Section 2, switcher labels.
6. **Deep content-refocus is incremental** ("refactor as we go") — this reorg lands the IA + the two carved docs; per-doc behavior-refocus of the `user/` set can follow.

## Testing / verification

- `spec/docs/index_coverage_spec.rb` — every doc appears in exactly one category; update for path-prefixed slugs + the 2 new docs.
- `spec/docs/application_flows_svg_spec.rb` — update the glob (flows moves to `app/docs/user/`).
- `spec/docs/auth_docs_accuracy_spec.rb` — keep green (paths shift).
- A render/route check: mode-scoped docs serve at `/docs/<mode>/<slug>`; root docs at `/docs/<slug>`; the mode switcher shows the right doc.
- `rake markdown:check` clean; full suite green; AAA (CI) for any doc-page chrome touched.

## Cross-links & redirects

- Sweep internal `/docs/<slug>` links to their new `/docs/<mode>/<slug>` (or root) paths.
- **Redirects:** add a small redirect map for the old root URLs that move under a mode (e.g. `/docs/architecture` → `/docs/developer/architecture`), so existing bookmarks/external links don't 404. (Decide scope during planning — at minimum the most-linked docs.)

## Out of scope / deferred

- **Deep content-refocus** of each `user/` doc to a pure behavior voice (incremental, post-reorg).
- **Consolidating** `accounts` / `accounts-and-identity` / `identity-system` (content cleanup; flagged, separate).
- **Literal end-user help** for deployed forks (the fork's responsibility).
- **Contribution docs** (README, not `/docs`).

## Risks / notes for the plan

- **Phase C must merge first** (prerequisite). The reorg branch rebases onto post-Phase-C main before implementation, so it moves the corrected docs and `user/authentication` is carved from accurate auth material.
- markdowndocs 0.7.0 path-routing + 0.9.0 (`~> 0.9`, already pinned by Phase C) are the gem floor — both land via the Phase C merge.
- The reorg touches `working_files/` (untracked) — confirm it's gitignored so the reference copy never commits.
