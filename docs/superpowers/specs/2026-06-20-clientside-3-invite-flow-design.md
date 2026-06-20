# Clientside #3 — Client invite flow — Design

Date: 2026-06-20
Status: Approved (design); ready for implementation planning
Branch: `feat/clientside-3-invite`
Source: Basecamp Onboarding Flows wireframes, flow 5 ("Client / guest invite — Clientside"), steps 2–4 (invite client → client email → accept → land).
Builds on: Clientside #1 (`ClientAccess`, `projects.clientside_enabled`) and #2 (the client area + `authenticated`/`clientside` plumbing).

## Milestone context

Third and FINAL Clientside sub-project. #1 = access model; #2 = client area + sharing; #3 = the invite flow that brings external clients in. After #3, wireframe flow 5 is complete.

## Decisions (locked)

- **Invite record:** EXTEND the existing `Invitation` with a client variant (not a separate `ClientInvitation`). The invite's accept path is the app's most security-critical machinery (bearer-token `EmailMismatch` guard, consume-before-verify, new-vs-existing-user branch); reusing it keeps one audited path. `accept!` creates a `ClientAccess` for client invites, preserving #1's separate-access-record boundary.
- **Scope:** the FULL flow — both accept branches (existing user one-click; new user sets up a login) — since external clients usually have no account.
- **Landing:** centralized — `authenticated_home_path` returns the client area for client-only users; no per-entry-point redirect threading.
- **Onboarding exemption:** stamp `users.onboarded_at` when a client invite is accepted (a client bypasses org onboarding); the #362 posture guard then lets them through with no special case.

## Scope

In scope:

- `invitations.company_name` + the `Invitation` client variant (`client_invite?`, optional role, `accept_client_invitation!`).
- `Invitation.invite_client!(project:, email:, company_name:, invited_by:)` + a client-flavored mailer action.
- `Workspaces::Projects::ClientInvitationsController` (`new`/`create`) — the team invite UI, gated on Clientside + authorization.
- The existing-user accept redirect to the client area; the new-user accept already works via parked-token → verify → claim.
- Two shared-auth touches: `authenticated_home_path` client-only branch; `EmailVerificationsController#show` redirect to `authenticated_home_path`.

Out of scope (deferred):

- A pending-client management list / revoke UI (re-invite works; full client roster UI is later polish).
- Approve/comment (earlier deferral); company-grouping UI; client-side notifications.

## Data model / Invitation changes

- Migration `add_company_name_to_invitations`: `company_name` string, nullable.
- `app/models/invitation.rb`:
  - `belongs_to :role, optional: true` (was implicitly required).
  - `validates :role, presence: true, unless: :client_invite?`.
  - `validate :client_invite_targets_a_project` — when `client_invite?`, `invitable_type` must be `"Project"`.
  - `def client_invite? = company_name.present?`.
  - `accept!` branch order: `client_invite?` → `accept_client_invitation!` ; elsif `invitable_type == "Project"` → existing project path ; else workspace path.
  - `accept_client_invitation!(user)` — idempotently create/undiscard a
    `ClientAccess(project: invitable, user:, company_name:)`, then
    `user.update!(onboarded_at: Time.current) unless user.onboarded?`. (The
    `ClientAccess` create-guard from #1 enforces `clientside_enabled?`; accepting
    a client invite to a project whose Clientside is off fails with
    `RecordInvalid`, surfaced by the accept controller as `acceptance_failed`.)
  - `Invitation.invite_client!(project:, email:, company_name:, invited_by:)`: create the invitation (`invitable: project`, `email:`, `company_name:`, `role: nil`, `expires_at: 7.days.from_now`), then `InvitationMailer.invite_client(invitation).deliver_later`. Returns the invitation. (Single-recipient; no bulk for clients in v1.)
  - `resolved_workspace` already maps a Project invitation → its workspace (used by notifiers/mailer); unchanged.

> The member-invite paths (`bulk_invite!`, `accept_project_invitation!`, `accept_workspace_invitation!`) are untouched. The role-optional change must NOT weaken member-invite validation — a member invite (no `company_name`) still requires a role via the `unless: :client_invite?` guard.

## Team invite UI

`Workspaces::Projects::ClientInvitationsController` (`new`, `create`), nested in
the projects `scope module: :projects` block.

