# Per-Project Tools — Design

Date: 2026-06-19
Status: Approved (design); ready for implementation planning
Branch: `feat/project-tools`
Source: Basecamp Onboarding Flows wireframes (flow 2 "Pick tools"); deferred from the onboarding journey.

## Summary

Give each project a configurable set of **tools** (Docs, and whatever a fork
adds). This ships the **enablement mechanism** — an extensible tool registry,
per-project on/off state, project-home tabs, a settings toggle, and a
registry-driven onboarding step — wiring the one tool that already exists
(Docs/Resources). It does **not** build the wireframe's other five tools
(Message board, To-dos, Schedule, Campfire, Card table); those are a fork's
domain, added through the registry seam.

## Panel decision (scope)

A three-reviewer panel (DHH, Dave Thomas, Chris Oliver; synthesized via Sandi
Metz + Jim Weirich) unanimously chose **mechanism-only**, and independently
added a refinement: ship a **lean registry (Docs + a documented "register your
own" seam)**, not Basecamp's six named tools.

- **Rejected — placeholder "coming soon" tabs:** lying UI; a fork rips them out.
- **Rejected — pre-build 1–2 tools:** code a fork deletes; ambiguous "example or
  core?" seam.
- **Rejected — ship Basecamp's six tool names:** Campfire/Card table are
  marketing names, not a generic template's domain.

Cost-of-change: stubs and pre-built tools are negative value in a template.
Honesty: an `implemented: false` registry entry *declares* a tool truthfully;
a "coming soon" page *lies*. The mechanism is the product; the tool list is the
fork's.

## Scope

In scope:

- `ProjectTools::Registry` + `ProjectTools::Tool` value object (the seam).
- `projects.enabled_tools` JSON column + `Project` helpers, with a create-time
  default and a backfill for existing projects.
- Project-home tab bar rendering enabled+implemented tools (surfaces Docs, which
  is currently not even linked from the project page).
- Project-settings tools toggle page (`Workspaces::Projects::ToolsController`).
- A registry-driven onboarding "pick tools" step that **auto-hides** until the
  registry offers a real choice.
- An enablement guard so a disabled tool's routes redirect rather than 404.

Out of scope (deliberately):

- Building Message board / To-dos / Schedule / Campfire / Card table.
- Per-tool configuration/settings beyond on/off.
- Reordering tools per project.
- Seat/billing implications.

## Registry (the extension seam)

`ProjectTools::Tool` — an immutable value object:

- `key` (Symbol, e.g. `:docs`)
- i18n label/description via `project_tools.<key>.{name,description}`
- `default_enabled` (Boolean)
- `implemented` (Boolean)
- a way to reach the tool from a project — a route-helper name (e.g.
  `:workspace_project_resources_path`) the tab bar uses.

`ProjectTools::Registry` — module holding the ordered set:

- `register(key:, default_enabled:, implemented: true, path_helper:)`
- `all`, `implemented`, `toggleable` (implemented tools the user may flip)
- `find(key)`
- **Guard:** refuses `implemented: true` without a resolvable `path_helper`, so
  the registry can never advertise a tool with no surface (no dead entries).

Ships exactly one registration: `:docs` (implemented, default-on →
`workspace_project_resources_path`). A fork adds tools in an initializer after
building them. The wireframe's other five tools appear only as commented
examples in that initializer + the design docs — never as live registry entries.

## Data model

- Migration: add `projects.enabled_tools` (JSON, not null, default `[]`).
- Backfill existing projects to the default-enabled implemented keys
  (`["docs"]`) so nothing regresses.
- On `Project` create, if `enabled_tools` is blank, set it to
  `ProjectTools::Registry.implemented.select(&:default_enabled).map(&:key)`.
- `Project#tool_enabled?(key)` → key present in `enabled_tools`.
- `Project#tools` → registry tools that are **implemented AND enabled**, in
  registry order (this is what renders as tabs).

Rejected alternative: a `project_tools` join table. The enabled set is simple
config on the project, not a domain entity with its own lifecycle; JSON matches
the app's existing JSON-column convention (role permissions,
`last_known_browsers`) and avoids a join on the project-home hot path.

