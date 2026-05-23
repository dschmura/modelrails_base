# Settings Hub Phase 3: Destinations + Disambiguation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [docs/superpowers/specs/2026-05-19-settings-hub-design.md](../specs/2026-05-19-settings-hub-design.md) — Phase 3 row + the "Disambiguation rules" table.

**Goal:** Deliver disambiguated H1s and aria-labels for every sidebar destination, extract a shared `shared/_settings_page_header.html.erb` partial that each destination opts into, and build the Appearance destination (closes #150 — the sidebar link currently 405s).

**Architecture:** Phase 3 is a redesign-within-shell pass — no new layouts, no sidebar structural changes. The hub frame is fixed from Phase 2; this phase makes each destination's first screen of content honor the spec's polymorphic-Profile disambiguation. A new shared partial centralizes the page-header pattern (H1 + optional description + ARIA hooks) so contributors don't reinvent the chrome per page. Appearance goes from "405 stub" to "working settings page."

**Tech Stack:** Rails 8.1, ERB partials with strict locals, TailwindCSS 4 with semantic tokens, RSpec system specs with Capybara + Playwright + axe-core (WCAG 2.2 AAA).

**Out of scope (deferred to separate PRs):**

- Route consolidation — splitting `workspaces#edit` (Profile) from `workspaces/settings#edit` (Limits & Plan). The Phase 1 spec row promised this as "future PR"; Phase 3 inherits the divergence. Today and during Phase 3, both sidebar items in org context route to the same destination page. Tracked separately.
- Full "shared page skeleton grid" for the two Profile pages (avatar/logo slot top-left, identity fields center, color/theme slot below). Phase 3 ships the *header* partial; the body layout grid is Phase 4 (visual polish) work.
- Mobile sidebar drawer (#148) — still deferred.
- Phase 4 OKLCH personal-context token ramp + switcher chroma boost.
- Viewer read-only Profile (closed wontfix as #144 per Fried-style rationale — strict Owner+Admin gating stands).

**Branch:** `docs/settings-hub-spec` (Phase 2 lives here; Phase 3 builds on top).

**Pre-Phase-3 baseline:** 1905 examples, 0 failures, 1 pending. Coverage 95.85% line.

---

## File Map

**Create:**

- `app/views/shared/_settings_page_header.html.erb` — shared header partial (H1, optional description, optional ARIA `id` for skip-link/aria-labelledby)
- `app/views/account/theme_preferences/edit.html.erb` — Appearance destination page
- `spec/system/account/profile_destination_spec.rb` — dedicated Profile (personal) destination spec with axe AAA
- `spec/system/account/connected_accounts_destination_spec.rb` — dedicated Security destination spec with axe AAA
- `spec/system/account/appearance_destination_spec.rb` — Appearance destination spec with axe AAA

**Modify:**

- `config/routes.rb` — add `:edit` to `resource :theme_preference`
- `app/controllers/account/theme_preferences_controller.rb` — add `edit` action
- `config/locales/en/settings.en.yml` — new keys for disambiguated H1s + Appearance content
- `config/locales/en/account.en.yml` (if it exists; else `config/locales/en/profiles.en.yml`) — update Account Profile H1 i18n
- `app/views/account/profiles/edit.html.erb` — adopt header + disambiguated H1
- `app/views/account/notification_preferences/edit.html.erb` — adopt header
- `app/views/account/connected_accounts/index.html.erb` — adopt header
- `app/views/workspaces/settings/edit.html.erb` — adopt header + workspace-name H1
- `app/views/workspaces/members/index.html.erb` — adopt header
- `CHANGELOG.md` — note Phase 3 changes

---

## Task 1: Shared settings page header partial

**Files:**

- Create: `app/views/shared/_settings_page_header.html.erb`

**Steps:**

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_settings_page_header.html.erb`:

```erb
<%# locals: (title:, description: nil) -%>
<header class="mb-8">
  <h1 class="text-2xl font-semibold text-text-heading"><%= title %></h1>
  <% if description.present? %>
    <p class="mt-2 text-sm text-text-body max-w-2xl"><%= description %></p>
  <% end %>
</header>
```

> **Why strict locals:** caller must pass `title:`; `description:` is optional. Rails 8 strict locals raise at render time if `title:` is missing — better than silently rendering an empty heading.

> **Why `text-2xl font-semibold`:** consistent visual hierarchy across all settings destinations. Tailwind defaults; no custom tokens.

> **Why `text-text-heading` and `text-text-body`:** project semantic tokens with dark-mode cascade (verified in Phase 2). Memory `feedback_phantom_css_classes.md`.

- [ ] **Step 2: Smoke test the partial renders**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rails runner 'puts ActionController::Base.render(partial: "shared/settings_page_header", locals: { title: "Profile" })'`

Expected: HTML containing `<h1`...`Profile</h1>` with the right Tailwind classes. No description paragraph.

Then with description: `'... locals: { title: "Profile", description: "Your account identity." })'` — should include the `<p>` block.

- [ ] **Step 3: Run full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1905 examples, 0 failures, 1 pending (no test changes; just a new partial).

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_settings_page_header.html.erb
git commit -m "feat(views): add shared settings page header partial

Single H1 + optional description block, project semantic tokens,
strict locals. Each settings destination opts in for consistent
chrome and a single place to evolve the page-header pattern."
```

---

## Task 2: I18n keys for disambiguated H1s

**Files:**

- Modify: `config/locales/en/settings.en.yml`

**Steps:**

- [ ] **Step 1: Add the keys**

Append to `config/locales/en/settings.en.yml`, nested under `en.settings`:

```yaml
pages:
  profile_personal:
    h1: "Your personal profile"
    description: "Visible in every workspace. Only you can edit this."
  notifications:
    h1: "Notifications"
    description: "Choose how and when you hear from this app."
  security:
    h1: "Security"
    description: "Manage your sign-in methods and connected accounts."
  appearance:
    h1: "Appearance"
    description: "Theme and visual preferences for this device."
  workspace_settings:
    h1_html: "<span class='text-text-muted font-normal'>%{name}</span> settings"
    description: "Workspace identity, capacity, and plan."
  workspace_members:
    h1_html: "<span class='text-text-muted font-normal'>%{name}</span> members"
    description: "Invite teammates, manage roles, deactivate access."
```

> **Why `h1_html` for workspace pages:** the workspace name should render in a muted weight, distinct from the rest of the H1, per the spec's disambiguation goal. Rails' `<%= t("...html") %>` auto-marks as HTML-safe.

> **Why "Visible in every workspace" subhead on personal Profile:** the spec calls this out — *"Your personal profile — visible in every workspace"* — so screen readers + sighted users understand the scope on page-load.

> **Workspace Settings H1 caveat:** the page currently serves BOTH Profile and Limits & Plan (route consolidation deferred). The H1 reads "<workspace name> settings" rather than "<workspace name>'s profile" to honestly describe the combined content. When route consolidation lands, this H1 splits into two.

- [ ] **Step 2: Smoke check the keys load**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rails runner "puts I18n.t('settings.pages.profile_personal.h1'); puts I18n.t('settings.pages.workspace_settings.h1_html', name: 'Acme'); puts I18n.t('settings.pages.appearance.description')"`

Expected output:
```
Your personal profile
<span class='text-text-muted font-normal'>Acme</span> settings
Theme and visual preferences for this device.
```

If any key raises, fix the YAML before continuing.

- [ ] **Step 3: Run full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1905 examples, 0 failures, 1 pending.

- [ ] **Step 4: Commit**

```bash
git add config/locales/en/settings.en.yml
git commit -m "feat(i18n): add disambiguated H1 keys for settings destinations

Per-page title + description keys under settings.pages.*. Personal
Profile gets the spec's explicit 'Your personal profile' wording;
workspace pages use h1_html with the workspace name in a muted
weight to honor the polymorphic-label disambiguation goal."
```

---

## Task 3: Account Profile destination — header + disambiguated H1

**Files:**

- Modify: `app/views/account/profiles/edit.html.erb`
- Create: `spec/system/account/profile_destination_spec.rb`

**Step 1: Inspect current Account Profile view**

Run: `head -20 app/views/account/profiles/edit.html.erb` to see the current opening (it currently has an `<h1>` with the existing `account.profiles.edit.title` key). Note that line so you know what to replace.

**Step 2: Write the failing spec FIRST (TDD)**

Create `spec/system/account/profile_destination_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Account Profile destination", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { sign_in_via_form(user) }

  it "renders the disambiguated personal Profile H1" do
    visit edit_account_profile_path
    expect(page).to have_css("h1", text: I18n.t("settings.pages.profile_personal.h1"))
  end

  it "renders the personal-Profile description" do
    visit edit_account_profile_path
    expect(page).to have_text(I18n.t("settings.pages.profile_personal.description"))
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_account_profile_path
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
```

**Step 3: Run the spec — expect FAIL on H1 + description (existing H1 is generic)**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/account/profile_destination_spec.rb`

Expected: First two examples FAIL (no H1 matching "Your personal profile" yet). Third (axe) likely PASSES — Phase 2 already verified axe AAA on this page via `personal_context_spec.rb`.

**Step 4: Update the view**

Edit `app/views/account/profiles/edit.html.erb`. Find the current `<h1>...</h1>` (or `<%= t("account.profiles.edit.title") %>` block) and replace with:

```erb
<%= render "shared/settings_page_header",
      title: t("settings.pages.profile_personal.h1"),
      description: t("settings.pages.profile_personal.description") %>
```

Remove any standalone H1 the view was rendering before. Preserve everything else (avatar picker, form fields, save button).

**Step 5: Re-run spec — expect PASS**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/account/profile_destination_spec.rb`

Expected: all 3 examples PASS.

**Step 6: Run full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1908 examples (1905 + 3 new), 0 failures, 1 pending. Any failures elsewhere likely indicate another spec was depending on the OLD H1 text — investigate before patching the spec.

**Step 7: Commit**

```bash
git add app/views/account/profiles/edit.html.erb spec/system/account/profile_destination_spec.rb
git commit -m "feat(views): disambiguated H1 for Account Profile destination

Adopts shared/_settings_page_header with the spec's 'Your personal
profile' title + 'Visible in every workspace' description so screen
readers and sighted users hear/see the scope on page-load. Dedicated
system spec asserts the H1 + description text and runs axe AAA in
both themes."
```

---

## Task 4: Account Notification Preferences destination — header

**Files:**

- Modify: `app/views/account/notification_preferences/edit.html.erb`

**Steps:**

- [ ] **Step 1: Inspect the current view**

Read `app/views/account/notification_preferences/edit.html.erb` and find its current `<h1>` (or i18n-keyed heading).

- [ ] **Step 2: Update the view**

Replace the existing heading block with:

```erb
<%= render "shared/settings_page_header",
      title: t("settings.pages.notifications.h1"),
      description: t("settings.pages.notifications.description") %>
```

Keep all existing functionality (banner, timezone drawer, preferences table) intact.

- [ ] **Step 3: Check existing system specs**

Run: `grep -l 'edit_account_notification_preferences_path\|notifications_preferences' spec/system/`

Expected: existing specs like `notification_preferences_aaa_spec.rb` and `notification_preferences_mobile_spec.rb`. Check if any assert the old H1 text — if so, update those assertions to the new i18n key.

- [ ] **Step 4: Run full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1908 examples, 0 failures, 1 pending.

If failures appear in `notification_preferences_*_spec.rb`, the assertions are likely pinned to the old H1 text — update them to use `t("settings.pages.notifications.h1")` and re-run.

- [ ] **Step 5: Commit**

```bash
git add app/views/account/notification_preferences/edit.html.erb spec/
git commit -m "feat(views): adopt settings page header on Notifications destination

Replaces the page's bespoke H1 with shared/_settings_page_header for
consistency with other settings destinations. Existing AAA system
specs continue to pass; H1 assertions updated to the new i18n key
where they pinned the previous text."
```

---

## Task 5: Account Security (Connected Accounts) destination — header + spec

**Files:**

- Modify: `app/views/account/connected_accounts/index.html.erb`
- Create: `spec/system/account/connected_accounts_destination_spec.rb`

**Steps:**

- [ ] **Step 1: Write the failing spec FIRST (TDD)**

Create `spec/system/account/connected_accounts_destination_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Account Security destination", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { sign_in_via_form(user) }

  it "renders the Security H1 (sidebar label parity)" do
    visit account_connected_accounts_path
    expect(page).to have_css("h1", text: I18n.t("settings.pages.security.h1"))
  end

  it "renders the Security description" do
    visit account_connected_accounts_path
    expect(page).to have_text(I18n.t("settings.pages.security.description"))
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit account_connected_accounts_path
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
```

- [ ] **Step 2: Run the spec — expect FAIL on H1 + description**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/account/connected_accounts_destination_spec.rb`
Expected: First two examples FAIL. Axe likely passes.

- [ ] **Step 3: Update the view**

Edit `app/views/account/connected_accounts/index.html.erb`. Replace the current heading block with:

```erb
<%= render "shared/settings_page_header",
      title: t("settings.pages.security.h1"),
      description: t("settings.pages.security.description") %>
```

Preserve the OAuth provider list and action buttons.

- [ ] **Step 4: Re-run spec — expect PASS**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/account/connected_accounts_destination_spec.rb`
Expected: all 3 examples PASS.

- [ ] **Step 5: Run full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1911 examples (1908 + 3), 0 failures, 1 pending.

- [ ] **Step 6: Commit**

```bash
git add app/views/account/connected_accounts/index.html.erb spec/system/account/connected_accounts_destination_spec.rb
git commit -m "feat(views): Security destination — header partial + AAA spec

Sidebar label is 'Security' (semantic — covers OAuth + future
password/2FA); H1 matches. Dedicated system spec closes the axe AAA
coverage gap surfaced by the Phase 2 panel review (Joël Q.)."
```

---

## Task 6: Appearance destination — route + controller + view + spec (closes #150)

**Files:**

- Modify: `config/routes.rb` (one line)
- Modify: `app/controllers/account/theme_preferences_controller.rb` (add `edit` action)
- Create: `app/views/account/theme_preferences/edit.html.erb`
- Create: `spec/system/account/appearance_destination_spec.rb`

**Steps:**

- [ ] **Step 1: Add the route**

Edit `config/routes.rb`. Find: `resource :theme_preference, only: [ :update ]`. Replace with:

```ruby
resource :theme_preference, only: [ :edit, :update ]
```

- [ ] **Step 2: Add the controller action**

Edit `app/controllers/account/theme_preferences_controller.rb`. Add an `edit` method that just authorizes + renders. Pattern matches existing controllers in `account/`:

```ruby
def edit
  authorize :theme_preference, :edit?, policy_class: Account::ThemePreferencePolicy
end
```

> **Policy class verification:** check if `Account::ThemePreferencePolicy` exists. If not (only `:update?` was needed before), add a minimal `edit?` method to whatever policy the controller already uses for `update`. If no policy file exists at all, the action can call `authorize :theme_preference` and Pundit will look up `ThemePreferencePolicy`.

> **PersonalWorkspaceContext + layout:** if this controller doesn't already include `PersonalWorkspaceContext` and `layout "settings"` (per Phase 2 Task 9), add them now — required for the sidebar to render correctly on this page.

- [ ] **Step 3: Create the view**

Create `app/views/account/theme_preferences/edit.html.erb`:

```erb
<%= render "shared/settings_page_header",
      title: t("settings.pages.appearance.h1"),
      description: t("settings.pages.appearance.description") %>

<div class="max-w-md">
  <%# Theme toggle — reuses the shared/_theme_toggle partial which
      already implements three-way light/dark/system selection
      wired to ThemePreferencesController#update. %>
  <%= render "shared/theme_toggle" %>
</div>
```

> **Why reuse `shared/_theme_toggle`:** Phase 2 explore identified this partial as the existing theme-switch UI. The header dropdown uses it; the new Appearance page mounts the same control inline.

> **What about timezone?** The spec mentions Appearance covers "theme (light/dark/system) + timezone." Phase 3 ships theme only. Timezone is set via `Account::Preferences::TimezonesController#update` and currently has no UI surface besides the auto-detect beacon — its UI is a separate task. Tracked as a follow-up; document in the CHANGELOG.

- [ ] **Step 4: Write the system spec**

Create `spec/system/account/appearance_destination_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Account Appearance destination", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { sign_in_via_form(user) }

  it "renders the Appearance H1" do
    visit edit_account_theme_preference_path
    expect(page).to have_css("h1", text: I18n.t("settings.pages.appearance.h1"))
  end

  it "responds 200 on GET (no longer 405)" do
    visit edit_account_theme_preference_path
    expect(page.status_code).to eq(200) if page.respond_to?(:status_code)
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_account_theme_preference_path
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
```

- [ ] **Step 5: Run the spec**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/account/appearance_destination_spec.rb`
Expected: all 3 examples PASS.

If axe fails, the theme_toggle partial may have AAA issues that weren't surfaced before (it currently lives in the header dropdown). Fix the underlying AAA violation rather than lowering the threshold.

- [ ] **Step 6: Run full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1914 examples (1911 + 3), 0 failures, 1 pending.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/account/theme_preferences_controller.rb app/views/account/theme_preferences/edit.html.erb spec/system/account/appearance_destination_spec.rb
git commit -m "feat(account): build Appearance destination (closes #150)

theme_preference resource now allows :edit alongside :update; new
action authorizes + renders a page wrapped in the settings hub
layout that hosts the existing shared/_theme_toggle control inline.
The sidebar's Appearance link no longer 405s.

Timezone UI is intentionally out of scope here — the timezone-beacon
auto-detect remains the sole timezone surface for now. Tracked for
follow-up."
```

---

## Task 7: Workspace Settings destination — header + workspace-name H1

**Files:**

- Modify: `app/views/workspaces/settings/edit.html.erb`

**Steps:**

- [ ] **Step 1: Find any system spec asserting the old H1**

Run: `grep -n "workspaces.settings.edit.title\|workspace.*settings.*[Hh]eading" spec/system/ -r`

Note any matches. Most likely the org-context spec doesn't pin H1 text (Phase 2 specs assert sidebar items, not destination H1s) — but verify.

- [ ] **Step 2: Update the view**

Edit `app/views/workspaces/settings/edit.html.erb`. Find the current `<h1>` block and replace with:

```erb
<%= render "shared/settings_page_header",
      title: t("settings.pages.workspace_settings.h1_html", name: @workspace.name).html_safe,
      description: t("settings.pages.workspace_settings.description") %>
```

> **`@workspace`:** the controller sets `@workspace` via `WorkspaceScoped#set_workspace`. Verify by reading `app/controllers/workspaces/settings_controller.rb`.

> **`.html_safe`:** the `h1_html` key contains a `<span>` for the muted workspace name. Calling `.html_safe` on the interpolated string preserves the markup. The risk of XSS here is bounded — `@workspace.name` is the only interpolated value, and ActiveRecord stores it as-is. If `name` could contain HTML, escape it before interpolation:

```erb
title: t("settings.pages.workspace_settings.h1_html", name: ERB::Util.html_escape(@workspace.name)).html_safe,
```

The safer pattern. Use it.

> **Header partial caveat:** the partial currently outputs the title via `<%= title %>` which auto-escapes. For HTML titles, the partial needs to detect `html_safe?` and use `raw` — OR add a separate `title_html:` local. Cleanest: extend the partial to accept either `title:` (string, escaped) or `title_html:` (raw HTML).

Update `app/views/shared/_settings_page_header.html.erb`:

```erb
<%# locals: (title: nil, title_html: nil, description: nil) -%>
<header class="mb-8">
  <h1 class="text-2xl font-semibold text-text-heading">
    <% if title_html %>
      <%= title_html.html_safe %>
    <% else %>
      <%= title %>
    <% end %>
  </h1>
  <% if description.present? %>
    <p class="mt-2 text-sm text-text-body max-w-2xl"><%= description %></p>
  <% end %>
</header>
```

Then the workspace settings view call becomes:

```erb
<%= render "shared/settings_page_header",
      title_html: t("settings.pages.workspace_settings.h1_html", name: ERB::Util.html_escape(@workspace.name)),
      description: t("settings.pages.workspace_settings.description") %>
```

- [ ] **Step 3: Run the full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1914 examples, 0 failures, 1 pending. If `org_context_spec.rb` or `settings_layout_subscription_spec.rb` breaks because they asserted the old H1, update those assertions to use the new key.

- [ ] **Step 4: Commit**

```bash
git add app/views/workspaces/settings/edit.html.erb app/views/shared/_settings_page_header.html.erb spec/
git commit -m "feat(views): disambiguated H1 for Workspace Settings destination

H1 now reads '<workspace name> settings' with the workspace name in
a muted weight. Honors the spec's polymorphic-Profile disambiguation
goal even though Profile + Limits & Plan share this destination
(route consolidation tracked separately). The header partial gained
a title_html local for HTML-safe interpolation."
```

---

## Task 8: Workspace Members destination — header + workspace-name H1

**Files:**

- Modify: `app/views/workspaces/members/index.html.erb`

**Steps:**

- [ ] **Step 1: Update the view**

Edit `app/views/workspaces/members/index.html.erb`. Find the current `<h1>` block and replace with:

```erb
<%= render "shared/settings_page_header",
      title_html: t("settings.pages.workspace_members.h1_html", name: ERB::Util.html_escape(@workspace.name)),
      description: t("settings.pages.workspace_members.description") %>
```

Preserve the invite button, filter form, and the turbo_frame results section.

- [ ] **Step 2: Run the full suite**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1914 examples, 0 failures, 1 pending.

`spec/system/members_table_spec.rb` likely doesn't pin H1 text (it tests row interactions) — but if it does, update accordingly.

- [ ] **Step 3: Commit**

```bash
git add app/views/workspaces/members/index.html.erb spec/
git commit -m "feat(views): disambiguated H1 for Workspace Members destination

H1 now reads '<workspace name> members' with the name in a muted
weight, matching the workspace_settings pattern for IA consistency."
```

---

## Task 9: CHANGELOG + file route-consolidation follow-up issue

**Files:**

- Modify: `CHANGELOG.md`

**Steps:**

- [ ] **Step 1: Add CHANGELOG entry**

Edit `CHANGELOG.md` under `## [Unreleased]` → `### Added` (or create the section if needed). Add:

```markdown
- Settings hub destinations: disambiguated H1s + descriptions on each sidebar destination, shared `shared/_settings_page_header.html.erb` partial, and Appearance page (closes #150 — sidebar link no longer 405s).
```

And under `### Changed` (or create):

```markdown
- Account Profile, Notification Preferences, Connected Accounts (Security), and Workspace Settings/Members destinations now use the shared settings page header for consistent chrome.
```

- [ ] **Step 2: File the route-consolidation follow-up**

First search to avoid duplicates: `gh issue list --search "route consolidation workspaces edit" --state all`.

If no existing issue covers it, file:

- Title: "Split workspaces#edit (Profile) from workspaces/settings#edit (Limits & Plan)"
- Body: 5-10 lines covering — the Phase 1 spec promised this; Phase 2 deferred; Phase 3 inherits the divergence (org sidebar's Profile and Limits & Plan land on the same page). The split would let each get its own disambiguated H1 + dedicated AAA spec. ~12 files would change (delete BrandingController, move identity fields, update routes, sidebar links, system specs).

Also file:
- Title: "Settings hub Appearance — add timezone UI"
- Body: Phase 3 shipped the Appearance destination with theme toggle only. Timezone is auto-detected via the existing beacon Stimulus controller but has no manual UI surface. A timezone picker (IANA list + search) within Appearance would let users override auto-detection.

- [ ] **Step 3: Run the FULL suite one last time as the closing verification**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rspec`
Expected: 1914 examples, 0 failures, 1 pending. Line coverage ≥ 95.85% (Phase 2 baseline) — Phase 3 should not regress coverage.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note Phase 3 settings hub destinations"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Disambiguated H1 per destination | 2 (i18n), 3, 5, 6, 7, 8 (views) |
| Polymorphic "Profile" disambiguation across personal + org | 3 ("Your personal profile"), 7 ("<name> settings" with caveat) |
| Shared page chrome for destinations | 1 (header partial), adopted in 3-8 |
| Appearance destination working (closes #150) | 6 |
| AAA coverage gaps closed (Account Profile, Connected Accounts, Appearance) | 3, 5, 6 |
| Visual "shared page skeleton grid" for Profile pages | **Deferred** — documented out-of-scope, Phase 4 work |
| Route consolidation | **Deferred** — documented out-of-scope, separate follow-up issue (Task 9) |
| Timezone UI inside Appearance | **Deferred** — documented out-of-scope, separate follow-up issue (Task 9) |

Out-of-scope items explicitly documented in plan header.

**Placeholder scan:** Each task contains complete code blocks, exact commands, named files. No TBDs.

**Type/identifier consistency:** `settings.pages.<key>.h1` (string title) vs `settings.pages.<key>.h1_html` (HTML-marked title with workspace-name interpolation) — taxonomy is consistent: `_html` suffix means "contains markup, use with `.html_safe` or via `title_html:` local." The partial accepts both `title:` and `title_html:` (Task 7 extends it). All call sites use the right one.

**Suite count progression:** 1905 baseline → 1908 (Task 3) → 1911 (Task 5) → 1914 (Task 6). Tasks 4, 7, 8, 9 don't add examples — they modify existing views without new tests beyond what existing specs cover.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-20-settings-hub-phase-3-destinations.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Same pattern as Phase 2; 9 tasks is well within the loop's working range.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Good if you want continuity (e.g., reading the existing destinations once and applying the header pattern across).

**Which approach?**
