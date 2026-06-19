# Workspace Settings IA — Phase 1: decouple the personal-workspace nav (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** A personal workspace's sidebar is **Overview · Projects** (no "Settings"); name/logo customization moves to a **Customize** affordance on the workspace Overview, edited in-place. Org workspaces are unchanged (Settings → workspace admin). Spec: `docs/superpowers/specs/2026-06-19-workspace-settings-ia-design.md`.

**Architecture:** Two surgical view changes plus the reused workspace-profile form. **No routing/layout restructure — that's Phase 2.** The workspace `#edit` page still uses `layout "settings"` after Phase 1, but Phase 1 makes it **unreachable via personal nav** (the Customize modal edits in-place on the Overview, in the workspace context), so the personal user never lands on the identity-sidebar page. The full fix to that page's context is Phase 2.

**Not in scope (verified):** no a11y change — the announcer already wires a static `data-settings-announcer-personal-value` (`app/views/layouts/settings.html.erb:26`) that `settings_announcer_controller.js` reads for `kind="personal"`. The panel's "announce personal" fix was investigated and found unnecessary.

**Tech Stack:** Rails 8.1 (`mise exec --` prefix on every ruby/rails/rspec/bundle command), RSpec (system specs use `sign_in_via_form`, request specs use `sign_in`), Hotwire (modal via `shared/_modal` + the existing `_identity_picker_hub`), modelrails_ui (semantic tokens, AAA, `focus-ring`). TDD; full suite green before every commit; commit but **DO NOT push**; never bypass Lefthook.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `app/views/shared/_workspace_sidebar_items.html.erb` | Modify (~L41–48) | gate the "Settings" item behind `unless current_workspace.personal?` |
| `app/views/workspaces/show.html.erb` | Modify (~L7–17) | a "Customize" affordance on the Overview header, personal workspaces only |
| `app/views/workspaces/_customize_modal.html.erb` | **Create** | the modal body — workspace name + logo editor, reusing the profile form / `_identity_picker_hub` |
| `config/locales/en/workspaces.en.yml` | Modify | `workspaces.overview.customize.*` labels |
| `spec/system/workspaces/sidebar_settings_label_spec.rb` (or similar) | Modify/Create | personal omits Settings; org keeps it |
| `spec/system/workspaces/customize_spec.rb` | **Create** | the Overview Customize flow (rename + logo, in-context) |

---

## Task 1 — hide "Settings" from the personal-workspace sidebar

**Files:** Modify `app/views/shared/_workspace_sidebar_items.html.erb`. Test: a request or system spec.

- [ ] **Step 1 — RED spec.** Assert a **personal**-workspace page's sidebar does NOT contain a link to `edit_workspace_path` (the "Settings" item), and an **org**-workspace page's sidebar DOES. A request spec is enough (the sidebar renders server-side). Example:

```ruby
require "rails_helper"

RSpec.describe "Workspace sidebar Settings item", type: :request do
  it "is hidden on a personal workspace" do
    user = create(:user)                       # :personal default → one personal workspace
    sign_in(user)
    get workspace_path(user.workspaces.kept.sole)
    expect(response.body).not_to include(edit_workspace_path(user.workspaces.kept.sole))
  end

  it "is shown on an org workspace" do
    user = create(:user)
    org = create(:workspace)                   # non-personal
    create(:membership, :owner, user: user, workspace: org)
    sign_in(user)
    get workspace_path(org)
    expect(response.body).to include(edit_workspace_path(org))
  end
end
```

- [ ] **Step 2:** run → FAIL (personal currently shows Settings).
- [ ] **Step 3 — implement.** Wrap the Settings item (currently ~L44–48) in a personal guard:

```erb
<% unless current_workspace.personal? %>
  <%# Org workspaces: "Settings" → workspace admin (Profile/Members/Invitations/Limits).
      Personal workspaces customize via the Overview instead (Phase 1). %>
  <%= render "shared/settings_sidebar_item",
        label: t("workspaces.sidebar.settings"),
        href: edit_workspace_path(current_workspace),
        icon: :cog,
        active: false %>
<% end %>
```