## Project home — tabs

`projects/show` gains a tab bar (modelrails_ui, AAA, both themes) rendering
`@project.tools`. Each tab links via the tool's `path_helper`. Today this
surfaces the **Docs** tab (Resources are currently unlinked from the project
page — a real gain). The existing Members/Edit nav stays. Empty state: if a
project somehow has no enabled tools, show a quiet "no tools enabled" hint
linking to the settings toggle.

## Settings toggle

`Workspaces::Projects::ToolsController` (`edit`, `update`), nested under the
project like the existing project sub-resources. Lists
`ProjectTools::Registry.toggleable` as checkboxes bound to `enabled_tools`.
Pundit: authorize on the project with `manage_projects`. Strong params permit
`enabled_tools: []`, intersected with toggleable keys server-side (never trust
the client to enable an unimplemented/unknown tool).

## Onboarding "pick tools" step — registry-driven, self-hiding

Re-adds the deferred wizard step **without** showing a pointless one-item
screen, and **without** complicating the derive-from-data dispatcher:

- A new `Onboarding::ToolsController` (new/create) sits between the project and
  team steps as a **forward-only interstitial**.
- `Onboarding::ProjectsController#create` redirects to the tools step **only
  when `ProjectTools::Registry.toggleable.size > 1`**; otherwise straight to the
  team step. Out of the box (Docs only) the step auto-skips, so the wizard stays
  workspace → project → invite. It appears automatically once a fork registers a
  second toggleable tool.
- When shown: checkboxes (create-time defaults pre-checked); "Save tools" writes
  `enabled_tools` → team step; "Skip" keeps the defaults → team step.
- The **resume dispatcher is unchanged** (`User#onboarding_step` /
  `OnboardingsController#show` stay workspace/project/team). Tool selection is
  optional with sensible defaults, so it does not need to be a resumable gate: a
  user who drops off at the tools step resumes at the team step keeping the
  create-time defaults. This deliberately keeps "tools chosen" OUT of the
  derive-from-data model (it isn't derivable — `enabled_tools` is pre-populated
  at create).

> #363 NOTE: because the dispatcher and `User#onboarding_step` are left
> untouched, this work only adds an onboarding route + a new controller and edits
> `Onboarding::ProjectsController#create` — none of which PR #363 changes. Conflict
> risk with #363 is limited to `config/routes.rb`; rebase if it lands first.

## Enablement guard

`Project#tool_enabled?` backs a small controller concern
(`EnforcesProjectTool`) that a tool's controller includes to redirect (not 404)
to the project home when its tool is disabled. The Docs/`resources` controller
adopts it as the worked example forks copy.

## Testing

- Registry unit specs: registration, `implemented`/`toggleable` filtering, the
  no-dead-entry guard (registering `implemented: true` with a bad path raises).
- `Project` model specs: create-time default, `tool_enabled?`, and `tools`
  ordering across the implemented-and-enabled intersection.
- Migration + backfill spec (existing project → `["docs"]`).
- Request specs: settings toggle (`edit`/`update`, param intersection,
  authorization), enablement guard (disabled tool route redirects).
- System spec: project-home tabs render; toggling a tool in settings shows/hides
  its tab; onboarding step hidden with the default registry.
- AAA axe on the new tab bar + settings page, both themes (proven in CI).

## Suggested phasing (for the plan)

- **P1** — Registry + `Project` model (`enabled_tools` migration + backfill +
  helpers + create default). Pure model/lib; no UI.
- **P2** — Project-home tab bar + enablement guard (wire Docs).
- **P3** — Settings toggle page.
- **P4** — Registry-driven onboarding tools step (forward-only interstitial off
  `Onboarding::ProjectsController#create`; dispatcher untouched). Self-hides with
  the default registry.
- **P5** — System spec + AAA + docs (the "register your own tool" guide).

## Terminology

| Wireframe | This design |
| --- | --- |
| "Pick the tools" | onboarding tools step (self-hiding) + settings toggle |
| Message board / To-dos / Schedule / Campfire / Card table | registry seam examples — not built |
| Docs & Files | the `:docs` tool → existing `Resource`/`Document` |
