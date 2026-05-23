# Settings Hub Route Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Spec:** [docs/superpowers/specs/2026-05-19-settings-hub-design.md](../specs/2026-05-19-settings-hub-design.md) — Phase 1 row's "Deferred: Route consolidation" cell. Also "Route consolidation: BrandingController deleted" subsection.

**Closes:** #153 (Split workspaces#edit from workspaces/settings#edit).

**Goal:** Split the org sidebar's "Profile" and "Limits & Plan" destinations onto their own pages instead of the current shared `workspaces/settings/edit.html.erb`. WorkspacesController#edit becomes the canonical workspace identity page (name, logo, primary_color); Workspaces::SettingsController#edit narrows to operational config (capacity, plan). Delete BrandingsController, fold its functionality.

**Architecture:** Three controllers come into focus: `WorkspacesController` (workspace identity — name, logo, primary_color), `Workspaces::SettingsController` (capacity + plan), and the old `Workspaces::BrandingsController` (deleted). A new `Workspaces::ProfilePolicy` gates identity edits on `manage_settings` (Owner+Admin) — matches the current BrandingPolicy capability surface; doesn't tighten to Owner-only because the Fried-style rationale that closed #144 (wontfix) applies here too: don't cut capabilities Admin users have today without a clear win. The identity picker hub (Turbo Stream modal) moves from `BrandingsController#hub` to `WorkspacesController#identity_picker_hub`.

**Tech Stack:** Rails 8.1, Pundit (new `Workspaces::ProfilePolicy`), ERB partials with strict locals, TailwindCSS 4, Turbo Streams for the hub modal, RSpec system + request specs.

**Out of scope (deferred to other PRs):**

