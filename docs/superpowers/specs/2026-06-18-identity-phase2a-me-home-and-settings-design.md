# Identity Phase 2a — `/me` home + `/account → /settings` move (Design Spec)

**Status:** Draft for review (not yet a plan)
**Date:** 2026-06-18
**Scope:** modelrails_base (template)
**Continues:** `docs/superpowers/specs/2026-06-18-identity-account-model-clarity-design.md` — this is the first concrete Phase 2 slice (the gating piece). Phase 0/1 shipped in PR #350.

---

## Decisions (confirmed 2026-06-18)

1. **`/me` home is thin** — an identity card (avatar + name + "Edit in Settings") + a "Your workspaces" list + a link to `/settings`. Forks flesh it out.
2. **Topology = split, siblings** — `/me` (home) and `/settings` (hub) are two top-level paths. `/account/*` → `/settings/*` (straight rename). No template redirects (a production fork adds temporary `/account/*` redirects at cutover).
3. **`/me` links to existing hubs** (`account/avatar#hub`, `workspaces#identity_picker_hub`) — it doesn't duplicate them.
4. **`/settings` = wholesale rename** of `namespace :account` — all 9 resources move together.

## What `/me` is (and isn't)

`/me` earns its place as **two things at once**: the identity **hub** every fork gets, *and* the **landing** a `:none` fork points `authenticated_home_path` at. It is account-independent — reachable from any context, safe when `Current.workspace` is nil.

- It does **not** change the `:personal` default landing — `authenticated_home_path` stays `root_path`; `:none` forks override it to `me_path` (that override already exists in the fork; after this, `me_path` exists in the template too).
- It is **thin** by design — a launchpad, not a dashboard.

## The `/me` home

- **Route:** `resource :me, only: [:show]` → `MeController#show`, `me_path`.
- **View:** identity card (`Current.user` avatar + name + "Edit in Settings" → `edit_settings_profile_path`) · "Your workspaces" (`Current.user.workspaces`, each with name + the user's role + a link) · a prominent link to `/settings`. Workspace-agnostic.
- **Pundit:** `show?` = signed-in (your own `/me`); no workspace authorization (it's identity-scoped).
- **a11y:** AAA; "Your workspaces" is a labeled nav list; works with zero workspaces (`:none`).

## The `/account → /settings` move

- `namespace :account` → `namespace :settings` (routes); `Account::` → `Settings::` (controller module); `app/views/account/*` → `app/views/settings/*`.
- **9 resources move together:** `profile`, `password`, `avatar` (+`hub`), `theme_preference`, `notification_preferences` (+`dismiss_banner`), `preferences/timezone`, `connected_accounts` (+`verify/:token`), `email_confirmation`, `notifications`.
- **Mailer touch:** the `connected_accounts` `verify/:token` link (email-ownership verification, `config/routes.rb:39`) becomes `/settings/connected_accounts/verify/:token` — find and update the mailer/template that emits it.
- **Redirects:** none in the template (clean move — one pre-launch fork). Documented note: a production fork adds temporary `/account/* → /settings/*` redirects at cutover, removed once outstanding email links expire.

## Sequencing — two safe sub-slices

- **2a-1 — the `/me` home** (purely additive: new route + `MeController` + thin view + specs; no move). Ships value immediately, near-zero risk, and gives `:none` forks a template-owned `me_path`.
- **2a-2 — the `/account → /settings` rename** (the mechanical move + the mailer link + i18n keys). Bigger, but isolated.

Recommend **2a-1 first**, then 2a-2.

## Open questions to confirm before a plan

1. **i18n keys:** rename the `account.*` locale keys → `settings.*` (consistent, bigger sweep) — or keep the keys and only move routes/controllers/views? *(Rec: rename for honesty.)*
2. **`/me` contents:** strictly identity + workspaces (thin), or also a notifications summary? *(Rec: thin — notifications stay at `/settings/notifications`.)*
3. **Redirect stance reconfirm:** template ships zero `/account/*` redirects, correct? *(Rec: yes — clean move; the fork is pre-launch.)*

## Non-goals (later Phase 2 slices)

- The **switcher component** (header dropdown, two variants — harvest the IA-brief guidance). Phase 2b.
- `personal: → owner_created` **column migration** — separate, triggered.
- The **context banner** ("You're in [X]") — lands with the switcher.
- The 3 deferred **settings-sidebar copy** strings — with the sidebar restructure.
