# Identity Phase 2b — header workspace context switcher (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Add a header **workspace context switcher** — its own dropdown control (separate from the avatar/user menu) listing the user's workspaces, each a link to `/workspaces/:slug`. Person-vs-org chips (shape, not color), highlights the current workspace, and **collapses entirely when the user has only one workspace**. **Additive** — a new partial rendered into the header; no existing behavior changes. Spec: `docs/superpowers/specs/2026-06-18-identity-account-model-clarity-design.md` (the switcher). Execute after #352 (the rename) merges.

**Architecture:** A new `shared/_workspace_switcher` partial, rendered in `_header.html.erb` between the theme toggle and the user menu (desktop-only, like the theme toggle). It **reuses the existing `dropdown` Stimulus controller** (toggle, outside-click, Escape, arrow keys, focus-on-open, focus-return-on-close, `aria-expanded`) — no new JS. It **harvests the chip rendering** from `_settings_sidebar_switcher` (`workspace.personal? ? "rounded-full" : "rounded-md"` + `workspace_icon_for`). The "current" workspace is read from `Current.workspace` (on workspace pages) or `session[:current_workspace_id]` (elsewhere, e.g. `/me`). Switching = a plain Turbo visit to `/workspaces/:slug`; Turbo's page-title update announces the context change to screen readers.

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (`mise exec --`), Hotwire (reuse `dropdown` controller), modelrails_ui (semantic tokens, AAA, `focus-ring`). TDD; full suite green before every commit; commit but **DO NOT push**; never bypass Lefthook.

## Scope notes (refinement from research — flag to maintainer)

- **Deferred to 2c, not 2b** (originally slated for 2b): the explicit "Switched to X" `aria-live` **announcer** and Turbo **morph**. Reason: the header switcher *navigates* (full Turbo visit), so the page-`<title>` change already announces context; morph lives only on the settings layout and adding it globally isn't additive. These pair with 2c's banner + OKLCH ramp.
- **Out of scope:** the OKLCH "your workspace" token ramp, the "You're in [X]" banner, dropping `PersonalWorkspaceContext`, removing `_settings_sidebar_switcher` — all 2c.

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `app/helpers/workspace_helper.rb` | Modify | `switcher_workspaces` (preloaded list) + `switcher_current_workspace` (Current.workspace ‖ session) helpers. |
| `app/views/shared/_workspace_switcher.html.erb` | **Create** | The dropdown — reuses `dropdown` controller, chips, links, collapse-when-one. |
| `app/views/shared/_header.html.erb` | Modify (~L27) | Render the switcher before the user menu (desktop). |
| `config/locales/en/workspaces.en.yml` | Modify | `workspaces.switcher.*` labels/aria. |
| `spec/requests/workspace_switcher_spec.rb` | **Create** | Renders when ≥2 workspaces; absent when 1; current highlighted. |
| `spec/system/workspace_switcher_spec.rb` | **Create** | Open dropdown → list → click navigates; a11y/axe. |

---

## Task 1 — the switcher (helper + partial + header + request spec)

- [ ] **Step 1: Helpers.** In `app/helpers/workspace_helper.rb` add:

```ruby
# Workspaces shown in the header context switcher, preloaded for the chip
# (logo + role), N+1-safe.
def switcher_workspaces
  Current.user.workspaces.kept.includes(:logo_attachment, memberships: :role)
end

# The workspace the switcher trigger reflects: the active one on a workspace
# page, else the last-visited one remembered in the session (e.g. on /me).
def switcher_current_workspace
  Current.workspace || Current.user.workspaces.kept.find_by(id: session[:current_workspace_id])
end
```

- [ ] **Step 2: Request spec (RED).** `spec/requests/workspace_switcher_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Workspace switcher (header)", type: :request do
  let(:user) { create(:user) }                                  # :personal → 1 workspace
  before { sign_in(user) }

  it "is absent when the user has only one workspace" do
    get me_path
    expect(response.body).not_to include("workspace-switcher-button")
  end

  it "renders the switcher when the user has 2+ workspaces" do
    second = create(:workspace)
    create(:membership, :owner, user: user, workspace: second)
    get me_path
    expect(response.body).to include("workspace-switcher-button")
    expect(response.body).to include(CGI.escapeHTML(second.name))
  end
end
```

- [ ] **Step 3: Run it → FAIL** (`mise exec -- bundle exec rspec spec/requests/workspace_switcher_spec.rb`) — no switcher rendered.

- [ ] **Step 4: Build the partial.** `app/views/shared/_workspace_switcher.html.erb` — mirror the `_user_menu.html.erb` dropdown markup (reuse `data-controller="dropdown"`, `dropdown-target` button/menu, `role="menu"`, `role="menuitem"` items, `focus-ring`), and the chip from `_settings_sidebar_switcher.html.erb`. Collapse when ≤1. Match semantic tokens / AAA / 44px:

```erb
<% workspaces = switcher_workspaces %>
<% if workspaces.size > 1 %>
  <% current = switcher_current_workspace %>
  <div data-controller="dropdown" class="relative hidden md:block">
    <button data-dropdown-target="button" data-action="click->dropdown#toggle"
            id="workspace-switcher-button" type="button"
            aria-haspopup="true" aria-expanded="false" aria-controls="workspace-switcher-menu"
            class="min-h-[44px] flex items-center gap-2 px-3 rounded-lg text-text-body hover:bg-surface-sunken focus-ring">
      <span class="shrink-0 w-8 h-8 flex items-center justify-center <%= current&.personal? ? "rounded-full" : "rounded-md overflow-hidden" %>">
        <%= workspace_icon_for(current, size: :sm) if current %>
      </span>
      <span class="hidden lg:block max-w-[12ch] truncate font-medium">
        <%= current&.name || t("workspaces.switcher.label") %>
      </span>
      <span aria-hidden="true">▾</span>
    </button>

    <div data-dropdown-target="menu" id="workspace-switcher-menu" role="menu"
         aria-labelledby="workspace-switcher-button"
         class="hidden absolute right-0 mt-2 w-64 rounded-lg bg-surface-raised border border-border shadow-lg z-50 py-1">
      <% workspaces.each do |workspace| %>
        <% is_current = current && workspace.id == current.id %>
        <% membership = workspace.memberships.detect { |m| m.user_id == Current.user.id } %>
        <%= link_to workspace_path(workspace), role: "menuitem", tabindex: "-1",
              aria: { current: ("true" if is_current) },
              class: ["min-h-[44px] flex items-center gap-3 py-2 text-sm",
                      (is_current ? "pl-2 pr-3 border-l-4 border-interactive bg-surface-sunken font-semibold text-text-heading"
                                  : "px-3 text-text-body hover:bg-surface-sunken")].compact do %>
          <span class="shrink-0 w-8 h-8 flex items-center justify-center <%= workspace.personal? ? "rounded-full" : "rounded-md overflow-hidden" %>">
            <%= workspace_icon_for(workspace, size: :sm) %>
          </span>
          <span class="flex-1 min-w-0">
            <span class="block truncate"><%= workspace.name %></span>
            <span class="block text-xs text-text-muted"><%= membership&.role&.name %></span>
          </span>
        <% end %>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 5: Locale.** Add to `config/locales/en/workspaces.en.yml`:

```yaml
en:
  workspaces:
    switcher:
      label: "Workspaces"
```

- [ ] **Step 6: Render in the header.** `app/views/shared/_header.html.erb`, in the authenticated flex cluster, just before the `render "shared/user_menu"` line: `<%= render "shared/workspace_switcher" %>` (guard with `<% if authenticated? %>` if that block isn't already auth-gated).

- [ ] **Step 7: Run the request spec → PASS.** Then FULL suite green; commit:

```bash
mise exec -- bundle exec rspec
git add app/helpers/workspace_helper.rb app/views/shared/_workspace_switcher.html.erb app/views/shared/_header.html.erb config/locales/en/workspaces.en.yml spec/requests/workspace_switcher_spec.rb
git commit -m "feat(switcher): header workspace context switcher (additive; reuses dropdown controller)"
```

---

## Task 2 — system spec (interaction + a11y)

- [ ] **Step 1:** `spec/system/workspace_switcher_spec.rb` — a user with 2 workspaces: open the dropdown, see both, the current highlighted; click the other → navigates to its `/workspaces/:slug`. Axe in both themes (AAA proven in CI; local AA). Define `sign_in_via_form` inline (repo convention). Verify the dropdown a11y is inherited from the `dropdown` controller (aria-expanded toggles, Escape closes, focus returns to the trigger).

- [ ] **Step 2:** Run the new spec, then FULL suite green; commit:

```bash
git add spec/system/workspace_switcher_spec.rb
git commit -m "test(switcher): system spec — open, navigate, a11y"
```

---

## Self-review

- **Additive** — new partial + helper + 2 specs; `_header.html.erb` gains one render line; nothing existing changes.
- **No new JS** — reuses the `dropdown` controller (a11y comes for free).
- **Collapse-when-one** verified by the request spec (absent at 1 workspace, present at 2).
- **Posture-agnostic** — lists whatever workspaces the user is a member of (personal + orgs under `:personal`; orgs-only under `:none`).
- **Deferred correctly** — morph, the explicit announcer, the banner, OKLCH, and the `PersonalWorkspaceContext` drop are all 2c.

## Execution handoff

1. **Subagent-Driven (recommended)** — implementer per task + review.
2. **Inline** — `superpowers:executing-plans`.
