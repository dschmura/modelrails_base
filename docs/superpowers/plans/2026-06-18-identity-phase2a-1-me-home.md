# Identity Phase 2a-1 — the thin `/me` home (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a thin, template-owned `/me` identity home — the signed-in user's launchpad (identity card + their workspaces + a link into settings). Purely **additive** (new route + `MeController` + view + specs); changes no existing behavior. Gives `:none` forks a template-native `me_path` to point `authenticated_home_path` at. Spec: `docs/superpowers/specs/2026-06-18-identity-phase2a-me-home-and-settings-design.md`.

**Architecture:** One singular RESTful route (`resource :me, only: [:show]`), one controller (self-scoped, no Pundit policy — the repo's opt-in posture), one view built from existing design-system patterns (`avatar_for`, `workspace_path`, `UI::*`/semantic tokens), one locale file. The `:personal` default landing is unchanged — `/me` is a *reachable* surface, not the new default. Links to settings target today's `edit_account_profile_path` (Phase 2a-2 sweeps it to `/settings`).

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (`mise exec --`), RSpec (request + system), Capybara/Playwright + axe (AAA proven in **CI only**; local axe is AA), modelrails_ui design system (AAA, semantic tokens — see `.modelrails_ui/agent-rules.md`). TDD; full suite green before every commit; commit but **DO NOT push**; never bypass Lefthook.

---

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `config/routes.rb` | Modify (~L20, before `namespace :account`) | `resource :me, only: [:show]` → `me_path`. |
| `app/controllers/me_controller.rb` | **Create** | `#show` loads the user's memberships (preloaded); self-scoped, no `authorize`. |
| `app/views/me/show.html.erb` | **Create** | Identity card (`avatar_for` + name + "Edit in Settings") + "Your workspaces" list + thin/zero-safe. |
| `config/locales/en/me.en.yml` | **Create** | `me.show.*` strings. |
| `spec/requests/me_spec.rb` | **Create** | Unauth → redirect; signed-in → 200; zero-workspace → 200. |
| `spec/system/me_spec.rb` | **Create** | Renders identity + workspaces + settings link; axe (AAA in CI). |

---

## Task 1 — the `/me` seam (route + controller + request spec)

**Files:** Create `app/controllers/me_controller.rb`, `spec/requests/me_spec.rb`; Modify `config/routes.rb`. (A minimal view stub so the 200 renders — the real view is Task 2.)

- [ ] **Step 1: Write the request spec (RED).** `spec/requests/me_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Me (identity home)", type: :request do
  it "redirects unauthenticated visitors to sign in" do
    get me_path
    expect(response).to redirect_to(new_session_path)
  end

  context "authenticated" do
    let(:user) { create(:user) }            # :personal default → has one workspace
    before { sign_in(user) }

    it "renders the identity home" do
      get me_path
      expect(response).to have_http_status(:ok)
    end

    it "renders for a workspaceless user (:none safety)" do
      get me_path                            # warm
      sign_in(create(:user, :with_zero_workspaces))
      get me_path
      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: Run it — verify it fails.** `mise exec -- bundle exec rspec spec/requests/me_spec.rb` → **FAIL** (`undefined ... me_path` / no route).

- [ ] **Step 3: Add the route.** `config/routes.rb`, just before the `namespace :account do` block (~L21):

```ruby
  resource :me, only: [ :show ]
```

- [ ] **Step 4: Create the controller.** `app/controllers/me_controller.rb`:

```ruby
class MeController < ApplicationController
  # Identity home — the signed-in user's own launchpad. Self-scoped (you only
  # ever see your own /me), so there is no Pundit authorize call: the page reads
  # Current.user and the workspaces they belong to. Per the project's Pundit
  # opt-in posture, a self-scoped resource needs no policy.
  def show
    @memberships = Current.user.memberships.kept.includes(:workspace, :role)
  end
end
```

- [ ] **Step 5: Add a minimal view stub** so the action renders 200 (real content in Task 2). `app/views/me/show.html.erb`:

```erb
<h1><%= Current.user.name %></h1>
```

- [ ] **Step 6: Run the request spec — verify GREEN.** `mise exec -- bundle exec rspec spec/requests/me_spec.rb` → **PASS** (3 examples). If `Current.user.name` errors, use `"#{Current.user.first_name} #{Current.user.last_name}"` (verify whether `User#name` exists).

- [ ] **Step 7: Full suite, then commit.**

```bash
mise exec -- bundle exec rspec
git add config/routes.rb app/controllers/me_controller.rb app/views/me/show.html.erb spec/requests/me_spec.rb
git commit -m "feat(me): thin /me identity-home seam (route + controller + request specs)"
```

---

## Task 2 — the `/me` view + i18n + a11y

**Files:** Modify `app/views/me/show.html.erb`; Create `config/locales/en/me.en.yml`, `spec/system/me_spec.rb`.

- [ ] **Step 1: Add the locale strings.** `config/locales/en/me.en.yml`:

```yaml
en:
  me:
    show:
      edit_in_settings: "Edit in settings"
      workspaces_title: "Your workspaces"
      no_workspaces: "You're not in any workspaces yet."
```

- [ ] **Step 2: Build the view.** Replace `app/views/me/show.html.erb`. Match the design system — semantic tokens only, AAA, 44px targets, `focus-ring` (never `focus:ring`). Use `avatar_for` and the card pattern from `shared/_preferences_card.html.erb`. Verify the button class against `.modelrails_ui/agent-rules.md` / existing usage (e.g. `.btn-outline` vs the `ui :button` primitive):

```erb
<div class="mx-auto max-w-2xl px-4 py-8 space-y-6">
  <section aria-labelledby="me-identity-title"
           class="rounded-2xl bg-surface-raised border border-border shadow-sm p-6 flex items-center gap-4">
    <%= avatar_for(Current.user, size: :lg) %>
    <div class="flex-1 min-w-0">
      <h1 id="me-identity-title" class="text-xl font-semibold text-text-heading truncate">
        <%= Current.user.name %>
      </h1>
      <p class="text-sm text-text-body truncate"><%= Current.user.email_address %></p>
    </div>
    <%= link_to t("me.show.edit_in_settings"), edit_account_profile_path, class: "btn-outline shrink-0" %>
  </section>

  <section aria-labelledby="me-workspaces-title"
           class="rounded-2xl bg-surface-raised border border-border shadow-sm overflow-hidden">
    <header class="px-6 py-5 border-b border-border">
      <h2 id="me-workspaces-title" class="text-lg font-semibold text-text-heading">
        <%= t("me.show.workspaces_title") %>
      </h2>
    </header>
    <% if @memberships.any? %>
      <ul class="divide-y divide-border">
        <% @memberships.each do |membership| %>
          <li>
            <%= link_to workspace_path(membership.workspace),
                  class: "min-h-[44px] flex items-center gap-3 px-6 py-3 hover:bg-surface-sunken focus-ring" do %>
              <span class="flex-1 min-w-0">
                <span class="block truncate text-text-heading font-medium"><%= membership.workspace.name %></span>
                <span class="block text-xs text-text-muted"><%= membership.role.name %></span>
              </span>
            <% end %>
          </li>
        <% end %>
      </ul>
    <% else %>
      <p class="px-6 py-4 text-sm text-text-body"><%= t("me.show.no_workspaces") %></p>
    <% end %>
  </section>
</div>
```

- [ ] **Step 3: Write the system spec.** `spec/system/me_spec.rb` (define `sign_in_via_form` inline per the repo convention; assert content; run axe in both themes — AAA proven in CI, AA locally):

```ruby
require "rails_helper"

RSpec.describe "Me (identity home)", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  it "shows identity, the user's workspaces, and a settings link" do
    sign_in_via_form(user)
    visit me_path

    expect(page).to have_css("h1", text: user.name)
    expect(page).to have_link(I18n.t("me.show.edit_in_settings"), href: edit_account_profile_path)
    expect(page).to have_css("#me-workspaces-title")
    expect(page).to have_link(user.workspaces.first.name)   # :personal default → one workspace

    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end
end
```

- [ ] **Step 4: Run the new specs.** `mise exec -- bundle exec rspec spec/requests/me_spec.rb spec/system/me_spec.rb` → green (local axe = AA; CI proves AAA).

- [ ] **Step 5: Full suite, then commit.**

```bash
mise exec -- bundle exec rspec
git add app/views/me/show.html.erb config/locales/en/me.en.yml spec/system/me_spec.rb
git commit -m "feat(me): identity-home view — identity card + your-workspaces list (AAA, design-system)"
```

---

## Self-review (run before handoff)

- **Additive only** — no existing route/controller/view touched; `authenticated_home_path` unchanged (the `:personal` default landing is untouched; `:none` forks may now point at the template's `me_path`).
- **No placeholders** — exact route/controller/spec code; the view is a complete skeleton (implementer verifies the button class + `User#name` against the codebase).
- **Conventions encoded** — `sign_in` (request) vs inline `sign_in_via_form` (system); `:with_zero_workspaces` for the `:none` safety case; self-scoped controller = no Pundit policy (commented); AAA is CI-only.
- **Settings link** targets today's `edit_account_profile_path` — Phase 2a-2's namespace rename sweeps it.

## Execution handoff

1. **Subagent-Driven (recommended)** — fresh subagent per task, spec + code-quality review between.
2. **Inline** — `superpowers:executing-plans`.

> **Sequencing note:** execute after PR #350 merges (this branches off the renamed-var main). 2a-2 (the `/account → /settings` move) is a separate plan.
