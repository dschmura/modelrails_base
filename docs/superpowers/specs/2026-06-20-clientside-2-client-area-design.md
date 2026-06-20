# Clientside #2 — Client area + per-resource sharing — Design

Date: 2026-06-20
Status: Approved (design); ready for implementation planning
Branch: `feat/clientside-2-client-area`
Source: Basecamp Onboarding Flows wireframes, flow 5 ("Client / guest invite — Clientside"), step 4 ("Client view").
Builds on: Clientside #1 (PR #365) — `ClientAccess`, `projects.clientside_enabled`, `Project#client?`, `User#client_of?`.

## Milestone context

Second of three Clientside sub-projects (#1 access model shipped; #3 client invite flow remains). This sub-project delivers the **team-side sharing flag** and the **read-only client area** — the separate limited surface where an external client sees only explicitly-shared items.

## Scope

In scope:

- `resources.shared_with_client` boolean + `Resource#client_visible?` (`shared_with_client? && published?`).
- Team-side sharing control: a `shared_with_client` checkbox on the resource edit
  form, shown only when the project's Clientside is enabled.
- A `Clientside::` namespace (authenticated, non-workspace-scoped) — the read-only
  client area: a list of the client's projects, a per-project client area showing
  client-visible resources, and a read-only resource view.
- Runtime enforcement deferred from #1: the client area gate checks
  `project.clientside_enabled?` (toggling Clientside off blocks access).
- A focused `clientside` layout ("{workspace} · Client area").

Out of scope (later increments / sub-projects):

- Approve/comment interactions (needs Comment/Approval models + notifications).
- The client **invite** flow — email + company → accept → land (sub-project #3).
- A one-click "share" toggle on the resource index/show (the edit-form checkbox
  suffices for v1).
- Client-side notifications; grouping the client area by company.

## Decisions (locked)

- **Client-visible rule:** `Resource#client_visible?` ⇒ `shared_with_client? && published?`.
  Publishing is the readiness gate, so a shared *draft* never leaks.
- **Sharing UI:** a checkbox on the existing resource edit form (rides the resource
  update), shown only when `@project.clientside_enabled?`. No new toggle endpoint.
- **Approve/comment:** deferred (read-only client area for #2).

## Data model

- Migration `add_shared_with_client_to_resources`: `shared_with_client` boolean,
  `null: false, default: false`.
- `Resource`:
  - `scope :shared_with_client, -> { where(shared_with_client: true) }` (DB scope)
  - `def client_visible? = shared_with_client? && published?`
  - A project-level reader for the client area:
    `Project#client_visible_resources` → `resources.kept.published.where(shared_with_client: true).positioned`.
- Strong params: the member-side resource update permits `:shared_with_client`
  **only when the project's Clientside is enabled** (the controller intersects, so
  a client flag can't be set on a non-Clientside project).

## Team-side sharing control

On `app/views/workspaces/projects/resources/edit.html.erb`, add a
`shared_with_client` checkbox wrapped in `<% if @project.clientside_enabled? %>`.
`Workspaces::Projects::ResourcesController#update` permits `:shared_with_client`
guarded by `@project.clientside_enabled?` (drop the key otherwise). Authorization
is unchanged (resource update already requires creator/editor). I18n copy via the
existing `workspaces.projects.resources.*` namespace.

## Client area (`Clientside::` namespace)

A `MeController`-style authenticated, self-scoped area — clients are `User`s but
NOT workspace members, so it must not use `WorkspaceScoped` / `Current.workspace`.

- `Clientside::BaseController < ApplicationController`
  - `skip_onboarding_requirement` — a client (external `User`, possibly
    `onboarded_at: nil` under `:none`) must reach the client area, not be funneled
    into the onboarding wizard (the #362 guard). This is the load-bearing
    cross-cutting fix.
  - `layout "clientside"` — focused layout, no workspace sidebar.
  - `set_project` (for the per-project actions): resolves the project via
    `Current.user.client_accesses.kept.find_by!(project: …)` → the project; sets
    `Current.project`; redirects to the client projects list (not 500) when the
    user has no client access to it. **Does NOT set `Current.workspace`.**
  - `ensure_clientside_enabled`: redirect to the client projects list unless
    `Current.project.clientside_enabled?` (deferred-from-#1 runtime enforcement).
- `Clientside::ProjectsController`
  - `index`: `@projects = Project.where(id: Current.user.client_accesses.kept.select(:project_id))` (the projects the user is a client of). Self-scoped, no Pundit (like `MeController`).
  - `show`: the client area for one project — header "the workspace name · Client
    area" + `@resources = @project.client_visible_resources`.
- `Clientside::Projects::ResourcesController`
  - `show`: a read-only view of one client-visible resource; redirect to the
    project client area unless `resource.client_visible?` (and the resource belongs
    to `@project`).

Routes (top-level, RESTful):

```ruby
namespace :clientside do
  resources :projects, only: %i[index show] do
    resources :resources, only: %i[show], module: :projects
  end
end
```

(`Clientside::ProjectsController`, `Clientside::Projects::ResourcesController`.)

## Layout

`app/views/layouts/clientside.html.erb` — minimal: head, skip link, a header
showing "the workspace name · Client area" + sign-out, a centered `<main>`, tail.
No workspace sidebar, no internal nav. Reuses `shared/layout_head` / `layout_tail`
/ `skip_link`. Semantic AAA tokens, both themes.

## Authorization / isolation summary

- A client sees a project ONLY via a kept `ClientAccess` (never membership).
- A client sees a resource ONLY if `client_visible?` (shared + published) AND it
  belongs to a project they have client access to.
- The area is blocked entirely when `clientside_enabled?` is false.
- No workspace-scoped data, controllers, or chrome are reachable from the client
  area (no `Current.workspace`, no `WorkspaceScoped`).

## Testing

- Model: `Resource#client_visible?` truth table (shared+published true; shared+draft
  false; unshared+published false); `Project#client_visible_resources` returns only
  shared+published kept resources in position order.
- Request (team side): the resource edit form shows the share checkbox only when
  Clientside is on; update sets `shared_with_client` when on; update ignores the
  flag when Clientside is off.
- Request (client side): a client sees the client area (200) and only
  client-visible resources; a non-client gets redirected/404 from a project; the
  area is blocked when `clientside_enabled?` is false; a draft/unshared resource
  `show` is refused.
- System: a client signs in, lands in the client area, sees a shared+published
  resource and not a draft/unshared one — with AAA axe on the client layout, both
  themes.
- The existing member-side resource specs stay green.

## Suggested phasing (for the plan)

- **P1** — `shared_with_client` migration + `Resource#client_visible?` /
  `Project#client_visible_resources` + the member-side edit checkbox &
  Clientside-guarded param.
- **P2** — `Clientside::BaseController` + `clientside` layout + `ProjectsController`
  (index/show) + the access/enablement gates.
- **P3** — `Clientside::Projects::ResourcesController#show` (read-only) + the system
  spec + AAA.

## Terminology

| Wireframe | This design |
| --- | --- |
| "Acme Co · Client area" | `Clientside::ProjectsController#show` under the `clientside` layout |
| "items the team explicitly shares to the client side" | `resources.shared_with_client` + `client_visible?` |
| "Approve / Comment" | deferred (a later increment) |
