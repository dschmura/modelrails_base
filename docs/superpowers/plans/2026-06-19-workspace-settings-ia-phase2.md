# Workspace Settings IA — Phase 2: split the settings context, delete `settings_context_kind` (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or executing-plans. Steps use checkbox (`- [ ]`). **Execute after Phase 1 merges.** Re-verify the live state first — Phase 1 may have shifted the Overview/edit surface, and the layout-file decision (Task 2) is best made against the merged code.

**Goal:** The settings **context is decided by the controller/route, not by `Current.workspace.personal?`** — `/settings/*` renders the identity sidebar (Profile · Notifications · Security · Appearance, account-independent); `/workspaces/:slug/*` (incl. `WorkspacesController#edit`) renders the workspace sidebar (Profile · Members · Invitations · Limits & Plan). `settings_context_kind` and the personal/org branching are **deleted**. Spec: `docs/superpowers/specs/2026-06-19-workspace-settings-ia-design.md`.

**Architecture (DHH's "deletion over abstraction"):** today one shared `_settings_sidebar_items.html.erb` branches on `settings_context_kind` (→ `:personal` when `Current.workspace.personal?`). After Phase 2, **two focused, unconditional sidebar partials** — `shared/_identity_settings_sidebar_items` and `shared/_workspace_settings_sidebar_items` — and the *controller* declares which one its settings page wants. The shared `layout "settings"` chrome (aria-live region, header, flex+main) stays DRY; only the rendered sidebar partial differs.

**Decision to make at execution (spec §8 open edge):** *how* the controller selects its sidebar. Recommended: each settings-rendering controller declares a context via a `before_action`/class attribute (e.g. `settings_context :identity` in `Settings::*`, `settings_context :workspace` in `WorkspacesController#edit` + `Workspaces::*`); the layout reads it and renders the matching sidebar partial. This is routing-driven (the controller *is* the route) with zero `personal?` branching and one layout file. The alternative — two layout files — duplicates chrome; prefer the single-layout + controller-declared-context unless the chrome genuinely diverges.

**Tech Stack:** Rails 8.1 (`mise exec --`), RSpec (`sign_in_via_form` system / `sign_in` request), Hotwire (Turbo morph on the settings hub — preserve it), modelrails_ui. TDD; the **full suite is the gate** (deleting `settings_context_kind` → every spec asserting it fails → update it); commit but **DO NOT push**; never bypass Lefthook.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `app/views/shared/_identity_settings_sidebar_items.html.erb` | **Create** | the identity branch (Profile→`/settings/profile`, Notifications, Security, Appearance), unconditional |
| `app/views/shared/_workspace_settings_sidebar_items.html.erb` | **Create** | the workspace branch (Profile→`edit_workspace_path`, Members, Invitations, Limits), `render_nav_item_if_permitted` gates kept |
| `app/views/shared/_settings_sidebar_items.html.erb` | **Delete** | superseded by the two above (grep for remaining renders first) |
| `app/helpers/settings_navigation_helper.rb` | Modify | **delete `settings_context_kind`**; keep `render_nav_item_if_permitted`; reframe the announcer helper |
| `app/controllers/concerns/settings_context.rb` | **Create** | the `settings_context :identity\|:workspace` declaration + the chosen-sidebar helper |
| `app/controllers/settings/*` + `workspaces_controller.rb` + `app/controllers/workspaces/{settings,members,invitations}_controller.rb` | Modify | declare the context |
| `app/views/layouts/settings.html.erb` | Modify | render the controller-declared sidebar partial; `data-workspace-kind` → the new context value |
| `app/javascript/controllers/settings_announcer_controller.js` + `config/locales/en/settings.en.yml` | Modify | rename the announcer kinds `personal/org` → `identity/workspace` |
| specs (see Task 5) | Modify/Delete | drop `settings_context_kind` tests; reframe sidebar context specs |

---

## Task 1 — extract the two sidebar partials

- [ ] **Step 1 — RED:** request specs — a `/settings/profile/edit` page renders the identity items (Notifications/Security/Appearance present, no Members); a `/workspaces/:slug/members` (org) page renders the workspace items (Members present, no Notifications). Assert by item presence, not `settings_context_kind`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3 — implement:** split the current `_settings_sidebar_items` `:personal` branch into `_identity_settings_sidebar_items` (verbatim, drop the `if settings_context_kind == :personal` guard) and the `:org` branch into `_workspace_settings_sidebar_items` (verbatim, keep the `render_nav_item_if_permitted` Pundit gates). Each renders its own section label (`settings.sidebar.section_label.*`).
- [ ] **Step 4:** run → still FAIL until the layout wires them (Task 2) — proceed.

## Task 2 — controller-declared context + layout wiring

- [ ] **Step 1 — implement the concern:** `SettingsContext` — `included` adds a `settings_context` class macro storing `:identity` or `:workspace`, exposed to views via a helper (e.g. `settings_sidebar_partial` → `"shared/identity_settings_sidebar_items"` or `"shared/workspace_settings_sidebar_items"`). Include it in `ApplicationController` (or the settings controllers).
- [ ] **Step 2 — declare:** `settings_context :identity` in each `Settings::*` controller; `settings_context :workspace` in `WorkspacesController` (for `:edit`/`:update`) + `Workspaces::{Settings,Members,Invitations}Controller`.
- [ ] **Step 3 — layout:** in `settings.html.erb`, replace the two `render "shared/settings_sidebar_items"` calls (desktop L55 + mobile content_for L41) with `render settings_sidebar_partial`. Replace `data-workspace-kind="<%= settings_context_kind %>"` (L51) with the declared context (`identity`/`workspace`).
- [ ] **Step 4:** Task 1's specs → PASS.

## Task 3 — `WorkspacesController#edit` in the workspace context

- [ ] **Step 1 — RED:** a system/request spec — visiting `edit_workspace_path` for a **personal** workspace renders the **workspace** sidebar (no `/settings/profile` identity link), proving the `personal?`→identity conflation is dead.
- [ ] **Step 2:** run → FAIL (today it shows identity).
- [ ] **Step 3:** confirm `WorkspacesController` declares `settings_context :workspace` (Task 2). The edit page now wears the workspace sidebar for all workspaces.
- [ ] **Step 4:** run → PASS.

## Task 4 — rename the announcer kinds (`personal/org` → `identity/workspace`)

- [ ] **Step 1:** `settings_announcer_controller.js` already reads `this[\`${kind}Value\`]` — rename the Stimulus values `personal/org` → `identity/workspace`; update `settings.html.erb`'s `data-settings-announcer-*-value` names + the i18n keys (`settings.sidebar.aria_live_template.{identity,workspace}`). Keep the existing transition-only dedup logic. Re-verify it announces on an identity↔workspace switch.
- [ ] **Step 2:** the existing announcer system spec (if any) → green after the rename.

## Task 5 — update/delete the pinned specs

- [ ] `spec/helpers/settings_navigation_helper_spec.rb` — **delete** the `settings_context_kind` examples; keep/adjust `render_nav_item_if_permitted` + the (reframed) announcer-helper examples.
- [ ] `spec/system/settings/{personal,org}_context_spec.rb` — reframe to `identity`/`workspace` context (the sidebars no longer key off `personal?`).
- [ ] `spec/requests/settings_sidebar_visibility_spec.rb` — update to the workspace-settings sidebar.
- [ ] grep `spec/` for `settings_context_kind` → zero after.

## Task 6 — full suite, commit

- [ ] `mise exec -- bundle exec rspec` → green. `mise exec -- bundle exec rake erb:check` → clean.
- [ ] Commit: `refactor(settings): split identity vs workspace settings context by controller; delete settings_context_kind (Phase 2)`.

## Self-review

- **No `settings_context_kind`; no `personal?` branching** — the controller (route) decides; the sidebars are unconditional.
- **`/workspaces/:slug/edit` → workspace context** for all workspaces; the personal edit page (direct URL) shows the workspace sidebar, never identity.
- **Identity settings → `/settings/*`**, account-independent, one door (the avatar menu).
- **Turbo morph + the announcer preserved** (renamed kinds, same dedup).
- AAA is CI-only — push and read CI.

## Execution handoff

1. **Subagent-Driven (recommended)** — implementer per task + two-stage review (the reviewer confirms `settings_context_kind` is fully gone and the org admin sidebar is untouched).
2. **Inline** — `superpowers:executing-plans`.
