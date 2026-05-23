# Settings Hub Phase 2: Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [docs/superpowers/specs/2026-05-19-settings-hub-design.md](../specs/2026-05-19-settings-hub-design.md) — Phase 2 row.

**Goal:** Ship the Settings hub navigational shell — a sidebar-equipped layout that wraps existing settings destinations with a context-adaptive item list, Pundit-gated visibility, an `aria-live` region for context-change announcements, and Turbo morph navigation. Destination page content is unchanged in this phase (Phase 3's job).

**Architecture:**

- New `layouts/settings.html.erb` wraps an existing application chrome with a sidebar containing the workspace switcher (sidebar variant) and a context-adaptive item list. All settings-tier controllers opt in via `layout "settings"`.
- Sidebar items are partials, not ViewComponents (matches project's partial-with-strict-locals convention). A new `SettingsNavigationHelper` exposes `nav_item_if_permitted(record, action:)` that consults the same Pundit policies the destination controllers use — single source of truth for visibility.
- A new `PersonalWorkspaceContext` controller concern sets `Current.workspace = current_user.personal_workspace` on `/account/*` routes so the sidebar/policies treat personal pages uniformly with org pages.
- Turbo morph (`turbo_refreshes_with method: :morph`) is enabled site-wide so the workspace switcher's full visit keeps focus/scroll across context changes. `Membership` broadcasts a refresh on role updates so demoted users re-render automatically.

**Tech Stack:** Rails 8.1, Pundit, TailwindCSS 4 (OKLCH tokens), Hotwire (Turbo morph + Stimulus `dropdown` controller already in repo), RSpec + Capybara + Playwright + axe-core (WCAG 2.2 AAA).

**Out of scope (deferred to Phase 3+):**

- Per-destination page redesign (Profile H1/aria-label disambiguation, shared page skeleton)
- OKLCH personal-context token ramp (`[data-workspace-kind="personal"]`)
- Visual differentiation polish (avatar shape, chroma-boosted swatch, transition animations, hover prefetch)
- Route consolidation (deleting `BrandingController`, moving identity to `workspaces#edit`)
- Hiding personal workspace from the *header* switcher

**Branch:** `feat/settings-hub-phase-2-shell` (created off `docs/settings-hub-spec`, which will be merged to `main` separately).

---

## File Map

**Create:**

- `app/controllers/concerns/personal_workspace_context.rb` — sets `Current.workspace = current_user.personal_workspace` for account-tier controllers
- `app/helpers/settings_navigation_helper.rb` — `nav_item_if_permitted` + `settings_context_kind` (returns `:personal` or `:org`)
- `app/views/layouts/settings.html.erb` — settings hub layout (sidebar + main + aria-live region)
- `app/views/shared/_settings_sidebar.html.erb` — top-level sidebar partial (switcher + item list)
- `app/views/shared/_settings_sidebar_switcher.html.erb` — sidebar variant of workspace switcher (always-open list)
- `app/views/shared/_settings_sidebar_item.html.erb` — single sidebar item (icon + label + active state + aria-label)
- `spec/models/user_spec.rb` — add `personal_workspace` examples (file likely exists; append)
- `spec/helpers/settings_navigation_helper_spec.rb` — helper unit spec
- `spec/system/settings/personal_context_spec.rb` — personal context shell + sidebar happy path + axe AAA
- `spec/system/settings/org_context_spec.rb` — org context shell + Owner/Viewer Pundit gating + axe AAA
- `spec/system/settings/demotion_while_viewing_spec.rb` — admin demoted mid-session, Turbo refresh + redirect

**Modify:**

- `app/models/user.rb` — add `personal_workspace` reader
- `app/models/current.rb` — no code change; documented as the source of truth (the concern sets `Current.workspace`)
- `app/controllers/application_controller.rb` — no change required if account controllers each include the concern; otherwise see Task 3
- `app/controllers/account/profiles_controller.rb` — include `PersonalWorkspaceContext`, set `layout "settings"`
- `app/controllers/account/notification_preferences_controller.rb` — same
- `app/controllers/account/connected_accounts_controller.rb` — same
- `app/controllers/account/theme_preferences_controller.rb` — same
- `app/controllers/account/preferences/timezones_controller.rb` — same
- `app/controllers/workspaces_controller.rb` — `layout "settings", only: [:edit, :update]`
- `app/controllers/workspaces/settings_controller.rb` — `layout "settings"`
- `app/controllers/workspaces/branding_controller.rb` — `layout "settings"`
- `app/controllers/workspaces/members_controller.rb` — `layout "settings"`
- `app/controllers/workspaces/invitations_controller.rb` — `layout "settings"`
- `config/locales/en.yml` — add `settings.hub.*` and `settings.sidebar.*` keys
- `app/views/layouts/application.html.erb` — add `<%= turbo_refreshes_with method: :morph %>` (one line in `<head>`)
- `app/models/membership.rb` — opt into `Broadcastable` for `:update` events (broadcasts on role change)

---

## Task 1: User#personal_workspace reader

**Files:**

- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/models/user_spec.rb` inside the top-level `describe User do` block:

```ruby
describe "#personal_workspace" do
  let(:user) { create(:user) }

  it "returns the kept workspace flagged personal: true" do
    personal = user.workspaces.find_by!(personal: true)
    expect(user.personal_workspace).to eq(personal)
  end

  it "returns nil if the personal workspace has been soft-deleted" do
    user.workspaces.find_by!(personal: true).discard
    expect(user.personal_workspace).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/user_spec.rb -e "personal_workspace"`
Expected: FAIL with `NoMethodError: undefined method 'personal_workspace'` (or `nil.eq?` if a stub returns nil).

- [ ] **Step 3: Write minimal implementation**

In `app/models/user.rb`, add inside the class body (near other workspace-related methods):

```ruby
def personal_workspace
  workspaces.kept.find_by(personal: true)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/user_spec.rb -e "personal_workspace"`
Expected: both examples PASS.

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec`
Expected: all green (zero failures, zero unexpected pendings). If any pending exists that wasn't pending on `main`, investigate (see memory `feedback_investigate_pending_tests.md`).

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "feat(user): add personal_workspace reader

Returns the kept workspace flagged personal: true. Used by
PersonalWorkspaceContext to set Current.workspace on /account/* routes."
```

---

## Task 2: PersonalWorkspaceContext concern

**Files:**

- Create: `app/controllers/concerns/personal_workspace_context.rb`
- Test: `spec/requests/concerns/personal_workspace_context_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/requests/concerns/personal_workspace_context_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PersonalWorkspaceContext, type: :request do
  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  it "sets Current.workspace to the user's personal workspace during the request" do
    get edit_account_profile_path

    expect(response).to have_http_status(:ok)
    # The page should render fine and the layout should have read Current.workspace.
    # We assert via a sentinel that the layout writes when Current.workspace is set:
    expect(response.body).to include("data-settings-context-kind=\"personal\"")
  end
end
```

> **Note:** The `sign_in_via_form` helper is defined in `spec/support/`. The `data-settings-context-kind` attribute lands on `<main>` in `layouts/settings.html.erb` (Task 9) and reads `:personal` when `Current.workspace.personal?` is true.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/concerns/personal_workspace_context_spec.rb`
Expected: FAIL — body does not include `data-settings-context-kind` because the layout isn't wired yet. This test will go green after Tasks 9 + 10 land; for now, write it but mark with a `pending` if you need to commit before then. Preferred path: write Tasks 2–10 as a single sequence, then commit each as it passes individually.

- [ ] **Step 3: Write the concern**

Create `app/controllers/concerns/personal_workspace_context.rb`:

```ruby
module PersonalWorkspaceContext
  extend ActiveSupport::Concern

  included do
    before_action :set_personal_workspace
  end

  private

  def set_personal_workspace
    Current.workspace = Current.user&.personal_workspace
  end
end
```

- [ ] **Step 4: Verify the concern in isolation**

Add a minimal example to the same spec file that doesn't depend on the layout:

```ruby
it "sets Current.workspace before the controller action runs" do
  controller_class = Class.new(ApplicationController) do
    include PersonalWorkspaceContext
    def index = render(plain: Current.workspace&.id.to_s)
  end
  stub_const("DummyController", controller_class)
  Rails.application.routes.draw do
    get "/dummy" => "dummy#index"
    # NOTE: redrawing routes inline is fragile — see alternative below
  end
  get "/dummy"
  expect(response.body).to eq(user.personal_workspace.id.to_s)
ensure
  Rails.application.reload_routes!
end
```

If route-redrawing in-test is too fragile in this project, skip this micro-example and rely on the integration assertion in Task 10's request spec. Pick one — don't keep both.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/personal_workspace_context.rb spec/requests/concerns/personal_workspace_context_spec.rb
git commit -m "feat(controllers): add PersonalWorkspaceContext concern

Sets Current.workspace to current_user.personal_workspace before each
action. Account controllers include this so the Settings hub layout
can render personal-context sidebar items via the same code path as
org-context (Current.workspace works uniformly)."
```

---

## Task 3: SettingsNavigationHelper

**Files:**

- Create: `app/helpers/settings_navigation_helper.rb`
- Test: `spec/helpers/settings_navigation_helper_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/helpers/settings_navigation_helper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SettingsNavigationHelper, type: :helper do
  describe "#settings_context_kind" do
    it "returns :personal when Current.workspace.personal? is true" do
      personal = build_stubbed(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(personal)
      expect(helper.settings_context_kind).to eq(:personal)
    end

    it "returns :org when Current.workspace.personal? is false" do
      org = build_stubbed(:workspace, personal: false)
      allow(Current).to receive(:workspace).and_return(org)
      expect(helper.settings_context_kind).to eq(:org)
    end

    it "returns :personal when Current.workspace is nil (safe default for unauthenticated edge)" do
      allow(Current).to receive(:workspace).and_return(nil)
      expect(helper.settings_context_kind).to eq(:personal)
    end
  end

  describe "#nav_item_if_permitted" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }

    before do
      allow(helper).to receive(:current_user).and_return(user)
      allow(Current).to receive(:user).and_return(user)
      allow(Current).to receive(:workspace).and_return(workspace)
    end

    it "yields when the policy permits the action" do
      allow(WorkspacePolicy).to receive(:new)
        .with(user, workspace).and_return(instance_double(WorkspacePolicy, edit?: true))

      output = helper.nav_item_if_permitted(workspace, action: :edit?) { "RENDERED" }
      expect(output).to eq("RENDERED")
    end

    it "returns nil when the policy denies the action" do
      allow(WorkspacePolicy).to receive(:new)
        .with(user, workspace).and_return(instance_double(WorkspacePolicy, edit?: false))

      output = helper.nav_item_if_permitted(workspace, action: :edit?) { "RENDERED" }
      expect(output).to be_nil
    end

    it "infers the policy class from the record" do
      membership = create(:membership, user: user, workspace: workspace)
      allow(MembershipPolicy).to receive(:new)
        .with(user, membership).and_return(instance_double(MembershipPolicy, index?: true))

      output = helper.nav_item_if_permitted(membership, action: :index?) { "RENDERED" }
      expect(output).to eq("RENDERED")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/helpers/settings_navigation_helper_spec.rb`
Expected: FAIL — `uninitialized constant SettingsNavigationHelper`.

- [ ] **Step 3: Write the helper**

Create `app/helpers/settings_navigation_helper.rb`:

```ruby
module SettingsNavigationHelper
  def settings_context_kind
    Current.workspace&.personal? ? :personal : (Current.workspace ? :org : :personal)
  end

  def nav_item_if_permitted(record, action:, &block)
    return nil unless block_given?

    policy = Pundit.policy(current_user, record)
    return nil unless policy.public_send(action)

    capture(&block)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/helpers/settings_navigation_helper_spec.rb`
Expected: all examples PASS.

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/helpers/settings_navigation_helper.rb spec/helpers/settings_navigation_helper_spec.rb
git commit -m "feat(helpers): add SettingsNavigationHelper

settings_context_kind returns :personal or :org based on
Current.workspace. nav_item_if_permitted gates a block of sidebar
markup on the same Pundit policy/action the destination controller
authorizes against — single source of truth, no SidebarPolicy."
```

---

## Task 4: I18n keys for sidebar

**Files:**

- Modify: `config/locales/en.yml`

- [ ] **Step 1: Inspect current shape**

Run: `grep -n "^settings:" config/locales/en.yml || echo "no settings: block yet"`
Expected: either confirmation no `settings:` block exists, or its current location.

- [ ] **Step 2: Add the keys**

Append (or merge if `settings:` exists) to `config/locales/en.yml`:

```yaml
settings:
  sidebar:
    aria_label: "Settings navigation"
    aria_live_template:
      personal: "Switched to your personal workspace. Settings menu updated: Profile, Notifications, Security, Appearance."
      org: "Switched to %{name}, %{role}. Settings menu updated: %{items}."
    items:
      profile: "Profile"
      notifications: "Notifications"
      security: "Security"
      appearance: "Appearance"
      members: "Members"
      invitations: "Invitations"
      limits_and_plan: "Limits & Plan"
    aria_labels:
      profile_personal: "Profile, personal workspace"
      profile_org: "Profile, %{workspace_name}"
      members: "Members of %{workspace_name}"
      invitations: "Invitations for %{workspace_name}"
      limits_and_plan: "Limits and plan for %{workspace_name}"
```

- [ ] **Step 3: Verify locale loads without YAML error**

Run: `bundle exec rails runner "puts I18n.t('settings.sidebar.items.profile')"`
Expected: prints `Profile`. If it raises, you have a YAML indentation bug — fix before continuing.

- [ ] **Step 4: Commit**

```bash
git add config/locales/en.yml
git commit -m "feat(i18n): add settings.sidebar.* keys

Sidebar labels, aria-labels for context-disambiguated links, and the
aria-live announcement template for context changes."
```

---

## Task 5: Settings sidebar item partial

**Files:**

- Create: `app/views/shared/_settings_sidebar_item.html.erb`

> **Note on testing:** This partial is exercised end-to-end by the system specs in Tasks 12–14. No isolated render spec — the partial is too small to warrant one.

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_settings_sidebar_item.html.erb`:

```erb
<%# locals: (label:, href:, aria_label: nil, active: false, icon: nil) -%>
<li>
  <%= link_to href,
        aria: { label: aria_label, current: ("page" if active) },
        data: { turbo_prefetch: "true" },
        class: [
          "min-h-[44px] flex items-center gap-3 px-3 py-2 rounded-md",
          "text-text-body",
          "hover:bg-surface-sunken",
          "focus:outline-none focus:ring-2 focus:ring-interactive-focus",
          ("bg-surface-sunken font-semibold text-text-heading" if active)
        ].compact do %>
    <% if icon %>
      <span class="shrink-0" aria-hidden="true"><%= icon(icon, size: :sm) %></span>
    <% end %>
    <span><%= label %></span>
  <% end %>
</li>
```

> **Why `min-h-[44px]`:** WCAG 2.2 AAA target-size criterion (2.5.5 enhanced). Touch targets ≥44×44px. The padding plus min-height ensures both axes meet the bar.

> **Why `aria-current="page"`:** screen readers announce the active item; visual `bg-surface-sunken` mirrors it. Per AAA 1.4.1 (use of color), this is not color-alone — `font-semibold` and `aria-current` both differentiate.

- [ ] **Step 2: Sanity check by rendering once**

Run: `bundle exec rails runner 'puts ActionController::Base.render(partial: "shared/settings_sidebar_item", locals: { label: "Profile", href: "/account/profile/edit" })'`
Expected: prints HTML containing `Profile` and `/account/profile/edit`. If it raises about missing `icon` helper, that's expected — the helper exists in app context; this CLI render is just a smoke check.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_settings_sidebar_item.html.erb
git commit -m "feat(views): add settings sidebar item partial

Single link row with 44x44 min target, aria-current=page when active,
turbo prefetch on hover, optional leading icon, and aria-label slot
for context-disambiguated labels."
```

---

## Task 6: Settings sidebar workspace switcher partial

**Files:**

- Create: `app/views/shared/_settings_sidebar_switcher.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_settings_sidebar_switcher.html.erb`:

```erb
<%# locals: (workspaces:, current_workspace:) -%>
<nav aria-label="<%= t("settings.sidebar.aria_label") %>"
     class="mb-4 pb-4 border-b border-border">
  <ul role="list" class="flex flex-col gap-1">
    <% workspaces.each do |workspace| %>
      <% is_current = workspace == current_workspace %>
      <% role_slug = workspace.memberships.detect { |m| m.user_id == Current.user.id }&.role&.slug %>
      <li>
        <%= link_to workspace_path(workspace),
              aria: { current: ("true" if is_current),
                      label: "#{workspace.name}#{', personal workspace' if workspace.personal?}" },
              data: { turbo_prefetch: "true" },
              class: [
                "min-h-[44px] flex items-center gap-3 px-3 py-2 rounded-md",
                "text-text-body",
                "hover:bg-surface-sunken",
                "focus:outline-none focus:ring-2 focus:ring-interactive-focus",
                ("bg-surface-sunken font-semibold text-text-heading" if is_current)
              ].compact do %>
          <%# Avatar shape: circle = personal, rounded square = org (WCAG 1.4.1: not color-alone) %>
          <span class="<%= workspace.personal? ? "rounded-full" : "rounded-md" %> shrink-0">
            <%= workspace_icon_for(workspace, size: :sm) %>
          </span>
          <span class="flex-1 min-w-0">
            <span class="block truncate"><%= workspace.name %></span>
            <% if role_slug %>
              <span class="block text-xs text-text-muted"><%= role_slug.titleize %></span>
            <% end %>
          </span>
        <% end %>
      </li>
    <% end %>
  </ul>
</nav>
```

> **Why sidebar variant, not dropdown:** spec mandates "always-open, current-item highlight" for the sidebar variant. Dropdown is the header form.

> **Why circle vs rounded-square avatar shape:** WCAG 1.4.1 (use of color) — visual differentiation must not rely on hue alone. Slack/Linear/GitHub convention: circle = person, square = org.

- [ ] **Step 2: Commit**

```bash
git add app/views/shared/_settings_sidebar_switcher.html.erb
git commit -m "feat(views): add sidebar workspace switcher partial

Always-open inline list (sidebar variant). Renders personal + org
workspaces with circle/rounded-square avatar shape per WCAG 1.4.1.
Current item gets aria-current=true and visual emphasis."
```

---

## Task 7: Settings sidebar (top-level)

**Files:**

- Create: `app/views/shared/_settings_sidebar.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_settings_sidebar.html.erb`:

```erb
<%# locals: (workspaces:, current_workspace:) -%>
<aside aria-label="<%= t("settings.sidebar.aria_label") %>"
       class="w-64 shrink-0 px-4 py-6 border-r border-border bg-surface">
  <%= render "shared/settings_sidebar_switcher",
        workspaces: workspaces,
        current_workspace: current_workspace %>

  <ul role="list" class="flex flex-col gap-1">
    <% if settings_context_kind == :personal %>
      <%= render "shared/settings_sidebar_item",
            label: t("settings.sidebar.items.profile"),
            href: edit_account_profile_path,
            aria_label: t("settings.sidebar.aria_labels.profile_personal"),
            active: current_page?(edit_account_profile_path) %>

      <%= render "shared/settings_sidebar_item",
            label: t("settings.sidebar.items.notifications"),
            href: edit_account_notification_preferences_path,
            active: current_page?(edit_account_notification_preferences_path) %>

      <%= render "shared/settings_sidebar_item",
            label: t("settings.sidebar.items.security"),
            href: account_connected_accounts_path,
            active: current_page?(account_connected_accounts_path) %>

      <%= render "shared/settings_sidebar_item",
            label: t("settings.sidebar.items.appearance"),
            href: account_theme_preference_path,
            active: current_page?(account_theme_preference_path) %>
    <% else %>
      <%= nav_item_if_permitted(current_workspace, action: :update?) do %>
        <%= render "shared/settings_sidebar_item",
              label: t("settings.sidebar.items.profile"),
              href: edit_workspace_path(current_workspace),
              aria_label: t("settings.sidebar.aria_labels.profile_org",
                            workspace_name: current_workspace.name),
              active: current_page?(edit_workspace_path(current_workspace)) %>
      <% end %>

      <%= nav_item_if_permitted(Membership.new(workspace: current_workspace), action: :index?) do %>
        <%= render "shared/settings_sidebar_item",
              label: t("settings.sidebar.items.members"),
              href: workspace_members_path(current_workspace),
              aria_label: t("settings.sidebar.aria_labels.members",
                            workspace_name: current_workspace.name),
              active: current_page?(workspace_members_path(current_workspace)) %>
      <% end %>

      <%= nav_item_if_permitted(Invitation.new(workspace: current_workspace), action: :index?) do %>
        <%= render "shared/settings_sidebar_item",
              label: t("settings.sidebar.items.invitations"),
              href: workspace_invitations_path(current_workspace),
              aria_label: t("settings.sidebar.aria_labels.invitations",
                            workspace_name: current_workspace.name),
              active: current_page?(workspace_invitations_path(current_workspace)) %>
      <% end %>

      <%# Limits & Plan reuses workspaces/settings#edit (operational config) %>
      <%= nav_item_if_permitted(current_workspace, action: :update?) do %>
        <%= render "shared/settings_sidebar_item",
              label: t("settings.sidebar.items.limits_and_plan"),
              href: edit_workspace_settings_path(current_workspace),
              aria_label: t("settings.sidebar.aria_labels.limits_and_plan",
                            workspace_name: current_workspace.name),
              active: current_page?(edit_workspace_settings_path(current_workspace)) %>
      <% end %>
    <% end %>
  </ul>
</aside>
```

> **Why `current_workspace` is passed in vs read from `Current.workspace`:** strict locals make the contract explicit, and the layout (Task 9) controls preloading so the sidebar never re-queries.

> **Why `Membership.new(workspace: ...)` for the policy probe:** `MembershipPolicy#index?` checks `membership.present?` for the current user — that needs the workspace context. The Pundit instance receives a record-shaped object; an unpersisted instance is fine because the policy reads `record.workspace` (which we provide), not persisted state.

> **Note on Invitation policy:** verify `InvitationPolicy#index?` exists with similar semantics. If it doesn't, gate on `WorkspacePolicy` with `:update?` instead (Owner/Admin only). Confirm during this task; do not skip.

- [ ] **Step 2: Verify InvitationPolicy semantics**

Run: `cat app/policies/invitation_policy.rb 2>/dev/null || echo "no InvitationPolicy"`

If the policy doesn't exist or lacks `index?`, swap the second `nav_item_if_permitted` block to gate on `current_workspace` + `:update?` (Owner/Admin) — that's the spec's intent ("Invitations management" is admin-only). Edit the partial accordingly before continuing.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_settings_sidebar.html.erb
git commit -m "feat(views): add context-adaptive settings sidebar partial

Renders personal-context items (Profile/Notifications/Security/
Appearance) or org-context items (Profile/Members/Invitations/
Limits & Plan) based on settings_context_kind. Org items are gated
through nav_item_if_permitted using the same Pundit policies the
destination controllers authorize against."
```

---

## Task 8: Settings hub layout

**Files:**

- Create: `app/views/layouts/settings.html.erb`

- [ ] **Step 1: Read the existing application layout for reference**

Read `app/views/layouts/application.html.erb` fully. Identify:
- The `<head>` block (Turbo, stylesheets, theme script, meta tags)
- The header partial render
- The `<main>` wrapper attributes (`data-workspace-branded`, OKLCH style hue)
- The toasts partial
- The footer partial

You'll replicate the chrome and inject the sidebar between header and main content.

- [ ] **Step 2: Create the layout**

Create `app/views/layouts/settings.html.erb`. The bulk reuses the application layout's chrome; the differentiation is the `<div class="flex">` wrapper that puts sidebar + main side-by-side. The exact contents of `<head>` and `<header>` should be **rendered from a shared partial** to avoid duplication — but since `application.html.erb` doesn't currently extract them, copy the structure verbatim and file a follow-up issue to deduplicate.

Skeleton (fill in `<head>` / `<header>` / `<footer>` by mirroring `application.html.erb` exactly — do not paraphrase):

```erb
<!DOCTYPE html>
<html lang="en" class="<%= theme_html_classes %>">
  <head>
    <%# COPY THE ENTIRE <head> BLOCK FROM application.html.erb VERBATIM %>
    <%# Add this line (Turbo morph) if it isn't already present in application.html.erb: %>
    <%= turbo_refreshes_with method: :morph %>
  </head>
  <body class="bg-surface text-text-body">
    <%# Polite aria-live region for context-change announcements (WCAG 4.1.3) %>
    <div id="settings-aria-live"
         role="status"
         aria-live="polite"
         aria-atomic="true"
         class="sr-only"
         data-controller="settings-announcer">
    </div>

    <%= render "shared/header" %>

    <div class="flex min-h-[calc(100vh-var(--header-height,4rem))]"
         data-settings-context-kind="<%= settings_context_kind %>">
      <%= render "shared/settings_sidebar",
            workspaces: Current.user.workspaces.kept.includes(:roles, memberships: :role),
            current_workspace: Current.workspace %>

      <main id="main" class="flex-1 px-6 py-8">
        <%= render "shared/toasts" %>
        <%= yield %>
      </main>
    </div>

    <%= render "shared/footer" %>
  </body>
</html>
```

> **Why aria-live in the layout (not in a partial of its own):** the announcement is owned by the layout context. A separate partial would invite copy-paste into pages.

> **Why `sr-only` on the live region:** SR-only is the standard pattern for polite announcements without visual noise. Tailwind ships `sr-only` (clip + position:absolute) — no custom CSS needed.

> **Where does the announcement text come from in Phase 2?** A Stimulus controller (`settings-announcer`) writes the localized string from `t("settings.sidebar.aria_live_template.<kind>")` after a Turbo morph completes. We're not building that controller in this task — Task 11 enables Turbo morph; an empty announcer region today is fine. Phase 2 ships the *region*; activating it is left as a small follow-up in this same phase (Task 11).

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/settings.html.erb
git commit -m "feat(layouts): add settings hub layout

Wraps existing chrome (header, footer, toasts) and inserts a sidebar
(shared/settings_sidebar) plus a polite aria-live region for context-
change announcements. data-settings-context-kind attribute exposes
:personal/:org to CSS for Phase 4 token differentiation."
```

---

## Task 9: Account controllers opt into the settings layout

**Files:**

- Modify: each `app/controllers/account/*_controller.rb`

Five controllers, all the same edit. Do them as one commit at the end — atomic feature toggle.

- [ ] **Step 1: Modify `app/controllers/account/profiles_controller.rb`**

Add at the top of the class body:

```ruby
include PersonalWorkspaceContext
layout "settings"
```

- [ ] **Step 2: Repeat the edit for these controllers** (same two lines, same position):

- `app/controllers/account/notification_preferences_controller.rb`
- `app/controllers/account/connected_accounts_controller.rb`
- `app/controllers/account/theme_preferences_controller.rb`
- `app/controllers/account/preferences/timezones_controller.rb`

> **Decision: per-controller include vs base class.** A `Account::BaseController` would DRY this, but the project pattern (visible in `app/controllers/account/`) is flat controllers inheriting `ApplicationController`. Five `include`s is fine; introducing a base class is a separate refactor, file an issue if you think it warrants one.

- [ ] **Step 3: Run the request spec from Task 2 now that the layout is wired**

Run: `bundle exec rspec spec/requests/concerns/personal_workspace_context_spec.rb`
Expected: the integration example asserting `data-settings-context-kind="personal"` PASSES.

If it fails, the most likely cause is the layout's `<head>` block missing pieces from `application.html.erb` that affect rendering. Diff the two layouts.

- [ ] **Step 4: Run full suite**

Run: `bundle exec rspec`
Expected: all green. Some existing system specs for account pages may break because they now render the sidebar (layout change). Triage:
- If a spec was asserting absence of certain markup → update the spec, the new markup is correct.
- If a spec was asserting presence of markup that's still present → bug in the layout, fix it.

This is the highest-risk task in the plan — review failures carefully before patching specs.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/account/
git commit -m "feat(account): render account settings in settings hub layout

Each account controller includes PersonalWorkspaceContext (so
Current.workspace == personal workspace) and sets layout 'settings'.
Existing /account/* URLs unchanged; visual frame now includes the
sidebar and aria-live region."
```

---

## Task 10: Workspaces settings-tier controllers opt into the layout

**Files:**

- Modify: `app/controllers/workspaces_controller.rb`
- Modify: `app/controllers/workspaces/settings_controller.rb`
- Modify: `app/controllers/workspaces/branding_controller.rb`
- Modify: `app/controllers/workspaces/members_controller.rb`
- Modify: `app/controllers/workspaces/invitations_controller.rb`

- [ ] **Step 1: Modify `app/controllers/workspaces_controller.rb`**

Add inside the class body (these controllers already set `Current.workspace` via `WorkspaceScoped` — no concern needed here):

```ruby
layout "settings", only: [:edit, :update]
```

The `show`/`index` actions keep the application layout (workspace dashboard, not settings).

- [ ] **Step 2: Add `layout "settings"` to each of the four `Workspaces::*` controllers**

For each of `settings_controller`, `branding_controller`, `members_controller`, `invitations_controller`, add:

```ruby
layout "settings"
```

(No `only:` constraint — these controllers' actions are all settings-tier.)

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec`
Expected: all green. Workspaces system specs (`brandings_spec.rb`, `invitations_spec.rb`, etc.) may need updates for the same reasons as Task 9 step 4.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/workspaces_controller.rb app/controllers/workspaces/
git commit -m "feat(workspaces): render workspace settings in settings hub layout

WorkspacesController#edit + Workspaces::{settings,branding,members,
invitations} controllers set layout 'settings'. Org-context sidebar
items render with Pundit gating via nav_item_if_permitted."
```

---

## Task 11: Turbo morph site-wide + aria-live announcer

**Files:**

- Modify: `app/views/layouts/application.html.erb`
- Create: `app/javascript/controllers/settings_announcer_controller.js`
- Modify: `app/javascript/controllers/index.js` (if it manually registers controllers; skip if it's `eagerLoad`)

- [ ] **Step 1: Add `turbo_refreshes_with` to the application layout**

In `app/views/layouts/application.html.erb`, inside `<head>`, add (if not already present):

```erb
<%= turbo_refreshes_with method: :morph %>
```

> **Why this lives in `application.html.erb` and not just `settings.html.erb`:** Turbo morph is harmless for non-settings pages and consistent behavior site-wide is preferable to conditional morphing. Per spec: "Use `<%= turbo_refreshes_with method: :morph %>` site-wide".

- [ ] **Step 2: Create the announcer Stimulus controller**

Create `app/javascript/controllers/settings_announcer_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    personal: String,
    org: String,
  }

  connect() {
    this.boundOnRender = this.onRender.bind(this)
    document.addEventListener("turbo:render", this.boundOnRender)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundOnRender)
  }

  onRender() {
    const main = document.querySelector("[data-settings-context-kind]")
    if (!main) return

    const kind = main.dataset.settingsContextKind
    const template = this[`${kind}Value`]
    if (!template) return

    // Write the announcement so screen readers pick it up.
    this.element.textContent = ""
    requestAnimationFrame(() => { this.element.textContent = template })
  }
}
```

- [ ] **Step 3: Update the layout to pass announcement templates as values**

In `app/views/layouts/settings.html.erb`, replace the announcer div with:

```erb
<div id="settings-aria-live"
     role="status"
     aria-live="polite"
     aria-atomic="true"
     class="sr-only"
     data-controller="settings-announcer"
     data-settings-announcer-personal-value="<%= t("settings.sidebar.aria_live_template.personal") %>"
     data-settings-announcer-org-value="<%= current_workspace_announcement_for_aria_live %>">
</div>
```

Add to `app/helpers/settings_navigation_helper.rb`:

```ruby
def current_workspace_announcement_for_aria_live
  return nil unless Current.workspace && !Current.workspace.personal?

  membership = Current.workspace.memberships.detect { |m| m.user_id == Current.user.id }
  role = membership&.role&.slug&.titleize || "Member"

  items = if Pundit.policy(current_user, Current.workspace).update?
    "Profile, Members, Invitations, Limits and Plan"
  else
    "Profile"
  end

  I18n.t("settings.sidebar.aria_live_template.org",
         name: Current.workspace.name, role: role, items: items)
end
```

- [ ] **Step 4: Run full suite**

Run: `bundle exec rspec`
Expected: all green. If the helper spec from Task 3 needs updates for the new method, add examples there.

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/layouts/settings.html.erb \
        app/javascript/controllers/settings_announcer_controller.js \
        app/helpers/settings_navigation_helper.rb \
        spec/helpers/settings_navigation_helper_spec.rb
git commit -m "feat(turbo): site-wide morph + aria-live context announcer

turbo_refreshes_with :morph in application layout (focus/scroll
preserved across navigation, broadcasts can trigger refresh in any
open tab). Settings hub layout exposes a polite aria-live region;
settings-announcer Stimulus controller writes a localized
context-change announcement on turbo:render."
```

---

## Task 12: Membership broadcasts on role change

**Files:**

- Modify: `app/models/membership.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/models/membership_spec.rb` (create the file if it doesn't exist):

```ruby
describe "broadcasts" do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let(:membership) { create(:membership, user: user, workspace: workspace) }

  it "broadcasts a refresh when the role changes" do
    expect { membership.update!(role: create(:role, slug: "viewer", workspace: workspace)) }
      .to have_broadcasted_to(membership).from_channel(Turbo::StreamsChannel)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/membership_spec.rb -e "broadcasts"`
Expected: FAIL — no broadcasts.

- [ ] **Step 3: Add Broadcastable to Membership**

In `app/models/membership.rb`, add near the top:

```ruby
include Broadcastable

def self.broadcast_events
  [:update]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/membership_spec.rb -e "broadcasts"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/membership.rb spec/models/membership_spec.rb
git commit -m "feat(membership): broadcast refresh on role change

Membership includes Broadcastable for :update events. When an admin
demotes a member, every open tab subscribed to that membership stream
re-renders via Turbo morph — sidebar visibility updates without a
page reload (WCAG-friendly: focus and scroll preserved)."
```

---

## Task 13: System spec — personal context happy path

**Files:**

- Create: `spec/system/settings/personal_context_spec.rb`

- [ ] **Step 1: Inspect a sibling spec to mirror its structure**

Read `spec/system/workspaces/brandings_spec.rb` to confirm the project's idioms for:
- driver setup (`driven_by :playwright` or via shared config)
- sign-in helper name (`sign_in_via_form` vs `sign_in_as`)
- axe helper invocation
- expectation style for Turbo morph completion

- [ ] **Step 2: Write the spec**

Create `spec/system/settings/personal_context_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Settings hub — personal context", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { sign_in_via_form(user) }

  it "renders the personal-context sidebar with all user-tier items" do
    visit edit_account_profile_path

    within("aside[aria-label='Settings navigation']") do
      expect(page).to have_link("Profile")
      expect(page).to have_link("Notifications")
      expect(page).to have_link("Security")
      expect(page).to have_link("Appearance")

      expect(page).not_to have_link("Members")
      expect(page).not_to have_link("Invitations")
      expect(page).not_to have_link("Limits & Plan")
    end
  end

  it "exposes the personal context via data attribute" do
    visit edit_account_profile_path
    expect(page).to have_css("[data-settings-context-kind='personal']")
  end

  it "marks the current page in the sidebar with aria-current" do
    visit edit_account_profile_path
    within("aside[aria-label='Settings navigation']") do
      expect(page).to have_css("a[aria-current='page']", text: "Profile")
    end
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_account_profile_path

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
```

- [ ] **Step 3: Run the spec**

Run: `bundle exec rspec spec/system/settings/personal_context_spec.rb`
Expected: all four examples PASS. If axe fails, fix the violation — do not lower the threshold. Project policy: WCAG 2.2 AAA, no exceptions (see memory `feedback_ci_vs_local_axe.md`).

- [ ] **Step 4: Commit**

```bash
git add spec/system/settings/personal_context_spec.rb
git commit -m "test(system): settings hub personal context happy path

Asserts sidebar item visibility, data-settings-context-kind, current-
page marking, and axe-core WCAG 2.2 AAA cleanliness in both themes."
```

---

## Task 14: System spec — org context + Pundit gating

**Files:**

- Create: `spec/system/settings/org_context_spec.rb`

- [ ] **Step 1: Write the spec**

Create `spec/system/settings/org_context_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Settings hub — org context", type: :system do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:membership, user: owner, workspace: workspace, role: create(:role, slug: "owner", workspace: workspace))
    create(:membership, user: viewer, workspace: workspace, role: create(:role, slug: "viewer", workspace: workspace))
  end

  context "as Owner" do
    before { sign_in_via_form(owner) }

    it "renders org-context sidebar with all admin items" do
      visit edit_workspace_path(workspace)

      within("aside[aria-label='Settings navigation']") do
        expect(page).to have_link("Profile")
        expect(page).to have_link("Members")
        expect(page).to have_link("Invitations")
        expect(page).to have_link("Limits & Plan")

        expect(page).not_to have_link("Notifications") # personal-only
        expect(page).not_to have_link("Security")
        expect(page).not_to have_link("Appearance")
      end
    end

    it "exposes the org context via data attribute" do
      visit edit_workspace_path(workspace)
      expect(page).to have_css("[data-settings-context-kind='org']")
    end

    it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
      visit edit_workspace_path(workspace)
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  context "as Viewer" do
    before { sign_in_via_form(viewer) }

    it "hides admin items (Members, Invitations, Limits) but shows read-only Profile" do
      visit workspace_path(workspace)

      within("aside[aria-label='Settings navigation']") do
        # Profile may be hidden too if WorkspacePolicy#update? is false for Viewer.
        # Per spec: "A Viewer in Acme sees Profile (read-only) but does not see Members management".
        # If the policy gates the link only on :show? for read-only access, add a :show? variant
        # to nav_item_if_permitted call in the partial. For now, assert the admin items are absent:
        expect(page).not_to have_link("Members")
        expect(page).not_to have_link("Invitations")
        expect(page).not_to have_link("Limits & Plan")
      end
    end
  end
end
```

> **Note:** Step 1 caveat — the Profile gating granularity for Viewers may need refinement. The current `_settings_sidebar.html.erb` (Task 7) gates Profile on `:update?` which means Viewers won't see Profile at all. The spec says "Viewer sees Profile (read-only)". Resolve by introducing a `:show?` fallback or splitting the gate: gate visibility on `:show?`, but the destination page renders read-only based on `:update?`. If the team wants the spec-true behavior, add a follow-up subtask here to relax the gate; otherwise document the divergence in CHANGELOG and accept that Phase 2 Viewer experience is "no Profile link" (Phase 3 destination redesign can restore read-only Profile).

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/system/settings/org_context_spec.rb`
Expected: all examples PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/settings/org_context_spec.rb
git commit -m "test(system): settings hub org context + Pundit gating

Owner sees all org-tier items; Viewer sees the admin items hidden.
axe-core AAA in both themes for the Owner path."
```

---

## Task 15: System spec — demotion while viewing

**Files:**

- Create: `spec/system/settings/demotion_while_viewing_spec.rb`

- [ ] **Step 1: Write the spec**

Create `spec/system/settings/demotion_while_viewing_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Settings hub — demotion while viewing", type: :system do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }

  before do
    create(:membership, user: owner, workspace: workspace, role: create(:role, slug: "owner", workspace: workspace))
    @member_role = create(:role, slug: "admin", workspace: workspace)
    @member_ms = create(:membership, user: member, workspace: workspace, role: @member_role)
    @viewer_role = create(:role, slug: "viewer", workspace: workspace)
  end

  it "re-renders the sidebar via Turbo morph when the user's role is changed in another tab" do
    sign_in_via_form(member)
    visit workspace_members_path(workspace)

    # In a real session, an admin in another tab demotes this user. Simulate the broadcast:
    @member_ms.update!(role: @viewer_role)

    # The morph should have removed the Members link from this user's sidebar.
    using_wait_time(5) do
      within("aside[aria-label='Settings navigation']") do
        expect(page).not_to have_link("Members")
      end
    end
  end
end
```

> **Why this test is fragile:** broadcasts in system specs can be flaky. If the test is unreliable, mark with `it "...", :flaky` and triage in a follow-up (memory: `project_flaky_tests_followup.md`). Do not skip the assertion entirely — the behavior is load-bearing for Phase 2.

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/system/settings/demotion_while_viewing_spec.rb`
Expected: PASS. If it fails because the broadcast doesn't arrive in time, investigate (don't extend the wait blindly — see `feedback_check_dev_log_first.md`).

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add spec/system/settings/demotion_while_viewing_spec.rb
git commit -m "test(system): settings hub demotion-while-viewing redirect

When a user's role is changed mid-session, the Membership broadcast
triggers a Turbo morph that updates the sidebar in the open tab —
the demoted admin sees Members removed from their sidebar
immediately, no half-rendered Turbo Frame state."
```

---

## Task 16: CHANGELOG + open Phase 3 issues

**Files:**

- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add entry to `[Unreleased]`**

Per memory `feedback_lean_changelog.md` — one-line action statements, not narratives.

Edit `CHANGELOG.md` and add under `## [Unreleased]` → `### Added`:

```markdown
- Settings hub shell: sidebar-equipped layout (`layouts/settings.html.erb`) for account- and workspace-tier settings, with context-adaptive item list, Pundit-gated visibility, polite aria-live region, and site-wide Turbo morph.
```

- [ ] **Step 2: Open follow-up issues for Phase 3 / deferred items**

Per memory `feedback_check_issues_before_filing.md`, search first:

```bash
gh issue list --search "settings hub" --state all
```

Then file (only the ones that don't already exist):

- "Phase 3: redesign Settings hub destination pages with H1 / aria-label disambiguation"
- "Phase 4: OKLCH personal-context token ramp + switcher visual differentiation"
- "Viewer-read-only Profile gating: relax sidebar gate or add :show? fallback"
- "Hide personal workspace from header workspace switcher dropdown"
- "Extract shared `<head>` partial between application.html.erb and settings.html.erb to remove duplication"

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note Phase 2 settings hub shell"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Settings hub layout (`settings.html.erb`) | 8 |
| Workspace switcher (sidebar variant) | 6 |
| Context-adaptive sidebar | 7 |
| Pundit-gated items via single source of truth | 3 (helper), 7 (partial) |
| aria-live region | 8 (region), 11 (announcer controller) |
| Turbo morph site-wide | 11 |
| Personal workspace context on `/account/*` | 1 (model), 2 (concern), 9 (controllers) |
| Membership broadcast on role change | 12 |
| WCAG 2.2 AAA verified | 13, 14 (axe in both themes) |
| Demotion-while-viewing | 15 |
| Polymorphic Profile aria-label | 7 (`aria_labels.profile_personal`/`profile_org` i18n keys) |
| Avatar-shape differentiation (1.4.1) | 6 (`rounded-full` vs `rounded-md`) |
| 44×44 touch targets | 5 (`min-h-[44px]`) |

Out-of-scope items documented in plan header.

**Placeholder scan:** Each task contains complete code blocks, exact commands, and named files. The "Viewer-Profile gating" decision in Task 14 is flagged with concrete resolution paths rather than left as TBD.

**Type/identifier consistency:** `settings_context_kind` (helper) → `data-settings-context-kind` (DOM attribute) → `settings.sidebar.aria_live_template.<kind>` (i18n key) all use the same `:personal`/`:org` taxonomy. `current_workspace` is the consistent local across `_settings_sidebar.html.erb` and `_settings_sidebar_switcher.html.erb`. `nav_item_if_permitted(record, action:)` signature matches across helper definition (Task 3) and call sites (Task 7).

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-19-settings-hub-phase-2-shell.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Good fit for this plan because tasks 1–7 are independent and could parallelize partially, and the layout-application tasks (9, 10) benefit from a fresh subagent reading the application layout cleanly.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Good if you want me to keep state across tasks (e.g. learn each controller's quirks once and apply patterns to the next).

**Which approach?**
