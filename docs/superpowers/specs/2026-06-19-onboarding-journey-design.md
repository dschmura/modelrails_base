# Onboarding Journey — Design

Date: 2026-06-19
Status: Approved (design); ready for implementation planning
Branch: `feat/onboarding-journey`
Source: Basecamp Onboarding Flows wireframes (claude.ai/design project `7c7c1c0b…`), flows 1 + 2

## Summary

Build a first-run onboarding journey for new users on the **team/org** signup
posture (`WORKSPACE_ON_SIGNUP=none`): after registration they land on a
"check your email" screen (soft email-verification gate), then a resumable
multi-step wizard — **Name your account → Create first project → Invite
teammates (skippable) → land in the project home**.

This stitches together machinery the app already has (Rails 8 auth, Workspace,
Project, Invitation, roles) with onboarding-specific chrome and redirects. It
does **not** introduce new business logic for workspace/project/invitation
creation — those paths are reused.

## Scope

In scope:

- Onboarding wizard for the `none` posture (account → project → invite → done).
- Soft email-verification gate: post-registration "check your email" screen with
  a working **Resend** action, plus a non-blocking "confirm your email" reminder
  banner in the authenticated layout.
- Production design system: modelrails_ui primitives, AAA tokens, light + dark,
  reusing the existing `UI::StepperComponent` for wizard progress chrome.

Out of scope (deliberately deferred):

- Email-already-exists → log in routing on the password signup path.
- Apple OAuth provider (only Google + GitHub today).
- Pricing / marketing landing pages (fork-owned, no backend, off the core path).
- Per-project "tools" toggles (Message board / To-dos / Schedule / …) — there is
  no per-project feature-toggle subsystem; building one is a separate effort.
- The `personal` and `shared` postures — onboarding targets `none` only; the
  other postures are left untouched.
- Clientside / external-client surface (wireframe flow 5) — greenfield milestone,
  separate effort.

## Posture & assumptions

- Target posture: `WORKSPACE_ON_SIGNUP=none`. In this mode `User#onboard_workspace`
  creates nothing on signup, so a brand-new user has **zero** workspaces and is
  routed into the wizard.
- Tenancy today is URL-scoped: `WorkspaceScoped` sets `Current.workspace` from the
  route's workspace. During first-run the user owns exactly one workspace, so the
  wizard can resolve it unambiguously without a slug in the URL.
- Soft gate: the app already signs the user in at registration (before email
  verification). We keep that. Verification completes asynchronously; the user may
  proceed into the wizard while unverified.

## State model (derive-from-data + single terminal marker)

- Add one nullable column `users.onboarded_at : datetime`.
- The current step is **derived from data**, never stored as a pointer:
  - no workspace → **Account** step
  - workspace, no project → **Project** step
  - workspace + project, `onboarded_at` nil → **Invite** step
  - `onboarded_at` present → onboarding complete
- "Send invites" and "Skip for now" both stamp `onboarded_at` and end the wizard.
- Migration includes a **backfill**: stamp `onboarded_at = now` for existing
  `none`-posture users who already have a workspace + project, so they are never
  pulled into the wizard retroactively.

Rejected alternatives: an `onboarding_step` enum column (can desync from real
data); a separate `Onboarding` model (overkill for one nullable timestamp).

## Routing (RESTful, all top-level under `/onboarding`)

```ruby
resource  :onboarding, only: %i[show update]   # show = dispatcher → current step; update = complete/skip
namespace :onboarding do
  resource :account, only: %i[new create]      # step 1: name + create workspace
  resource :project, only: %i[new create]      # step 2: first project
  resource :team,    only: %i[new create]      # step 3: send invites (skippable)
end
```

- `OnboardingsController#show` is the single entry point / dispatcher: it computes
  the derived step and redirects to that step's `new` path. The redirect guard
  always sends users here.
- `OnboardingsController#update` marks onboarding complete (stamps `onboarded_at`)
  and redirects to the project home — used by "Skip for now".

## Controllers (thin; reuse existing models)

- `Onboarding::BaseController` (< authenticated base):
  - requires login;
  - bounces already-onboarded users out of `/onboarding` (inverse guard);
  - resolves `Current.workspace` from the in-progress workspace for the project
    and team steps. This is a small, documented deviation from URL-scoped tenancy,
    justified by keeping wizard URLs stable during first-run.
- `Onboarding::AccountsController` — `new` (name form), `create` (reuses the
  existing Workspace + owner-membership creation path; → project step).
- `Onboarding::ProjectsController` — `new`, `create` (Project under
  `Current.workspace` via the existing path; → team step).
- `Onboarding::TeamController` — `new` (invite form showing the owner avatar),
  `create` (existing `Invitation.bulk_invite!`; then complete → project home).
- `OnboardingsController` — `show` (dispatcher), `update` (complete/skip).

All creation logic is delegated to existing models/paths; onboarding controllers
own only the views and redirects.

## First-run redirect guard

In the authenticated base controller, `require_onboarding`:

- active **only** when `Rails.configuration.x.tenancy.onboarding == :none`;
- active only when `current_user.onboarded_at.nil?`;
- skips auth / email-verification / onboarding routes (no redirect loops);
- redirects everything else to the onboarding dispatcher.

Other postures (`personal`, `shared`) never trigger it.

## Soft-gate signup

- `RegistrationsController#create` redirects to a dedicated post-registration
  confirmation screen (`registrations/check_email`) showing the masked address and
  a **Resend** button wired to the existing `email_verification_resend` route
  (`POST`). If markup overlaps the existing sessions `check_email` view (magic-link
  path), the shared chrome is factored into a partial; the two screens are not
  merged, since their copy and follow-on actions differ.
- A "confirm your email" reminder banner partial renders in the authenticated
  layout while the user's primary email is unverified. It is **non-blocking** — the
  user can still use the wizard and the app.
- The existing email-verification link flips `verified` and routes into the
  onboarding dispatcher (or the app, if already onboarded).

## UI / design system

- `UI::StepperComponent` (already AAA-proven, with preview + spec) provides the
  Account · Project · Invite progress chrome.
- Forms, buttons, cards, empty states use modelrails_ui primitives and semantic
  AAA tokens. Verified in both light and dark themes. Contrast is proven in CI
  (local axe is AA-only).

## Testing (TDD, spec-first)

- Request specs: each onboarding controller (`new`/`create`/dispatch/`update`);
  the redirect guard under `none` vs `personal` postures; resend.
- System spec: the full journey (verify → account → project → invite → home) plus
  the skip path, with reminder-banner assertions.
- Mailer / resend spec.
- Migration + backfill spec.
- AAA axe coverage in CI for every new screen.

## Suggested phasing (for the implementation plan)

- **Phase A** — Soft gate: check-email screen + resend + reminder banner.
  Independent and shippable on its own.
- **Phase B** — State: `onboarded_at` migration + backfill + redirect guard.
- **Phase C** — Wizard steps (account, project, team) + stepper UI.
- **Phase D** — Full system spec + AAA polish.

## Terminology map (wireframe → app)

| Wireframe | App |
| --- | --- |
| Account (org) | Workspace |
| Owner / Admin / Member / Client | Owner / Admin / Member / Viewer (no Client) |
| Basecamp ID | User (one per person, reused across workspaces) |
| "Name your account" | Onboarding::Account step (creates Workspace) |
