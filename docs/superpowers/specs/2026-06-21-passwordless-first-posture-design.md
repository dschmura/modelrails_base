# Passwordless-First Posture — Design (Phase A)

**Date:** 2026-06-21
**Status:** Approved (brainstorming complete; ready for implementation plan)
**Arc:** This is **Phase A** of a three-phase passwordless arc:

- **A — Passwordless-first posture** *(this spec)*: magic-link (+ OAuth) is the default and only signup; password becomes a settings-only opt-in; magic-link is the universal recovery.
- **B — Passkeys (WebAuthn)**: add a `webauthn` tile to the existing `Authentication` provider axis — primary returning-login, magic-link as recovery. *(separate spec)*
- **C — Docs**: update the Application Flows wireframe + auth docs to the new default, and fold in the markdowndocs click-to-expand wiring. *(separate spec)*

## Goal

A user can create an account and sign in **without ever setting a password**. Email (magic-link) and OAuth are the default and only paths surfaced at signup and sign-in. A password is an explicit opt-in managed only in settings, and is never required. Recovery for everything — including a forgotten password — flows through the single hardened `MagicLinkToken` primitive.

**Driving constraint (user's words):** "avoid storing passwords on our system if it can be avoided." Passwordless-first (not passwordless-only): passwords remain a complete, supported, but deemphasized opt-in.

## Current state (grounded)

The app is already ~80% passwordless. Relevant facts, with evidence:

- `users.password_digest` is **nullable**; `has_secure_password validations: false`; password validation runs only `if password.present?` (`app/models/user.rb`). OAuth and magic-link users already exist with no password.
- Three auth methods converge on a custom `Session` + `Current.user` (`app/controllers/concerns/authenticatable.rb`).
- **`SessionsController#lookup`** (`app/controllers/sessions_controller.rb:28`) is the email-first entry: `has_password?` → `password_form`; existing no-password user → magic-link sign-in; new email → magic-link registration.
- **`SessionsController#create`** (`:10`) is password sign-in (email + password). Handles `locked?`, `register_failed_login!`.
- **`RegistrationsController`** (`app/controllers/registrations_controller.rb`) is the **password** signup. It alone does two edge-case jobs: enforces `signups_open?`, and parks `session[:pending_invitation_token]` + `session[:pending_join_token]` onto the email `Authentication` (`:33`) for consumption after email verification.
- **`MagicLinkToken`**: 15-min, single-use, race-safe (partial unique index + atomic `consume!`).
- Routes today (`config/routes.rb`): `resource :session`, `resource :registration` (new/create), `resources :passwords, param: :token` (public reset), `resource :magic_link`, `magic_link_callback` (show/create), `post session/lookup`, OAuth callbacks, `namespace :settings { resource :password, only: [:new, :create] }`.
- `settings/password` already has `new` + `create` (opt-in set-password); pwned-check lives here.
- Email verification is **soft** / non-blocking; magic-link & OAuth users are verified on arrival.

## Decisions (locked during brainstorming)

| Area | Decision |
|------|----------|
| Entry | Single email-first screen (`sessions#new`) serves sign-up **and** sign-in, plus OAuth buttons |
| Login default | `lookup` always sends a magic-link; if the user `has_password?`, the `check_email` screen offers a secondary **"use your password instead"** → `password_form` → `sessions#create` |
| Signup | New email → magic-link registration. The password signup (`RegistrationsController` + `registrations/new`) is **removed** |
| Password | Settings-only opt-in: **add** and **remove** a password in `settings/password`; pwned-check stays here; never required, never at signup |
| Recovery | "Forgot password?" stays, **backed by magic-link** (one recovery primitive) → lands on "set a new password". The dedicated reset-token flow (`PasswordsController` + `resources :passwords`) is **removed** |
| Must move, not lose | `signups_open?` gate and pending invitation/join-link claims must move onto the magic-link registration path; magic-link/OAuth users stay auto-verified |
| Untouched | OAuth; `sessions#create` (now the secondary password login); lockout/rate-limit (now scoped to the secondary password path); `MagicLinkToken` mechanics |

## Architecture & components

### 1. Single email-first entry (`sessions#new` + `lookup`)

`sessions/new` is the only door. One email field POSTs to `session_lookup`. OAuth buttons (`shared/_oauth_buttons`) remain. The "Create account" CTA anywhere in the app points here (no separate signup page).

**`lookup` reshape** (`sessions_controller.rb:28`):

- New email **and** `signups_open?` → create registration `MagicLinkToken`, send `registration_link`, render `check_email`.
- New email **and** signups closed → render the closed state (same content `RegistrationsController#closed` renders today), status `:unprocessable_entity`. *(This is the moved `signups_open?` gate.)*
- Existing user → create sign-in `MagicLinkToken`, send `sign_in_link`, render `check_email`. **No longer auto-routes to `password_form`.**
- On the `check_email` view, when the looked-up user `has_password?`, render a secondary **"Use your password instead"** link to `password_form` (carrying the email). This is the only place the password form is reachable.

### 2. Magic-link registration carries the moved responsibilities (`magic_link_callbacks#create`)

When a registration magic-link is consumed and the `User` + email `Authentication` are created, this path must now also:

- Re-check `signups_open?` (defense-in-depth; the token could outlive a posture change) and refuse if closed.
- Consume the pending **invitation** and **open-link-join** claims. Because the magic-link *proves email ownership at click time*, these are consumed **immediately** at the callback (no deferred email-verification step) rather than parked on the `Authentication`. The claims are read from the session (as today) — `session[:pending_invitation_token]`, `session[:pending_join_token]` — and applied, then cleared.

This is the single highest-risk part of Phase A: invitation/open-link acceptance for brand-new users currently rides the password registration path; it must ride the magic-link path after this change. It is covered by an explicit system spec (below).

### 3. Password as settings-only opt-in (`settings/password`)

- Keep `new`/`create` (add a password; pwned-check stays).
- Add a **`destroy`** (remove password) so the opt-in is reversible — a user can return to fully passwordless. Route becomes `resource :password, only: [:new, :create, :destroy]`.
- The settings UI surfaces "Add a password" when `!has_password?` and "Remove password" when `has_password?`.

### 4. Forgot-password → magic-link → set-new-password (return-intent)

"Forgot password?" appears on `password_form`. It triggers the magic-link sign-in path, but the resulting magic-link must land the user on the **set-a-new-password** screen (`settings/password#new`) instead of the default post-auth home.

**Mechanism — return-intent on the token.** Add a nullable `return_to` (or `intent`) attribute to `MagicLinkToken` (a server-controlled enum/path, never a raw user-supplied URL — avoids open-redirect). `create_for_email` accepts an optional intent; the callback, after `start_new_session_for`, redirects to the intent's path (here, `new_settings_password_path`) or falls back to `after_authentication_url`. Forgot-password sets `intent: :set_password`.

### 5. Removals

| Removed | Absorbed by |
|---------|-------------|
| `RegistrationsController`, `app/views/registrations/*`, `resource :registration` | `sessions#new` single entry + magic-link registration |
| `PasswordsController`, `app/views/passwords/*`, `resources :passwords` | "Forgot password?" → magic-link (intent: set_password) |
| "Forgot password?" pointing at the reset-token flow | Same link, now magic-link-backed |

`sessions#create`, `password_form`, `check_email`, `email_error` are **kept** (the secondary password login + its supporting views).

## Data flow

**Sign up (new email):** `sessions#new` → `lookup` → (signups_open?) → registration `MagicLinkToken` → email → `magic_link_callback#show`/`create` → create User + verified email `Authentication` → consume pending invitation/join claims → `start_new_session_for` → home.

**Returning sign-in (passwordless):** `sessions#new` → `lookup` → sign-in `MagicLinkToken` → email → callback → session → home.

**Returning sign-in (password opt-in user):** `lookup` → `check_email` (magic-link sent) **and** a "use your password instead" link → `password_form` → `sessions#create` (lockout/rate-limit apply) → session → home.

**Forgot password:** `password_form` → "Forgot password?" → magic-link with `intent: :set_password` → email → callback → session → redirect to `settings/password#new`.

## Error handling & security

- Open-redirect: the return-intent is a server-side enum mapped to a fixed path, never a user-supplied URL.
- Token reuse/expiry unchanged (15-min, single-use, race-safe `consume!`).
- `signups_open?` enforced at **both** `lookup` (fast feedback) and the callback (defense-in-depth).
- Rate-limit: `lookup` is already rate-limited (`sessions_controller.rb:5`); the magic-link send path stays within it. `sessions#create` keeps its password rate-limit + lockout.
- Account lockout (`failed_login_attempts`, `locked_at`) remains meaningful only for the secondary password login; magic-link/OAuth bypass it (no shared secret to brute-force).
- Pwned-check stays on `settings/password#create` (the only place a password is set).

## Testing strategy (TDD, system-level where it counts)

Behavior, not implementation. Request/system specs:

1. New user signs up via magic-link (no password field anywhere in the flow).
2. Returning passwordless user signs in via magic-link.
3. Password opt-in user: `check_email` shows "use your password instead"; the password path still authenticates via `sessions#create`.
4. **Invitation acceptance through magic-link registration** — a brand-new invited user lands a workspace `Membership` after clicking the magic-link (claim consumed at callback).
5. **Open-link-join through magic-link registration** — analogous to (4) for the join-link claim.
6. **Signups-closed blocks magic-link registration** — `lookup` for a new email renders the closed state; the callback also refuses.
7. Forgot-password → magic-link → lands on set-new-password; submitting sets the password; subsequent password login works.
8. Settings: add a password, then remove it (`destroy`) → `has_password?` flips back to false; passwordless login still works.
9. Removed routes (`new_registration_path`, `passwords` reset) no longer exist (routing specs / 404).
10. Full suite green; AAA both themes proven in CI (entry, check_email, password_form, settings/password).

## Out of scope (this phase)

- Passkeys / WebAuthn (Phase B).
- Docs/wireframe updates + click-to-expand wiring (Phase C).
- Migrating existing password users (none in a template; no data migration needed beyond the `MagicLinkToken` return-intent column).
- An operator toggle to re-enable password signup (the user chose passwordless-first as the shipped default, not a configurable posture).

## Risks / open implementation notes for the plan

- **The invitation/join-claim move (§2) is the crux.** The plan must locate exactly how `RegistrationsController` + email verification consume these today and reproduce the outcome at the magic-link callback, immediately. Write that system spec first (red), then move the logic.
- `MagicLinkToken` gains a `return_to`/`intent` column — a small reversible migration.
- Confirm no other controller/view links to `new_registration_path` or the `passwords` reset routes before removing them (grep app/views, mailers, specs); update any stragglers (e.g. footer, sign-in page copy).
- Audit specs that call `User#authenticate` / create users with passwords for signup; they should move to magic-link or settings-opt-in setup.