- [ ] **Step 4:** run → PASS. Run the existing workspace-sidebar / org-context specs → still green (org unaffected).
- [ ] **Step 5 — commit.**

```bash
mise exec -- bundle exec rspec <the new spec> spec/system/settings/org_context_spec.rb
git add app/views/shared/_workspace_sidebar_items.html.erb spec/...
git commit -m "feat(workspace-nav): hide Settings on personal workspaces (identity settings live in the avatar menu)"
```

---

## Task 2 — "Customize" affordance on the personal Overview

**Files:** Modify `app/views/workspaces/show.html.erb`; create `app/views/workspaces/_customize_modal.html.erb`; reuse `app/views/workspaces/_profile_section.html.erb` form pattern + `shared/_identity_picker_hub`. Test: `spec/system/workspaces/customize_spec.rb`.

- [ ] **Step 1 — RED spec** (system, `sign_in_via_form`): on a **personal** workspace Overview, a "Customize" control opens a modal with a name field; renaming + submitting updates the workspace name (assert the new name appears via Turbo, no full settings-layout navigation). Assert the modal also exposes the logo picker (the `_identity_picker_hub` trigger). Example skeleton:

```ruby
require "rails_helper"

RSpec.describe "Personal workspace Customize", type: :system do
  it "renames the workspace in-context from the Overview" do
    user = create(:user)
    sign_in_via_form(user)
    visit workspace_path(user.workspaces.kept.sole)
    click_on t("workspaces.overview.customize.open")     # the Customize button
    fill_in t("workspaces.overview.customize.name_label"), with: "My Stuff"
    click_on t("workspaces.overview.customize.save")
    expect(page).to have_css("h1", text: "My Stuff")
  end
end
```

- [ ] **Step 2:** run → FAIL (no Customize control yet).
- [ ] **Step 3 — implement.** In `show.html.erb`, for `@workspace.personal?`, add a "Customize" button in the header area (~L7–17, beside the name/plan) that opens a `shared/_modal` whose body is `workspaces/_customize_modal`. The modal reuses the existing workspace-profile editing: a `form_with model: @workspace, url: workspace_path(@workspace), method: :patch` for the **name**, plus the **logo** via the existing `_identity_picker_hub` trigger (the same component `_profile_section` uses). **Compose the nesting cleanly:** the logo picker is itself a modal/turbo-frame — render the name field inline in the Customize modal and let the logo control open the hub (mirror how `_profile_section.html.erb` wires the logo button), rather than nesting two `shared/_modal`s. Keep it in the workspace (Overview) context — do NOT link to `edit_workspace_path` (that page still uses `layout "settings"` until Phase 2). Use semantic tokens, `focus-ring`, AAA; `data-slot` per the design system.

- [ ] **Step 4 — locale.** Add `workspaces.overview.customize.{open,name_label,save,...}` to `config/locales/en/workspaces.en.yml`.

- [ ] **Step 5:** run → PASS. Manually confirm the logo picker opens and a rename persists.

- [ ] **Step 6 — full suite green; commit.**

```bash
mise exec -- bundle exec rspec
git add app/views/workspaces/show.html.erb app/views/workspaces/_customize_modal.html.erb config/locales/en/workspaces.en.yml spec/system/workspaces/customize_spec.rb
git commit -m "feat(workspace): personal-workspace Customize (rename + logo) on the Overview, in-context"
```

---

## Self-review

- Personal sidebar = **Overview · Projects**; org unchanged (Settings → admin).
- The personal user edits name/logo in the **workspace** context (the Overview modal) — never the identity-sidebar edit page.
- **No a11y change** (verified unnecessary — static personal announcer value already present).
- The `/workspaces/:slug/edit` page still uses `layout "settings"` (Phase 2 fixes its context) but is **off the personal nav path** — only reachable by direct URL until Phase 2.
- AAA is CI-only — push and read CI for the Customize modal's contrast.

## Execution handoff

1. **Subagent-Driven (recommended)** — implementer per task + two-stage review.
2. **Inline** — `superpowers:executing-plans`.
