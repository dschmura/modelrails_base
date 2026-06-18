# Identity Phase 2c-1 — settings account-independent (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Make `/settings/*` honestly account-independent and retire the now-redundant settings-sidebar switcher (2b put one in the header). Two surgical changes: (1) drop `PersonalWorkspaceContext` so `Current.workspace` is `nil` on `/settings` (instead of the lie `= your personal workspace`); (2) remove the `_settings_sidebar_switcher`. Spec: `docs/superpowers/specs/2026-06-18-identity-account-model-clarity-design.md`. Execute after #353 (the header switcher) merges.

**Architecture:** The settings *layout/sidebar* is **shared** — `layout "settings"` serves both the identity controllers (`Settings::*`, `/settings/*`) and the workspace-admin controllers (`WorkspacesController#edit`, `Workspaces::{Members,Invitations,Settings}Controller`, `/workspaces/:slug/*`). The sidebar is **polymorphic by URL context**: `settings_context_kind` returns `:personal` (nil/personal workspace → identity items) or `:org` (a real org workspace → admin items). **This polymorphism stays — it is correct.** We are NOT deleting the org branch (it's the live workspace-admin nav). We only: drop the concern (so `/settings` resolves `:personal` via the existing nil-guard instead of a forced personal workspace) and remove the redundant switcher.

**⚠️ Guardrails (from a corrected blast-radius analysis):**
- **KEEP** `_settings_sidebar_items.html.erb` lines ~80–137 (the `:org` branch) — it renders workspace admin nav on `/workspaces/:slug/*`.
- **KEEP** `spec/system/settings/org_context_spec.rb`, `spec/requests/settings_sidebar_visibility_spec.rb`, the `:org` tests in `settings_navigation_helper_spec.rb` — they cover the live workspace-admin context.
- The switcher removal affects **both** contexts (identity *and* workspace-admin sidebars lose their in-sidebar switcher; switching is via the header now).
- Subtle effect of dropping the concern: the settings layout color heuristic (`if Current.workspace … primary_color`) no longer fires on `/settings`, so `/settings` uses the default hue (210) not the personal workspace's. **This is correct** (identity settings aren't workspace-colored) — update any spec that asserts otherwise.

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (`mise exec --`), RSpec. The full suite is the gate (removing the switcher → any spec asserting it fails → update it). TDD where it fits; commit but **DO NOT push**; never bypass Lefthook.

## File Structure

| File | Action | Note |
|---|---|---|
| `app/controllers/settings/{profiles,theme_preferences,notification_preferences,connected_accounts}_controller.rb` + `settings/preferences/timezones_controller.rb` | Modify | remove `include PersonalWorkspaceContext` (5 controllers) |
| `app/controllers/concerns/personal_workspace_context.rb` | **Delete** | unused after the includes are removed (verify with grep) |
| `app/views/shared/_settings_sidebar_items.html.erb` | Modify | remove the `_settings_sidebar_switcher` render (~L23–26); **keep** the `:org` branch |
| `app/views/shared/_settings_sidebar_switcher.html.erb` | **Delete** | superseded by the header switcher (verify no other usage) |
| `app/views/layouts/settings.html.erb` | Modify | drop the now-unused `workspaces:`/`workspaces_scope` local passed for the switcher |
| specs | Modify/Delete | only the **switcher-asserting** ones (see Task 2) |

---

## Task 1 — drop `PersonalWorkspaceContext`

- [ ] **Step 1: Confirm the inclusion set.** `grep -rn "PersonalWorkspaceContext" app spec` — expect the 5 `Settings::` controllers + the concern definition. If anything else includes it, STOP and report.

- [ ] **Step 2: Remove the include** from each of the 5 controllers (`app/controllers/settings/profiles_controller.rb`, `theme_preferences_controller.rb`, `notification_preferences_controller.rb`, `connected_accounts_controller.rb`, `preferences/timezones_controller.rb`).

- [ ] **Step 3: Delete the concern** `app/controllers/concerns/personal_workspace_context.rb`.

- [ ] **Step 4: Run the settings request + system specs** (`mise exec -- bundle exec rspec spec/requests/settings spec/system/settings`). Expect green — `/settings` pages still render (the `settings_navigation_helper:10` nil-guard returns `:personal`). Fix any spec that asserted `/settings` reflected the personal workspace's color/context (now the default — that's the intended honesty change).

- [ ] **Step 5: Confirm workspace-admin is untouched.** `mise exec -- bundle exec rspec spec/system/settings/org_context_spec.rb spec/requests/settings_sidebar_visibility_spec.rb` → green (the `:org` branch still renders on `/workspaces/:slug/*`).

- [ ] **Step 6: Full suite, commit.**

```bash
mise exec -- bundle exec rspec
git add app/controllers/settings app/controllers/concerns/personal_workspace_context.rb
git commit -m "refactor(settings): drop PersonalWorkspaceContext — /settings is account-independent (Current.workspace nil)"
```

---

## Task 2 — remove the redundant settings-sidebar switcher

- [ ] **Step 1: Find what asserts the switcher (RED guard).** `grep -rn "settings_sidebar_switcher\|settings-sidebar-switcher\|workspace-switcher" spec` and read the hits. Note which specs assert the *settings-sidebar* switcher (these will need updating) vs the *header* switcher from 2b (`#workspace-switcher-button` — leave those).

- [ ] **Step 2: Remove the switcher render** from `app/views/shared/_settings_sidebar_items.html.erb` (the `render "shared/settings_sidebar_switcher", …` block, ~L23–26). **Leave the `:personal` and `:org` item branches intact.**

- [ ] **Step 3: Delete the partial** `app/views/shared/_settings_sidebar_switcher.html.erb` (first `grep -rn "settings_sidebar_switcher" app` to confirm no remaining render).

- [ ] **Step 4: Clean up the layout local.** In `app/views/layouts/settings.html.erb`, the `workspaces: workspaces_scope` (and the mobile copy) were passed for the switcher — remove them if now unused by `_settings_sidebar_items` (grep the partial for `workspaces`). If `_settings_sidebar_items` no longer references `workspaces`, drop the local and the `workspaces_scope` call.

- [ ] **Step 5: Update the switcher-asserting specs** found in Step 1 — a settings page should NO LONGER show the in-sidebar switcher (assert its absence); switching is the header switcher's job (already covered by `spec/system/workspace_switcher_spec.rb`). Update `personal_context_spec` / any sidebar spec that asserted the switcher was present.

- [ ] **Step 6: Full suite green, commit.**

```bash
mise exec -- bundle exec rspec
git add -A
git commit -m "refactor(settings): remove the redundant settings-sidebar switcher (header switcher supersedes it)"
```

---

## Self-review

- **Polymorphism preserved** — the `:org` branch + workspace-admin specs are untouched; only the concern + switcher go.
- **`/settings` visibly unchanged** except: no in-sidebar switcher, and the default hue (both intended).
- **Honesty achieved** — `Current.workspace` is `nil` on `/settings` (account-independent), the personal-workspace lie removed.
- **Suite-driven** — the full suite catches any switcher/color assertion that needs updating; the org-context specs stay green throughout.
- **Not in scope** — the OKLCH "your workspace" ramp + the in-workspace "You're in [X]" banner are 2c-2.

## Execution handoff

1. **Subagent-Driven (recommended)** — implementer per task + review (the reviewer should confirm the `:org` branch + workspace-admin specs are untouched).
2. **Inline** — `superpowers:executing-plans`.
