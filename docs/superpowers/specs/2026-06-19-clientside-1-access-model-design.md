# Clientside #1 — Client access model — Design

Date: 2026-06-19
Status: Approved (design); ready for implementation planning
Branch: `feat/clientside`
Source: Basecamp Onboarding Flows wireframes, flow 5 ("Client / guest invite — Clientside").

## Milestone context (decomposition)

Flow 5 (Clientside) is a milestone, not a single spec. It introduces a **new
access axis**: an *external* client who sees only explicitly-shared items in a
walled "client area," never the workspace itself. It is decomposed into three
sequenced sub-projects, each its own spec → plan → PR:

1. **Client access model (THIS spec)** — the data model, the per-project
   Clientside toggle, and the access query the rest builds on. No client-facing
   UI, no invite flow.
2. **Client area + per-resource sharing** — the separate limited surface
   ("Acme · Client area"), a "share this to the client side" flag on resources,
   approve/comment interactions.
3. **Client invite flow** — invite by email + company, client email,
   accept → land in the client area (reuses the polymorphic `Invitation`).

Product decisions locked for the whole milestone:

- **Client model:** a **separate `ClientAccess` model**, NOT a `Membership`. An
  external client is genuinely not a workspace member — separate boundary keeps
  it out of workspace policies and seat counting.
- **Seats/billing:** no billing system is built. Clients are free because
  `ClientAccess` is a different table from `memberships`, so they never count
  toward `Workspace#max_members` (by construction).
- **Sharing granularity:** a per-resource "shared to client" flag (explicit,
  simple) in sub-project #2 — not per-field ACLs or a separate container.

## This spec: sub-project #1 scope

In scope:

- `projects.clientside_enabled` boolean (the per-project toggle).
- `ClientAccess` model (external client ↔ project), discardable, company-grouped.
- `Project` / `User` associations + access query (`Project#client?(user)`).
- A dedicated per-project Clientside settings toggle controller + view.
- Capacity-exclusion guarantee (clients don't consume member seats), locked by a
  test.

Out of scope (later sub-projects): the client area UI, per-resource sharing,
approve/comment (#2); the client invite-by-email/company flow, client email,
accept→land (#3); a `Company` model (a `company_name` string suffices for v1).

## Data model

- Migration `add_clientside_enabled_to_projects`: `clientside_enabled` boolean,
  `null: false, default: false`. (No backfill values needed beyond the default;
  existing projects default to off.)
- Migration `create_client_accesses`:
  - `project_id` (FK, indexed), `user_id` (FK, indexed)
  - `company_name` (string, null: false)
  - `discarded_at` (datetime, indexed — Discardable)
  - timestamps
  - unique index on `(project_id, user_id)`.
- `ClientAccess` model:
  - `belongs_to :project`, `belongs_to :user`
  - `include Discardable`
  - `validates :company_name, presence: true`
  - `validates :user_id, uniqueness: { scope: :project_id }`
  - `validate :project_clientside_enabled, on: :create` — adds an error unless
    `project.clientside_enabled?` (can't grant client access while Clientside is
    off).
- `Project`:
  - `has_many :client_accesses, dependent: :destroy`
  - `clientside_enabled?` (the boolean reader)
  - `client?(user)` → `client_accesses.kept.exists?(user: user)`
- `User`:
  - `has_many :client_accesses, dependent: :destroy`
  - `client_of?(project)` → `client_accesses.kept.exists?(project: project)`

A client is a real `User` (one identity per person, per the wireframe's own
model); the *external* relationship is the `ClientAccess` row, never a
`Membership`. A person can be a member of one workspace and a client of another
workspace's project simultaneously — the two relationships are independent.

## Per-project Clientside toggle

`Workspaces::Projects::ClientsideController` (`edit`, `update`) — nested under the
project in the `scope module: :projects` block, matching the tools-settings
pattern. `authorize @project, :update?` (reuses `ProjectPolicy#update?` =
project-creator check, same gate as the Tools settings) in both actions. `update` permits only `:clientside_enabled` and
redirects back to `edit` with a notice. Linked from the project settings nav
next to Tools/Edit. All copy via I18n (`clientside.*` keys).

Edge: turning Clientside *off* while client accesses exist — for #1, the toggle
simply flips the boolean; existing `ClientAccess` rows are left intact (access
enforcement lands with the client area in #2, which will check
`clientside_enabled?` at the gate). Documented here so #2 owns the runtime
enforcement; #1 does not silently revoke or destroy client rows.

## Access query (the seam #2/#3 consume)

`Project#client?(user)` and `ClientAccess.find_by(project:, user:)` are the
foundation. The client-area **policy and controllers** that gate a real surface
land in sub-project #2 (where there is something to authorize); #1 deliberately
ships only the model + query so #1 stays cohesive and independently testable.

## Capacity exclusion (free clients)

No code is required to make clients free: `Workspace#max_members` /
`Membership#workspace_has_member_capacity` count `memberships.kept`, and
`ClientAccess` is a separate table. A model spec asserts that granting a
`ClientAccess` does not change a workspace's remaining member capacity, locking
the guarantee against future regressions.

## Testing

- `ClientAccess` model specs: `company_name` presence; `(project, user)`
  uniqueness; the `project_clientside_enabled` create guard (granting fails when
  the project's Clientside is off, succeeds when on); `Discardable` behavior.
- `Project` / `User` specs: `client?` / `client_of?` true/false; `clientside_enabled?`.
- Capacity-exclusion spec: a workspace at N members with a client access still
  reports the same remaining capacity; a `ClientAccess` does not count as a
  membership.
- Request spec: `Workspaces::Projects::ClientsideController` `edit` renders,
  `update` flips `clientside_enabled` and authorizes (project-creator required per
  `ProjectPolicy#update?`; a non-creator project member is denied).
- Migration specs: new projects default `clientside_enabled: false`.

## Suggested phasing (for the plan)

- **P1** — migrations (`clientside_enabled` + `client_accesses`) + `ClientAccess`
  model + `Project`/`User` associations & queries (+ capacity-exclusion spec).
- **P2** — `Workspaces::Projects::ClientsideController` toggle (route, controller,
  view, settings link, i18n) + request specs.

## Terminology

| Wireframe | This design |
| --- | --- |
| "Turn on Clientside for this project" | `projects.clientside_enabled` + ClientsideController |
| Client (external, limited) | a `User` related via `ClientAccess` (not a Membership) |
| "grouped by their company" | `client_accesses.company_name` (string; grouping UI is #2) |
| "clients are free" | excluded from `max_members` by the separate table |