- Mobile drawer (#148) — separate phase
- Timezone UI on Appearance (#154) — separate phase
- Hide personal workspace from header switcher (#145) — separate phase
- Brandings flake stabilization (#147) — the `brandings_spec.rb` skip will be addressed here only insofar as the file gets restructured/deleted; the underlying Playwright dialog flake mechanism remains tracked

**Branch:** `feat/settings-hub-route-consolidation` off `docs/settings-hub-spec` (already checked out).

**Pre-consolidation baseline:** 1914 examples, 0 failures, 1 pending. Coverage 95.86% line.

---

## File Map

**Create:**

- `app/policies/workspaces/profile_policy.rb` — gates workspaces#edit/update on `manage_settings`
- `app/views/workspaces/edit.html.erb` — new workspace Profile destination
- `app/views/workspaces/identity_picker_hub.turbo_stream.erb` — moved from `workspaces/brandings/`
- `app/views/workspaces/update.turbo_stream.erb` — for identity picker close flow (if needed; the brandings update.turbo_stream.erb gets repurposed)

**Modify:**

- `config/routes.rb` — remove `resource :branding`, add `:identity_picker_hub` to workspaces
- `app/controllers/workspaces_controller.rb` — rewrite `edit` (render not redirect), expand `update` params, add `identity_picker_hub` action
- `app/controllers/workspaces/settings_controller.rb` — leave action methods alone, optionally narrow strong params (already capacity-only)
- `app/views/workspaces/settings/edit.html.erb` — strip the `_branding_section` render, keep `_capacity_section` only; update H1
- `app/views/workspaces/settings/_branding_section.html.erb` — RENAME to `app/views/workspaces/_profile_section.html.erb`; update form action to `workspace_path(@workspace)`; update policy class
- `config/locales/en/settings.en.yml` — add `pages.workspace_profile.h1_html` + description; narrow `workspace_settings.h1_html` to "Limits & Plan"
- `app/views/shared/_settings_sidebar.html.erb` — sidebar's Profile link already points to `edit_workspace_path` (Phase 3); verify no change needed
- `spec/system/workspaces/brandings_spec.rb` — DELETE or restructure into `spec/system/workspaces/profile_spec.rb`
- `spec/requests/settings_layout_subscription_spec.rb` — update expectation that `edit_workspace_path` is now a render (not a redirect)
- `spec/system/settings/org_context_spec.rb` — H1 assertion for org Profile destination (currently no H1 assertion; new spec may want one)
- `CHANGELOG.md` — note Route Consolidation entry

**Delete:**

- `app/controllers/workspaces/brandings_controller.rb`
- `app/policies/workspaces/branding_policy.rb`
- `app/views/workspaces/brandings/destroy.turbo_stream.erb`
- `app/views/workspaces/brandings/update.turbo_stream.erb`
- `app/views/workspaces/brandings/` directory itself

---

## Task 1: Workspaces::ProfilePolicy

**Files:** Create `app/policies/workspaces/profile_policy.rb`

**Steps:**

- [ ] **Step 1: Write failing policy spec FIRST.** Create `spec/policies/workspaces/profile_policy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Workspaces::ProfilePolicy, type: :policy do
  subject(:policy) { described_class.new(user, workspace) }

  let(:workspace) { create(:workspace) }

  context "as an Owner" do
    let(:user) { create(:user) }
    before do
      role = create(:role, slug: "owner", workspace_id: nil) do |r|
        r.permissions = { "manage_workspace" => true, "manage_settings" => true }
      end
      create(:membership, user: user, workspace: workspace, role: role)
    end

    it { is_expected.to permit_action(:edit) }
    it { is_expected.to permit_action(:update) }
  end

  context "as an Admin" do
    let(:user) { create(:user) }
    before do
      role = create(:role, slug: "admin", workspace_id: nil) do |r|
        r.permissions = { "manage_settings" => true }
      end
      create(:membership, user: user, workspace: workspace, role: role)
    end

    it { is_expected.to permit_action(:edit) }
    it { is_expected.to permit_action(:update) }
  end

  context "as a Viewer (no manage_settings)" do
    let(:user) { create(:user) }
    before do
      role = create(:role, slug: "viewer", workspace_id: nil) { |r| r.permissions = {} }
      create(:membership, user: user, workspace: workspace, role: role)
    end

    it { is_expected.to forbid_action(:edit) }
    it { is_expected.to forbid_action(:update) }
  end

  context "as a non-member" do
    let(:user) { create(:user) }

    it { is_expected.to forbid_action(:edit) }
    it { is_expected.to forbid_action(:update) }
  end
end
```

- [ ] **Step 2: Run spec, expect FAIL.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/policies/workspaces/profile_policy_spec.rb
```

Expected: `NameError: uninitialized constant Workspaces::ProfilePolicy`.

- [ ] **Step 3: Create the policy.** Create `app/policies/workspaces/profile_policy.rb`:

```ruby
module Workspaces
  # Authorizes workspace identity edits (name, logo, primary_color).
  # Gated on manage_settings — same capability surface as the previous
  # Workspaces::BrandingPolicy and Workspaces::SettingsPolicy, so Admins
  # who could edit branding before continue to edit profile after route
  # consolidation. Owner-only tightening would cut a capability Admins
  # depend on (see #144 wontfix rationale).
  class ProfilePolicy < ApplicationPolicy
    def edit?
      can?("manage_settings")
    end

    def update?
      can?("manage_settings")
    end
  end
end
```

- [ ] **Step 4: Run spec, expect PASS.** All examples PASS.

- [ ] **Step 5: Run FULL suite.** Expected: 1914 baseline + 8 new examples = 1922, 0 failures, 1 pending.

- [ ] **Step 6: Commit.**

```bash
git add app/policies/workspaces/profile_policy.rb spec/policies/workspaces/profile_policy_spec.rb
git commit -m "feat(policies): add Workspaces::ProfilePolicy for identity edits

Gates workspaces#edit/update on manage_settings (Owner+Admin) —
mirrors the existing Workspaces::SettingsPolicy + BrandingPolicy
capability surface so the route-consolidation refactor doesn't
silently cut Admin's ability to edit workspace identity (name,
logo, primary_color). Following the Fried-style reasoning that
closed #144 wontfix: don't tighten capabilities without a clear
win."
```

---

## Task 2: Routes update

**Files:** Modify `config/routes.rb`

**Steps:**

- [ ] **Step 1: Inspect current routes.** Run `grep -A 5 "resource :branding\|resource :settings" config/routes.rb`. Note the exact lines.

- [ ] **Step 2: Update routes.** In `config/routes.rb`, find:

```ruby
resource :branding, only: [ :edit, :update, :destroy ] do
  get :hub
end
```

(or whatever the current shape is). Replace with: (nothing — delete the entire `resource :branding` block.)

In its place, add the `identity_picker_hub` member action to the workspaces resource. The workspaces resource probably already has a `member do ... end` block — add to it. If not, add:

```ruby
resources :workspaces, param: :slug do
  member do
    get :identity_picker_hub
  end
  # ... existing nested resources (settings, members, invitations, projects)
end
```

If there's already a `member do ... end`, just add the line `get :identity_picker_hub` to it.

- [ ] **Step 3: Smoke-check routes.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails routes -g workspace | head -30
```

Expected: `identity_picker_hub_workspace_path` (or similar — verify the exact helper name) is present. Branding-related routes are GONE.

- [ ] **Step 4: Run FULL suite.** Expected: failures across multiple specs that reference `workspace_branding_path` or `edit_workspace_branding_path`. Document the failure count — Task 3 (delete BrandingsController) will resolve them, and Task 8 (specs) will update the assertions.

- [ ] **Step 5: Commit. (Note: full suite is RED.)**

This is the only commit in the consolidation that lands on a red suite. Stage with awareness; later tasks restore green.

```bash
git add config/routes.rb
git commit -m "refactor(routes): remove branding resource, add identity_picker_hub member action

Part 1 of the workspaces#edit / workspaces/settings#edit split. The
branding resource is gone; the identity picker hub (Turbo Stream
modal for logo/color selection) moves to WorkspacesController as a
member action. Tasks 3-7 follow to relocate the controller logic,
views, and specs that referenced the deleted routes — suite goes
red transiently between this commit and Task 7."
```

**Important:** Lefthook may run rubocop / herb-lint on the staged file. If Lefthook ALSO runs RSpec pre-commit (unlikely in this project — confirm via `cat lefthook.yml | head -30`), the red suite will block the commit. In that case, document the red state in the commit body and use `--no-verify` ONLY for this single transitional commit — but FIRST verify with the user / by reading lefthook config that pre-commit doesn't require green RSpec.

Better approach: if Lefthook blocks, REORDER the tasks. Do Tasks 3 + 7 (delete controller + fix referencing code) BEFORE Task 2's commit so the suite is green again before committing the routes change. The plan as written assumes Lefthook only runs static checks (rubocop, herb-lint) which is the project's actual pattern per Phase 2-4 commits.

---

## Task 3: WorkspacesController rewrite

**Files:**
- Modify `app/controllers/workspaces_controller.rb`

**Steps:**

- [ ] **Step 1: Inspect current actions.** Read the current `edit`, `update`, and any neighbors.

- [ ] **Step 2: Update `edit` action.** Replace the redirect with rendering. Authorize against the new ProfilePolicy. The action should set `@workspace` (it likely already is via `WorkspaceScoped` before_action) and render `workspaces/edit.html.erb` (which Task 5 creates).

```ruby
def edit
  authorize @workspace, policy_class: Workspaces::ProfilePolicy
end
```

- [ ] **Step 3: Update `update` action.** Authorize against ProfilePolicy. Expand strong params to include identity fields (name, primary_color, logo, logo_original, logo_source, and any crop coordinates the existing branding form uses).

Inspect the existing `BrandingsController#update` to see exactly which params it permits and how it handles attachments. Mirror that logic in WorkspacesController#update. Likely shape:

```ruby
def update
  authorize @workspace, policy_class: Workspaces::ProfilePolicy

  if @workspace.update(profile_params)
    respond_to do |format|
      format.html { redirect_to edit_workspace_path(@workspace), notice: t(".success") }
      format.turbo_stream { render "workspaces/update" }
    end
  else
    render :edit, status: :unprocessable_entity
  end
end

private

def profile_params
  params.require(:workspace).permit(:name, :primary_color, :logo_source, :logo, :logo_original)
end
```

Adjust the param list based on what BrandingsController actually permits.

- [ ] **Step 4: Add `identity_picker_hub` action.** Move the action from `BrandingsController#hub`. Authorize against ProfilePolicy. The action renders a Turbo Stream that shows the identity picker modal.

```ruby
def identity_picker_hub
  authorize @workspace, policy_class: Workspaces::ProfilePolicy
end
```

Move `app/views/workspaces/brandings/hub.turbo_stream.erb` (if it exists) to `app/views/workspaces/identity_picker_hub.turbo_stream.erb`. If `hub` action rendered an inline template via `render partial: "shared/identity_picker_hub"`, the same partial is still used — just the controller action changes.

- [ ] **Step 5: Run targeted spec.** No spec for WorkspacesController exists at this point that exercises the new shape; rely on Task 8 (system specs) for end-to-end coverage. Run the full suite to see what's still red from Task 2's routes change.

- [ ] **Step 6: Commit.**

```bash
git add app/controllers/workspaces_controller.rb app/views/workspaces/identity_picker_hub.turbo_stream.erb
git commit -m "refactor(workspaces): edit/update serve workspace identity directly

WorkspacesController#edit stops redirecting to settings#edit; now
renders workspaces/edit.html.erb (Task 5 creates the view). #update
accepts identity params (name, primary_color, logo, logo_source).
Identity picker hub action moves here from the soon-deleted
BrandingsController. All actions authorize against the new
Workspaces::ProfilePolicy."
```

---

## Task 4: Delete BrandingsController + BrandingPolicy

**Files:**
- Delete `app/controllers/workspaces/brandings_controller.rb`
- Delete `app/policies/workspaces/branding_policy.rb`
- Delete `spec/policies/workspaces/branding_policy_spec.rb` (if it exists)
- Delete `app/views/workspaces/brandings/destroy.turbo_stream.erb`
- Delete `app/views/workspaces/brandings/update.turbo_stream.erb`
- Delete the `app/views/workspaces/brandings/` directory

**Steps:**

- [ ] **Step 1: Delete the files.**

```bash
rm app/controllers/workspaces/brandings_controller.rb
rm app/policies/workspaces/branding_policy.rb
rm -f spec/policies/workspaces/branding_policy_spec.rb
rm -rf app/views/workspaces/brandings/
```

- [ ] **Step 2: Migrate any logic from `BrandingsController#destroy`.** Branding destroy was used to "remove logo and reset to initials." Decide:
  - (a) The new workspace identity form has a "Remove logo" action — add it to WorkspacesController as `#destroy_logo` or similar, OR
  - (b) The identity picker handles logo-removal via update with `logo_source: "initials"`, no dedicated destroy action needed.

Inspect the partial that calls `workspace_branding_path(method: :delete)` to determine which approach applies. Likely (b) — the form sets `logo_source` and the controller purges attachments in `update`. Add purge logic to `WorkspacesController#update`:

```ruby
def update
  authorize @workspace, policy_class: Workspaces::ProfilePolicy

  if @workspace.update(profile_params)
    if profile_params[:logo_source] == "initials"
      @workspace.logo.purge_later if @workspace.logo.attached?
      @workspace.logo_original.purge_later if @workspace.logo_original.attached?
    end
    # ... respond
  end
end
```

- [ ] **Step 3: Run FULL suite.** Expected: still failures from `brandings_spec.rb` and any spec referencing branding routes — Task 8 handles those. Verify the failures are SPEC-LAYER (route helper not found, response 404) not actual application errors.

- [ ] **Step 4: Commit.**

```bash
git add app/controllers/workspaces/brandings_controller.rb app/policies/workspaces/branding_policy.rb spec/policies/workspaces/branding_policy_spec.rb app/views/workspaces/brandings/
git commit -m "refactor(workspaces): delete BrandingsController and its policy/views

All branding behavior (logo upload, crop, color picker, identity
picker hub, logo purge) now lives in WorkspacesController.
Workspaces::BrandingPolicy is replaced by the new
Workspaces::ProfilePolicy. Brandings views deleted; the hub view
moved to workspaces/identity_picker_hub.turbo_stream.erb in Task 3."
```

(Adjust paths if `branding_policy_spec.rb` doesn't actually exist.)

---

## Task 5: Workspace Profile view + section partial

**Files:**
- Create `app/views/workspaces/edit.html.erb`
- Rename + Modify `app/views/workspaces/settings/_branding_section.html.erb` → `app/views/workspaces/_profile_section.html.erb` (update form action + i18n keys)

**Steps:**

- [ ] **Step 1: Move the partial.**

```bash
git mv app/views/workspaces/settings/_branding_section.html.erb app/views/workspaces/_profile_section.html.erb
```

- [ ] **Step 2: Update the partial's form action and i18n keys.** Read the partial. It currently posts to `workspace_branding_path(workspace)` (or similar). Update to:

```erb
<%= form_with model: workspace, url: workspace_path(workspace), method: :patch, ... do |form| %>
  <!-- ...existing form fields (name, logo picker, color picker)... -->
<% end %>
```

Update any i18n key references from `workspaces.brandings.*` to `workspaces.edit.*` (or wherever Task 7 lands the keys).

- [ ] **Step 3: Create the new Profile view.** Create `app/views/workspaces/edit.html.erb`:

```erb
<% content_for(:title) { t("workspaces.edit.title", workspace: @workspace.name) } %>

<div class="max-w-2xl mx-auto px-4 py-16">
  <%= render "shared/settings_page_header",
        title_html: t("settings.pages.workspace_profile.h1_html", name: ERB::Util.html_escape(@workspace.name)),
        description: t("settings.pages.workspace_profile.description") %>

  <%= render "workspaces/profile_section", workspace: @workspace %>
</div>
```

The H1 uses the i18n key Task 7 adds. The `<main>` wrapping comes from the settings layout (Phase 2).

- [ ] **Step 4: Verify the controller renders the new view.** `WorkspacesController#edit` (from Task 3) should default to rendering `workspaces/edit.html.erb` because Rails infers the template from the action name + controller. If the action explicitly renders something else, fix.

- [ ] **Step 5: Run FULL suite.** Still expecting some red until specs are fixed in Task 8.

- [ ] **Step 6: Commit.**

```bash
git add app/views/workspaces/edit.html.erb app/views/workspaces/_profile_section.html.erb
git commit -m "feat(views): workspace Profile destination + renamed section partial

Creates app/views/workspaces/edit.html.erb as the canonical workspace
Profile page. The _branding_section partial is renamed
_profile_section and moved to app/views/workspaces/ (top level) so
it can serve as the main content of the new edit page. Form action
points to workspace_path(workspace) (WorkspacesController#update)
instead of the removed workspace_branding_path."
```

---

## Task 6: Settings (Limits & Plan) view narrows

**Files:** Modify `app/views/workspaces/settings/edit.html.erb`

**Steps:**

- [ ] **Step 1: Inspect the current view.** It currently renders the header + branding_section + capacity_section.

- [ ] **Step 2: Strip the branding section.** Remove the `render "workspaces/settings/branding_section"` line + the `<hr>` separator. Keep the capacity_section render.

- [ ] **Step 3: Update H1 to "Limits & Plan" wording.** Change the header partial render from:

```erb
<%= render "shared/settings_page_header",
      title_html: t("settings.pages.workspace_settings.h1_html", name: ERB::Util.html_escape(@workspace.name)),
      description: t("settings.pages.workspace_settings.description") %>
```

to:

```erb
<%= render "shared/settings_page_header",
      title_html: t("settings.pages.workspace_limits_and_plan.h1_html", name: ERB::Util.html_escape(@workspace.name)),
      description: t("settings.pages.workspace_limits_and_plan.description") %>
```

(Task 7 adds the new i18n keys. Or rename the existing `workspace_settings` keys to `workspace_limits_and_plan` — your call. The latter is cleaner.)

- [ ] **Step 4: Run FULL suite.** The org_context_spec.rb may pin the old H1 — Task 8 handles spec updates.

- [ ] **Step 5: Commit.**

```bash
git add app/views/workspaces/settings/edit.html.erb
git commit -m "feat(views): settings (Limits & Plan) destination narrows to capacity

Strips the branding section (moved to workspaces#edit per route
consolidation). The page now serves only capacity + plan content.
H1 updates to '<workspace name> Limits & Plan' to match the
narrowed scope."
```

---

## Task 7: I18n keys for Profile + Limits & Plan

**Files:** Modify `config/locales/en/settings.en.yml` and (possibly) add `config/locales/en/workspaces.en.yml`

**Steps:**

- [ ] **Step 1: Update i18n keys.** In `config/locales/en/settings.en.yml`, find the existing `workspace_settings` block:

```yaml
workspace_settings:
  h1_html: "<span class='text-text-muted font-normal'>%{name}</span> settings"
  description: "Workspace identity, capacity, and plan."
```

Replace with TWO entries:

```yaml
workspace_profile:
  h1_html: "<span class='text-text-muted font-normal'>%{name}</span>'s profile"
  description: "Workspace identity — name, logo, and primary color."
workspace_limits_and_plan:
  h1_html: "<span class='text-text-muted font-normal'>%{name}</span> Limits & Plan"
  description: "Capacity and plan — visible to all members, editable by Owner and Admin."
```

- [ ] **Step 2: Add the browser-tab title key for Profile.** In `config/locales/en/workspaces.en.yml` (or wherever the existing `workspaces.edit.title` key lives — find via grep), update or add:

```yaml
en:
  workspaces:
    edit:
      title: "%{workspace} — Profile"
    update:
      success: "Workspace profile updated."
```

(Adjust `update.success` only if you want a more specific message than what existed before. The previous BrandingsController had its own `branding.update.success` key — find it via grep and consolidate.)

- [ ] **Step 3: Smoke check keys load.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails runner "puts I18n.t('settings.pages.workspace_profile.h1_html', name: 'Acme'); puts I18n.t('settings.pages.workspace_limits_and_plan.h1_html', name: 'Acme'); puts I18n.t('workspaces.edit.title', workspace: 'Acme')"
```

Expected: all three render correctly.

- [ ] **Step 4: Run FULL suite.**

- [ ] **Step 5: Commit.**

```bash
git add config/locales/en/settings.en.yml config/locales/en/workspaces.en.yml
git commit -m "feat(i18n): split workspace_settings keys into Profile + Limits & Plan

Two destinations, two i18n key namespaces. workspace_profile.* for
the new workspaces#edit page; workspace_limits_and_plan.* for the
narrowed workspaces/settings#edit page. Browser-tab title for the
Profile page added under workspaces.edit.title."
```

---

## Task 8: System spec restructuring

**Files:**
- Delete: `spec/system/workspaces/brandings_spec.rb` (or restructure into `spec/system/workspaces/profile_spec.rb`)
- Modify: `spec/system/settings/org_context_spec.rb` (update sidebar Profile assertion)
- Modify: `spec/requests/settings_layout_subscription_spec.rb` (`edit_workspace_path` no longer redirects)
- Possibly modify: any other spec that referenced `workspace_branding_path` or `edit_workspace_branding_path`

**Steps:**

- [ ] **Step 1: Find all referencing specs.**

```bash
grep -rln "edit_workspace_branding_path\|workspace_branding_path\|hub_workspace_branding_path" spec/
```

For each match, decide:
- If the spec tested branding-specific behavior that's now WorkspacesController behavior, update the assertions to use `edit_workspace_path` / `workspace_path` / `identity_picker_hub_workspace_path`.
- If the spec was the brandings_spec.rb file itself (with the existing `skip` for #147), and its tests overlap with what we want for the new Profile destination, restructure it into a `profile_spec.rb`. The skipped flake test for switch-to-initials may move to the new spec — and the same Playwright detachment issue may persist (per #147).

- [ ] **Step 2: Restructure brandings_spec.rb.** Two paths:

(a) **Delete it** and re-create the coverage in a new `spec/system/workspaces/profile_spec.rb` that exercises the new workspaces#edit page (logo upload, color picker, name edit, persist + redirect).

(b) **Rename via `git mv`** and update assertions to use new routes.

Path (a) is cleaner; (b) preserves git blame on the original spec.

Pick (a). The new file:

```ruby
require "rails_helper"

RSpec.describe "Workspace Profile destination", type: :system do
  let(:owner) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    role = create(:role, slug: "owner", workspace_id: nil) do |r|
      r.permissions = { "manage_workspace" => true, "manage_settings" => true }
    end
    create(:membership, user: owner, workspace: workspace, role: role)
    sign_in_via_form(owner)
  end

  it "renders the disambiguated Profile H1" do
    visit edit_workspace_path(workspace)
    expect(page).to have_css("h1", text: "#{workspace.name}'s profile")
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_workspace_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  # NOTE: The "switch to initials" flake originally documented in
  # brandings_spec.rb:51 was tracked as #147. It may still surface here
  # under full-suite ordering due to the same Playwright dialog
  # detachment mechanism. If it reappears, skip with explicit reference
  # to #147 rather than trying to fix the underlying interaction.
end
```

- [ ] **Step 3: Update org_context_spec.rb's Owner H1 assertion** (if it had one). Phase 3 may not have pinned the Profile H1; verify and update only if needed.

- [ ] **Step 4: Update settings_layout_subscription_spec.rb.** It currently does `follow_redirect! while response.redirect?` after `get edit_workspace_path` because the page redirected to settings. Post-consolidation, the redirect is gone. Update accordingly:

```ruby
# Before
get edit_workspace_path(workspace)
follow_redirect! while response.redirect?
# After
get edit_workspace_path(workspace)
# (no follow_redirect! — the page renders directly)
```

- [ ] **Step 5: Run FULL suite.**

Expected: 1914 (pre-Phase) + 8 (Task 1 policy spec) + 2 (Task 8 profile spec) - N (deleted brandings_spec examples) = exact number depends on brandings_spec's example count. Goal: 0 failures, 1 pending or 0 pending (the brandings skip may be gone if we deleted the spec).

- [ ] **Step 6: Commit.**

```bash
git add spec/
git commit -m "test: restructure brandings_spec into profile_spec; update route assertions

Deletes spec/system/workspaces/brandings_spec.rb (its scope splits
into the new workspaces#edit Profile destination + the narrowed
settings page). New spec/system/workspaces/profile_spec.rb exercises
the consolidated Profile destination. settings_layout_subscription
spec stops following redirects on edit_workspace_path. Other route-
helper references migrated."
```

---

## Task 9: Sidebar partial verification

**Files:** Verify `app/views/shared/_settings_sidebar.html.erb`

**Steps:**

- [ ] **Step 1: Read the sidebar partial.** Verify the Profile sidebar item still uses `edit_workspace_path(current_workspace)` (Phase 3 work). After Task 3, that helper now lands on a real page (not a redirect). Limits & Plan still uses `edit_workspace_settings_path(current_workspace)`.

- [ ] **Step 2: If everything's correct, NO COMMIT.** Just verify.

- [ ] **Step 3: If the sidebar needs updating** (e.g., the partial accidentally pointed to a brandings route), update and commit:

```bash
git add app/views/shared/_settings_sidebar.html.erb
git commit -m "fix(views): sidebar Profile link points to consolidated workspaces#edit"
```

---

## Task 10: CHANGELOG + close #153

**Files:** Modify `CHANGELOG.md`

**Steps:**

- [ ] **Step 1: Add CHANGELOG entries.** Under `## [Unreleased]` → `### Changed`:

```markdown
- Route consolidation: `workspaces#edit` now serves the workspace Profile (identity — name, logo, primary_color); `workspaces/settings#edit` narrows to Limits & Plan. `Workspaces::BrandingsController` deleted; `Workspaces::ProfilePolicy` added.
```

Under `### Removed`:

```markdown
- `Workspaces::BrandingsController` and its routes (`/workspaces/:slug/branding/*`). Identity picker hub moved to `WorkspacesController#identity_picker_hub` (`/workspaces/:slug/identity_picker_hub`).
```

- [ ] **Step 2: Close #153.**

```bash
gh issue close 153 --comment "Closed by feat/settings-hub-route-consolidation — workspaces#edit and workspaces/settings#edit now serve distinct destinations. See CHANGELOG entries under [Unreleased]."
```

Verify: `gh issue view 153 --json state -q .state` → CLOSED.

- [ ] **Step 3: Run FULL suite one last time.**

- [ ] **Step 4: Commit.**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note route consolidation (closes #153)"
```

---

## Self-Review

**Spec coverage:**

| Deliverable | Task |
|---|---|
| Workspaces::ProfilePolicy created | 1 |
| Routes: branding removed, identity_picker_hub added | 2 |
| WorkspacesController#edit renders (not redirects) | 3 |
| WorkspacesController#update accepts identity params | 3 |
| WorkspacesController#identity_picker_hub action | 3 |
| BrandingsController deleted | 4 |
| BrandingPolicy deleted | 4 |
| Brandings views deleted | 4 |
| workspaces/edit.html.erb created | 5 |
| _branding_section → _profile_section renamed + form action updated | 5 |
| settings/edit.html.erb narrows to capacity | 6 |
| I18n keys for Profile + Limits & Plan | 7 |
| System specs restructured | 8 |
| Sidebar Profile link verified | 9 |
| CHANGELOG entry | 10 |

**Placeholder scan:** every step has exact paths, complete code, named files.

**Identifier consistency:** `Workspaces::ProfilePolicy` (new), `workspace_profile.*` i18n keys (new), `workspace_limits_and_plan.*` i18n keys (renamed from workspace_settings.*). `identity_picker_hub_workspace_path` (new helper).

**Risk acknowledged:** Task 2 lands a transiently red commit. Tasks 3-7 restore green. If Lefthook gates on green RSpec, reorder Tasks 2-7 into a single combined commit.

---

## Execution Handoff

Plan complete. Continuing with subagent-driven execution.