- `before_action :set_project` (slug lookup, like the sibling controllers).
- `before_action :ensure_clientside_enabled` — redirect to the Clientside settings page unless `@project.clientside_enabled?`.
- `new`: `authorize Invitation` (reuses `InvitationPolicy#new?`/`create?` = `can?("manage_members")`); render the form.
- `create`: `authorize Invitation`; `Invitation.invite_client!(project: @project, email:, company_name:, invited_by: Current.user)`; redirect to `edit_workspace_project_clientside_path(@workspace, @project)` with a notice.
- Strong params: `params.require(:client_invitation).permit(:email, :company_name)` (a small form object-less param namespace).
- Linked from the Clientside settings page (`Workspaces::Projects::ClientsidesController#edit`, from #1).

## Client invite email

`InvitationMailer#invite_client(invitation)` — client-flavored copy
("{inviter name} shared {project name} with you"), linking to
`accept_invitation_url(token: invitation.token)` (the existing accept route).
Separate action/templates (html + text) from the member `invite` so copy stays
honest; reuses the same token + accept URL.

## Accept (reuses the hardened path)

`InvitationAcceptsController` is reused as-is for token validation + the
new-vs-existing branch. One change: in `create`, the authenticated/existing-user
success redirect branches on `@invitation.client_invite?` →
`clientside_project_path(@invitation.invitable)` (the client area), else the
existing member redirects. The `show` view should render client-flavored framing
when `@invitation.client_invite?` (e.g. "{inviter} shared {project} with you")
vs the member framing — a conditional in the existing template.

New-user branch is already correct and unchanged: unauthenticated accept stashes
the token → registration parks it on the `Authentication` → email verification →
`Authentication#claim_pending_invitation!` → `Invitation.consume!` → `accept!`
(client branch) → `ClientAccess` + `onboarded_at` stamp.

## Landing (shared-auth touches)

- `Authenticatable#authenticated_home_path`: return `clientside_projects_path`
  when the user is client-only — `Current.user.client_accesses.kept.exists?` AND
  `Current.user.memberships.kept.none?`; else the existing `root_path`. Members
  and member+client users are unaffected.
- `EmailVerificationsController#show`: redirect to `after_authentication_url`
  (which resolves through `authenticated_home_path`) instead of the hardcoded
  `root_path` on success — so a freshly-verified new client lands in the client
  area, while members still land on root / onboarding as before. (Net-better;
  the only #362-owned change.)

## Authorization / isolation summary

- Only `manage_members` users on a Clientside-enabled project can invite clients.
- A client invite carries an email; `consume!`'s `EmailMismatch` guard prevents
  bearer redemption (a leaked link can't be claimed by another address).
- Accepting creates a `ClientAccess` (never a Membership); the client gains the
  read-only client area from #2 and nothing else.
- A new client is exempt from onboarding (stamped) and lands only in the client
  area (`authenticated_home_path`).

## Testing

- Model: `client_invite?`; `invite_client!` creates the invitation + enqueues the
  client mailer; `accept!` for a client invite creates a `ClientAccess` + stamps
  `onboarded_at` (existing user) and is idempotent (undiscard); `EmailMismatch`
  still raised on a wrong-address consume; **member invites still require a role**
  (regression guard for the role-optional change).
- Request (team): `ClientInvitationsController` new/create — gated on
  `clientside_enabled?`, authorized (`manage_members`; a non-manager denied),
  creates the invite, enqueues the mailer.
- Request (accept): an authenticated existing user accepting a client invite gets
  a `ClientAccess` and is redirected to `clientside_project_path`; a new user
  accept (register → verify) ends with a `ClientAccess`, `onboarded_at` set, and
  `authenticated_home_path == clientside_projects_path`.
- Request (landing): a client-only user's `authenticated_home_path` is the client
  area; a member's is root; `EmailVerificationsController#show` lands a verified
  client in the area.
- Mailer: `invite_client` renders to the client with the accept URL.
- System: team enables Clientside (or it's on), invites a client; the (existing-
  user) client accepts and sees the client area — AAA axe on the invite form +
  accept page, both themes.
- The existing member-invitation request/system specs stay green.

## Suggested phasing (for the plan)

- **P1** — `company_name` migration + Invitation client variant (`client_invite?`,
  optional role + guards, `accept_client_invitation!` + onboarded stamp,
  `invite_client!`) + the `invite_client` mailer. Model/mailer only.
- **P2** — `Workspaces::Projects::ClientInvitationsController` + form + route +
  Clientside-settings link + i18n + request specs.
- **P3** — accept redirect + `show` client framing; `authenticated_home_path`
  client-only branch; `EmailVerificationsController#show` redirect; request specs
  for accept + landing.
- **P4** — end-to-end system spec + AAA + the member-invite regression guards.

## Terminology

| Wireframe | This design |
| --- | --- |
| "Invite a client" (email + company) | `ClientInvitationsController#new/create` → `Invitation.invite_client!` |
| "Acme shared a project" email | `InvitationMailer#invite_client` |
| accept → "lands in the client area" | `accept!` client branch + `authenticated_home_path` client-only routing |
| client is free / external | `ClientAccess` (from #1), never a Membership; onboarding-exempt |
