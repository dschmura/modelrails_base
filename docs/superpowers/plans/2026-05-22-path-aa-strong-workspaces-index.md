# Path AA — Strong Workspaces Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `workspaces#index` from a phonebook into a workbench per Jason Fried's "weak index" critique: pinned current workspace by last-accessed, rich row metadata (role/plan/member-count/last-accessed), Switch + Leave inline verbs, Discardable-safe member count from preloaded relation.

**Architecture:** New `memberships.last_accessed_at` column written by a single `update_all` per request inside the existing `WorkspaceScoped` concern. Sort by `last_accessed_at DESC NULLS LAST, name ASC` — "current" is the first row, no new user-level state. `MembershipPolicy#destroy?` amended to permit self-leave under safety gates (not personal workspace, not last owner); existing `Membership#deactivate!` is the model-level enforcement. Existing `Workspaces::MembersController#destroy` handles both admin-deactivate and self-leave via conditional redirect. View rewrite extracts `_row.html.erb` + `_leave_button.html.erb`; whole-row clickability via JS-free `relative + z-10` button overlay pattern.

**Tech Stack:** Rails 8.1, Ruby 4.0.4, SQLite (Solid Queue/Cache), TailwindCSS 4 with semantic tokens, Stimulus (minimal — just confirm-dialog wiring), RSpec + Capybara/Playwright, axe-core WCAG 2.2 AAA. Pundit for authorization. Discardable concern for soft-delete-aware queries.

**Spec:** `docs/superpowers/specs/2026-05-22-strong-workspaces-index-design.md` (approved, committed `f7ea915`).

**Branch:** `feat/path-aa-strong-workspaces-index` off `docs/settings-hub-spec`.

**Pre-task baseline:** 1910 / 0 / 0 (verified after `f7ea915` design-spec commit).

**Tasks (9):**

1. Schema + Membership model spec — `last_accessed_at` column
2. WorkspaceScoped touch before_action + concern/integration specs
3. Locale keys — row labels + leave flash messages
4. MembershipPolicy amendment + policy spec
5. MembersController#destroy redirect-by-case + request spec
6. WorkspacesController#index query rewrite (controller + minimal view)
7. View rewrite: `_row.html.erb`, `_leave_button.html.erb`, single-membership branch
8. System spec rewrite (UX assertions + axe-AAA both themes)
9. CHANGELOG + final verification + merge

---

## File Structure

**Create:**
- `db/migrate/<timestamp>_add_last_accessed_at_to_memberships.rb` — schema change
- `app/views/workspaces/_row.html.erb` — row partial (locals: `membership:, current: false`)
- `app/views/workspaces/_leave_button.html.erb` — leave button partial (locals: `membership:`)
- `spec/system/workspaces/index_spec.rb` — rewritten system spec (replaces any existing)

**Modify:**
- `app/controllers/concerns/workspace_scoped.rb` — add `touch_membership_last_accessed`
- `app/policies/membership_policy.rb` — amend `destroy?` for self-leave
- `app/controllers/workspaces/members_controller.rb` — `destroy` branches on self vs admin
- `app/controllers/workspaces_controller.rb` — `index` action: `@current_membership` / `@other_memberships`
- `app/views/workspaces/index.html.erb` — full rewrite (orchestrates sections)
- `config/locales/en/workspaces.en.yml` — row labels + leave flash messages
- `CHANGELOG.md` — Changed entry

**Specs added/modified:**
- `spec/models/membership_spec.rb` — column + index assertion
- `spec/controllers/concerns/workspace_scoped_spec.rb` — touch branches + silent rescue
- `spec/system/workspaces/membership_touch_spec.rb` — integration: visit workspace → timestamp updates
- `spec/policies/membership_policy_spec.rb` — self-leave / personal / last-owner / admin / non-member cases
- `spec/requests/workspaces/members_spec.rb` — destroy redirect branching
- `spec/system/workspaces/index_spec.rb` — full UX coverage

---

## Task 1: Schema + Membership model spec

**Files:**
- Create: `db/migrate/<timestamp>_add_last_accessed_at_to_memberships.rb`
- Modify: `db/schema.rb` (auto-updated)
- Test: `spec/models/membership_spec.rb`

- [ ] **Step 1: Generate the migration.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails generate migration AddLastAccessedAtToMemberships last_accessed_at:datetime
```

This creates a migration file named like `db/migrate/20260522HHMMSS_add_last_accessed_at_to_memberships.rb`.

- [ ] **Step 2: Edit the migration to add the composite index.**

Replace the generated migration body with:

```ruby
class AddLastAccessedAtToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :last_accessed_at, :datetime
    add_index  :memberships, [ :user_id, :last_accessed_at ]
  end
end
```

The composite index supports the `Current.user.memberships.kept.order("memberships.last_accessed_at DESC")` query pattern. We scope by `user_id` first (most selective), then by `last_accessed_at` (sort).

- [ ] **Step 3: Run the migration.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails db:migrate
```

Expected output ends with: `== AddLastAccessedAtToMemberships: migrated`.

- [ ] **Step 4: Verify schema.rb was updated.**

```bash
grep -n "last_accessed_at" db/schema.rb
```

Expected: one or two lines showing the column on `memberships` and the index.

- [ ] **Step 5: Add a failing model spec for the column.**

Append to `spec/models/membership_spec.rb` (or create the file if absent — look for existing pattern):

```ruby
require "rails_helper"

RSpec.describe Membership, type: :model do
  describe "schema" do
    it "has a last_accessed_at datetime column" do
      expect(Membership.columns_hash["last_accessed_at"].sql_type_metadata.type).to eq(:datetime)
    end

    it "has a composite index on [user_id, last_accessed_at]" do
      indexes = ActiveRecord::Base.connection.indexes("memberships")
      index = indexes.find { |i| i.columns == [ "user_id", "last_accessed_at" ] }
      expect(index).to be_present, "Expected composite index on (user_id, last_accessed_at)"
    end
  end
end
```

- [ ] **Step 6: Run the targeted spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/models/membership_spec.rb -e "schema"
```

Expected: PASS (both examples).

- [ ] **Step 7: Run FULL suite to confirm no regression.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: 1910 + 2 new examples = **1912 examples, 0 failures, 0 pending**.

- [ ] **Step 8: Commit.**

```bash
git checkout -b feat/path-aa-strong-workspaces-index
git add db/migrate/ db/schema.rb spec/models/membership_spec.rb
git commit -m "feat(db): add memberships.last_accessed_at (Path AA Task 1)

Single datetime column + composite index on (user_id, last_accessed_at).
Index supports the Current.user.memberships.kept.order(last_accessed_at)
query pattern the strengthened workspaces#index will use.

No backfill — existing memberships have NULL last_accessed_at and
will sort to 'Never accessed' until they receive their first touch
(Task 2).

Suite: 1910 → 1912 / 0 / 0."
```

---

## Task 2: WorkspaceScoped touch before_action + concern/integration specs

**Files:**
- Modify: `app/controllers/concerns/workspace_scoped.rb`
- Create: `spec/controllers/concerns/workspace_scoped_spec.rb` (if absent)
- Create: `spec/system/workspaces/membership_touch_spec.rb`

- [x] **Step 1: Failing concern spec.** Create `spec/controllers/concerns/workspace_scoped_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe WorkspaceScoped, type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    sign_in_via_form(user)
  end

  describe "touch_membership_last_accessed" do
    it "updates the membership's last_accessed_at when visiting a workspace-scoped page" do
      freeze_time do
        get workspace_path(workspace)
        expect(membership.reload.last_accessed_at).to eq(Time.current)
      end
    end

    it "does not touch discarded memberships" do
      original = 1.day.ago
      membership.update_column(:last_accessed_at, original)
      membership.discard!

      # Discarded membership shouldn't be touched; visiting the workspace will
      # raise/redirect via set_workspace's RecordNotFound branch.
      get workspace_path(workspace)
      expect(membership.reload.last_accessed_at).to be_within(1.second).of(original)
    end

    it "silently swallows touch failures (Rails.error.report)" do
      allow(Membership).to receive(:where).and_call_original
      # Inject a failure on the touch query only.
      bad_relation = double("ActiveRecord::Relation")
      allow(bad_relation).to receive(:update_all).and_raise(ActiveRecord::StatementInvalid, "boom")
      allow(Membership).to receive(:where)
        .with(hash_including(:user_id, :workspace_id, :discarded_at))
        .and_return(bad_relation)

      expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::StatementInvalid), anything)
      expect { get workspace_path(workspace) }.not_to raise_error
    end
  end
end
```

- [x] **Step 2: Run the spec to verify it fails.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/controllers/concerns/workspace_scoped_spec.rb
```

Expected: FAILS — `touch_membership_last_accessed` doesn't exist; the `last_accessed_at` won't move.

- [x] **Step 3: Add the before_action to the concern.** Modify `app/controllers/concerns/workspace_scoped.rb` to:

```ruby
module WorkspaceScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_workspace
    before_action :touch_membership_last_accessed
  end

  private

  def set_workspace
    slug = params[:workspace_slug] || params[:slug]
    @workspace = Current.user.workspaces.kept.find_by!(slug: slug)
    Current.workspace = @workspace
    session[:current_workspace_id] = @workspace.id
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: t("workspaces.not_found")
  end

  # Stamps `memberships.last_accessed_at = NOW` for the (current user,
  # current workspace) pair on every workspace-scoped request. Powers the
  # "most-recently-accessed" sort + pinned-current row on workspaces#index.
  #
  # Single UPDATE per request — no callback cascade, no validations, no
  # broadcasts. Silently swallows failures via Rails.error.report so a
  # connection blip on the touch doesn't 500 the user's page. Same posture
  # as NotificationBroadcaster#safe_broadcast (lib/notification_broadcaster.rb).
  def touch_membership_last_accessed
    return unless Current.user && Current.workspace

    Membership
      .where(user_id: Current.user.id, workspace_id: Current.workspace.id, discarded_at: nil)
      .update_all(last_accessed_at: Time.current)
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { touch_membership_for_user: Current.user&.id })
  end
end
```

- [x] **Step 4: Re-run the concern spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/controllers/concerns/workspace_scoped_spec.rb
```

Expected: PASS (3 examples).

- [x] **Step 5: Add the system-level integration spec.** Create `spec/system/workspaces/membership_touch_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Membership last_accessed_at touch", type: :system, js: true do
  let(:user) { create(:user) }
  let(:workspace_a) { create(:workspace, name: "Alpha") }
  let(:workspace_b) { create(:workspace, name: "Beta") }
  let!(:membership_a) { create(:membership, :owner, user: user, workspace: workspace_a) }
  let!(:membership_b) { create(:membership, :owner, user: user, workspace: workspace_b) }

  before do
    sign_in_via_form(user)
  end

  it "touches the membership on every workspace-scoped page visit" do
    expect(membership_a.last_accessed_at).to be_nil
    expect(membership_b.last_accessed_at).to be_nil

    visit workspace_path(workspace_a)
    expect(membership_a.reload.last_accessed_at).to be_within(5.seconds).of(Time.current)
    expect(membership_b.reload.last_accessed_at).to be_nil

    a_at_first_visit = membership_a.last_accessed_at
    travel 2.seconds

    visit workspace_path(workspace_b)
    expect(membership_a.reload.last_accessed_at).to eq(a_at_first_visit)
    expect(membership_b.reload.last_accessed_at).to be_within(5.seconds).of(Time.current)
  end
end
```

- [x] **Step 6: Run the integration spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/workspaces/membership_touch_spec.rb
```

Expected: PASS (1 example).

- [x] **Step 7: Full suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1916 / 0 / 0** (1910 + 2 from Task 1 + 4 new from Task 2).

- [x] **Step 8: Commit.**

```bash
git add app/controllers/concerns/workspace_scoped.rb spec/controllers/concerns/workspace_scoped_spec.rb spec/system/workspaces/membership_touch_spec.rb
git commit -m "feat(controllers): touch membership last_accessed_at per request (Path AA Task 2)

Adds before_action :touch_membership_last_accessed to the
WorkspaceScoped concern. Single UPDATE per workspace-scoped request,
silently rescued (Rails.error.report) so a connection blip on the
touch doesn't 500 the user's page. Same fail-soft posture as
NotificationBroadcaster#safe_broadcast.

Concern spec covers the three branches: touches when both Current
attributes are set, no-op on discarded membership, swallows failures.
Integration spec confirms cross-workspace touches don't bleed
(visiting Beta doesn't move Alpha's timestamp).

Suite: 1912 → 1916 / 0 / 0."
```

---

## Task 3: Locale keys — row labels + leave flash messages

**Files:**
- Modify: `config/locales/en/workspaces.en.yml`
- Test: smoke check via `bundle exec rails runner`

- [ ] **Step 1: Edit `config/locales/en/workspaces.en.yml`.** Find the existing `index:` block and the `members.destroy:` block. Add the new keys:

In the `workspaces.index` block, add a `row:` sub-block AND extend with section labels:

```yaml
    index:
      title: "Your workspaces"
      new_workspace: "New workspace"
      empty: "You don't have any workspaces yet."
      current_badge: "Current"
      other_workspaces_heading: "Other workspaces"
      create_workspace_cta: "Create workspace"
      row:
        switch: "Switch"
        leave: "Leave"
        leave_confirm: "Leave %{workspace}? You'll lose access to its projects and members. This can be reversed only by being re-invited."
        member:
          one: "1 member"
          other: "%{count} members"
        last_accessed:
          touched: "Last accessed %{relative} ago"
          never: "Never accessed"
        role:
          owner: "Owner"
          admin: "Admin"
          member: "Member"
```

In the `workspaces.members.destroy` block (currently has `deactivated` + `cannot_deactivate_last_owner`), add:

```yaml
      destroy:
        deactivated: "Member deactivated."
        cannot_deactivate_last_owner: "Cannot deactivate the last owner."
        left: "You left %{workspace}."
        cannot_leave_last_owner: "You can't leave — you're the last owner. Transfer ownership first."
        cannot_leave_personal: "You can't leave your personal workspace."
```

- [ ] **Step 2: Smoke check that all new keys resolve.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails runner '
keys = %w[
  workspaces.index.current_badge
  workspaces.index.other_workspaces_heading
  workspaces.index.create_workspace_cta
  workspaces.index.row.switch
  workspaces.index.row.leave
  workspaces.index.row.last_accessed.never
  workspaces.index.row.role.owner
  workspaces.index.row.role.admin
  workspaces.index.row.role.member
  workspaces.members.destroy.left
  workspaces.members.destroy.cannot_leave_last_owner
  workspaces.members.destroy.cannot_leave_personal
]
keys.each { |k| puts "#{k}: #{I18n.t(k, raise: true)}" }
puts "---"
puts "Pluralized:"
puts I18n.t("workspaces.index.row.member", count: 1)
puts I18n.t("workspaces.index.row.member", count: 5)
puts I18n.t("workspaces.index.row.last_accessed.touched", relative: "2 minutes ago")
puts I18n.t("workspaces.index.row.leave_confirm", workspace: "Acme")
'
```

Expected: every key prints its localized string. Pluralized member count returns "1 member" / "5 members". Interpolations return correctly.

- [ ] **Step 3: Run full suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1916 / 0 / 0** (no behavior change — only new keys; existing keys untouched).

- [ ] **Step 4: Commit.**

```bash
git add config/locales/en/workspaces.en.yml
git commit -m "feat(i18n): locale keys for strong workspaces index (Path AA Task 3)

New keys under workspaces.index.* and workspaces.members.destroy.*:

- workspaces.index.{current_badge, other_workspaces_heading,
  create_workspace_cta}
- workspaces.index.row.{switch, leave, leave_confirm}
- workspaces.index.row.member.{one, other} (pluralized)
- workspaces.index.row.last_accessed.{touched, never}
- workspaces.index.row.role.{owner, admin, member}
- workspaces.members.destroy.{left, cannot_leave_last_owner,
  cannot_leave_personal}

Lands ahead of the view rewrite (Task 7) and request-spec (Task 5)
so flash assertions and view assertions reference resolved keys.

Suite: 1916 / 0 / 0 (no behavior change)."
```

---

## Task 4: MembershipPolicy amendment + policy spec

**Files:**
- Modify: `app/policies/membership_policy.rb`
- Test: `spec/policies/membership_policy_spec.rb` (create or extend)

- [x] **Step 1: Failing policy spec.** Create or extend `spec/policies/membership_policy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MembershipPolicy do
  subject(:policy) { described_class.new(actor, record) }

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:workspace) { create(:workspace) }

  describe "#destroy? — admin deactivates someone else (existing case)" do
    let(:actor) { user }
    let!(:admin_membership) { create(:membership, :admin, user: user, workspace: workspace) }
    let(:record) { create(:membership, user: other_user, workspace: workspace) }

    it "permits admin to deactivate another member" do
      expect(policy.destroy?).to be(true)
    end

    it "denies when the workspace is discarded" do
      workspace.discard!
      record.reload
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#destroy? — user leaves own membership" do
    let(:actor) { user }
    let(:record) { create(:membership, user: user, workspace: workspace) }
    let!(:owner_membership_other) { create(:membership, :owner, user: other_user, workspace: workspace) }

    it "permits leaving when not last owner and not personal workspace" do
      expect(policy.destroy?).to be(true)
    end

    it "denies leaving the user's personal workspace" do
      user.update!(personal_workspace_id: workspace.id)
      expect(policy.destroy?).to be(false)
    end

    it "denies leaving when the user is the last owner" do
      owner_membership_other.discard!  # leaves user as sole owner... but only if user IS an owner here
      record.update!(role: Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" })
      expect(policy.destroy?).to be(false)
    end

    it "denies when the workspace is discarded" do
      workspace.discard!
      record.reload
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#destroy? — non-member" do
    let(:actor) { create(:user) }  # different user, no membership
    let(:record) { create(:membership, user: user, workspace: workspace) }

    it "denies non-members" do
      expect(policy.destroy?).to be(false)
    end
  end
end
```

- [x] **Step 2: Run the spec to verify it fails.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/policies/membership_policy_spec.rb
```

Expected: FAILS — the current policy is `can?("manage_members") && record.user != user`, which explicitly excludes self-leave.

- [x] **Step 3: Amend `app/policies/membership_policy.rb`.** Replace the current `destroy?` (line 10-12) with:

```ruby
  def destroy?
    return false if record.workspace.discarded?

    if record.user == user
      # Self-leave case: user deactivating their own membership.
      return false if record.workspace.id == user.personal_workspace_id
      return false if record.role.slug == "owner" && record.workspace.owners.size == 1
      true
    else
      # Admin-deactivates-someone-else case (the rule prior to Path AA).
      can?("manage_members")
    end
  end
```

The whole file now reads:

```ruby
class MembershipPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def update?
    can?("manage_members")
  end

  def destroy?
    return false if record.workspace.discarded?

    if record.user == user
      # Self-leave case: user deactivating their own membership.
      return false if record.workspace.id == user.personal_workspace_id
      return false if record.role.slug == "owner" && record.workspace.owners.size == 1
      true
    else
      # Admin-deactivates-someone-else case (the rule prior to Path AA).
      can?("manage_members")
    end
  end

  def reactivate?
    can?("manage_members")
  end

  def transfer_ownership?
    can?("manage_workspace")
  end
end
```

- [x] **Step 4: Re-run policy spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/policies/membership_policy_spec.rb
```

Expected: PASS (7 examples).

- [x] **Step 5: Full suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1923 / 0 / 0** (1916 + 7 new policy examples).

- [x] **Step 6: Commit.**

```bash
git add app/policies/membership_policy.rb spec/policies/membership_policy_spec.rb
git commit -m "feat(policies): MembershipPolicy#destroy? permits self-leave (Path AA Task 4)

Amends destroy? to handle two distinct flows:

- record.user == user (self-leave) is now PERMITTED, under two guards:
  - cannot leave personal workspace (workspace.id != user.personal_workspace_id)
  - cannot leave as last owner (deferred to model-layer safety net too)
- record.user != user (admin-deactivates-other) keeps the prior rule
  (can?(\"manage_members\")).

Personal-workspace guard preserves the 'every user has a personal
workspace' invariant the rest of the codebase assumes. Last-owner
guard makes the UI honest — we hide the Leave button when leaving
is genuinely impossible rather than producing a 422 on submit.
Membership#deactivate! remains the model-level safety net.

Suite: 1916 → 1923 / 0 / 0."
```

---

## Task 5: MembersController#destroy redirect-by-case + request spec

**Files:**
- Modify: `app/controllers/workspaces/members_controller.rb` (the `destroy` action only)
- Test: `spec/requests/workspaces/members_spec.rb` (create or extend)

- [ ] **Step 1: Failing request spec.** Create or extend `spec/requests/workspaces/members_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Workspaces::Members destroy", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }

  before { sign_in_via_form(user) }

  describe "DELETE /workspaces/:slug/members/:id" do
    context "user leaving their own (non-personal) membership" do
      let!(:user_membership) { create(:membership, user: user, workspace: workspace) }
      let!(:owner_membership) { create(:membership, :owner, user: other_user, workspace: workspace) }

      it "deactivates the membership and redirects to /workspaces with the 'left' flash" do
        delete workspace_member_path(workspace, user_membership)
        expect(response).to redirect_to(workspaces_path)
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("workspaces.members.destroy.left", workspace: workspace.name))
        expect(user_membership.reload.discarded_at).to be_present
      end
    end

    context "user trying to leave their personal workspace" do
      let!(:personal_membership) { create(:membership, :owner, user: user, workspace: workspace) }
      before { user.update!(personal_workspace_id: workspace.id) }

      it "is forbidden by the policy" do
        delete workspace_member_path(workspace, personal_membership)
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(personal_membership.reload.discarded_at).to be_nil
      end
    end

    context "user trying to leave as the last owner" do
      let!(:user_owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }
      # No other owners exist.

      it "is forbidden and the membership remains kept" do
        delete workspace_member_path(workspace, user_owner_membership)
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(user_owner_membership.reload.discarded_at).to be_nil
      end
    end

    context "admin deactivating another member (existing case)" do
      let!(:admin_membership) { create(:membership, :admin, user: user, workspace: workspace) }
      let!(:other_membership) { create(:membership, user: other_user, workspace: workspace) }
      let!(:other_owner) { create(:membership, :owner, user: create(:user), workspace: workspace) }

      it "deactivates and redirects to the members table (unchanged behavior)" do
        delete workspace_member_path(workspace, other_membership)
        expect(response).to redirect_to(workspace_members_path(workspace))
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("workspaces.members.destroy.deactivated"))
        expect(other_membership.reload.discarded_at).to be_present
      end
    end

    context "non-member tries to delete someone else's membership" do
      let!(:stranger) { user }  # the signed-in user has no membership in workspace
      let!(:target_membership) { create(:membership, user: other_user, workspace: workspace) }

      it "is forbidden" do
        delete workspace_member_path(workspace, target_membership)
        expect(response).to have_http_status(:redirect)  # set_workspace redirects to /workspaces on RecordNotFound
      end
    end
  end
end
```

- [ ] **Step 2: Run the request spec to verify it fails.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/requests/workspaces/members_spec.rb
```

Expected: FAILS — the "leaving" case currently redirects to `workspace_members_path` not `workspaces_path`, and the policy hasn't been adjusted yet (Task 4 handles policy; this task handles controller branching).

- [ ] **Step 3: Amend the `destroy` action.** Replace `app/controllers/workspaces/members_controller.rb`'s `destroy` method (lines 41-48 of the current file) with:

```ruby
    def destroy
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership

      leaving = @membership.user == Current.user

      @membership.deactivate!

      if leaving
        redirect_to workspaces_path,
                    notice: t("workspaces.members.destroy.left", workspace: @workspace.name)
      else
        redirect_to workspace_members_path(@workspace),
                    notice: t(".deactivated")
      end
    rescue ActiveRecord::RecordInvalid
      if @membership&.user == Current.user
        redirect_to workspaces_path,
                    alert: t("workspaces.members.destroy.cannot_leave_last_owner")
      else
        redirect_to workspace_members_path(@workspace),
                    alert: t(".cannot_deactivate_last_owner")
      end
    end
```

The two-branch redirect keeps existing admin-deactivate behavior identical while routing self-leave back to the workspaces index where the user came from.

- [ ] **Step 4: Re-run request spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/requests/workspaces/members_spec.rb
```

Expected: PASS (5 examples).

- [ ] **Step 5: Full suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1928 / 0 / 0** (1923 + 5 new request examples). Verify no existing Members-controller specs broke from the redirect change.

- [ ] **Step 6: Commit.**

```bash
git add app/controllers/workspaces/members_controller.rb spec/requests/workspaces/members_spec.rb
git commit -m "feat(controllers): self-leave redirect branch on Members#destroy (Path AA Task 5)

Amends Workspaces::MembersController#destroy to branch on whether the
membership being deactivated is the current user's own:

- Self-leave: redirect to /workspaces with workspaces.members.destroy.left flash
- Admin-deactivate (existing): redirect to /workspaces/:slug/members with the
  prior workspaces.members.destroy.deactivated flash

Same branching applies to the ActiveRecord::RecordInvalid rescue (last-owner
protection) — self-leave attempts route to /workspaces with the
cannot_leave_last_owner alert; admin-deactivate attempts retain the prior
cannot_deactivate_last_owner alert.

Reuses the existing route + controller + Membership#deactivate! — no new
route required. The policy amendment from Task 4 is what unlocks self-leave;
this task handles the post-action redirect UX.

Suite: 1923 → 1928 / 0 / 0."
```

---

## Task 6: WorkspacesController#index query rewrite (controller + minimal view scaffold)

**Files:**
- Modify: `app/controllers/workspaces_controller.rb` (the `index` action only)
- Modify: `app/views/workspaces/index.html.erb` (minimal scaffold; full rewrite in Task 7)
- Test: `spec/system/workspaces/index_spec.rb` (create — replaces any existing)

- [ ] **Step 1: Failing system spec — page-renders + pinned section structure.** Create `spec/system/workspaces/index_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Strong workspaces index", type: :system, js: true do
  let(:user) { create(:user, first_name: "Dave", last_name: "Hancock") }
  let(:current_workspace) { create(:workspace, name: "Recent") }
  let(:older_workspace) { create(:workspace, name: "Older") }

  let!(:current_membership) {
    create(:membership, :owner, user: user, workspace: current_workspace,
                                last_accessed_at: 2.minutes.ago)
  }
  let!(:older_membership) {
    create(:membership, user: user, workspace: older_workspace,
                        last_accessed_at: 3.days.ago)
  }
  # Seed a co-owner for current_workspace so user can leave it in later examples.
  let!(:co_owner) {
    other = create(:user)
    create(:membership, :owner, user: other, workspace: current_workspace)
  }

  before { sign_in_via_form(user) }

  describe "page structure" do
    it "renders the page title and the New workspace CTA" do
      visit workspaces_path
      expect(page).to have_selector("h1", text: I18n.t("workspaces.index.title"))
      expect(page).to have_link(I18n.t("workspaces.index.new_workspace"))
    end

    it "pins the most-recently-accessed workspace at the top with a CURRENT badge" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_text("Recent")
        expect(page).to have_text(I18n.t("workspaces.index.current_badge"))
      end
    end

    it "renders an 'Other workspaces' heading and the older workspace below" do
      visit workspaces_path
      expect(page).to have_text(I18n.t("workspaces.index.other_workspaces_heading"))
      others_section = page.find("[data-test='other-workspaces-list']")
      within(others_section) do
        expect(page).to have_text("Older")
      end
    end
  end
end
```

- [ ] **Step 2: Run to confirm it fails.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/workspaces/index_spec.rb
```

Expected: FAILS — the existing view doesn't have `[data-test='current-workspace-row']` or `[data-test='other-workspaces-list']` selectors.

- [ ] **Step 3: Rewrite the controller's `index` action.** Modify `app/controllers/workspaces_controller.rb`. Replace the `index` action (lines 8-12) with:

```ruby
  def index
    authorize Workspace

    scope = Current.user.memberships.kept
              .joins(:workspace)
              .merge(Workspace.kept)
              .includes(workspace: [ :logo_attachment, memberships: [ :role, { user: :avatar_attachment } ] ])
              .order(Arel.sql("memberships.last_accessed_at DESC NULLS LAST, workspaces.name ASC"))

    @memberships = scope.to_a
    @current_membership = @memberships.first
    @other_memberships = @memberships.drop(1)
  end
```

`@memberships` keeps the full list for cases where the view needs to count (e.g., to suppress the "Other workspaces" heading for single-membership users). `@current_membership` and `@other_memberships` are the split.

- [ ] **Step 4: Scaffold the view to make the system spec pass.** Replace `app/views/workspaces/index.html.erb` with a minimal version that has the data-test hooks (full styling lands in Task 7):

```erb
<% content_for(:title) { t("workspaces.index.title") } %>
<div class="max-w-4xl mx-auto px-4 py-16">
  <div class="flex items-center justify-between">
    <h1 class="text-3xl font-bold text-text-heading">
      <%= t("workspaces.index.title") %>
    </h1>
    <%= link_to t("workspaces.index.new_workspace"), new_workspace_path, class: "btn-primary" %>
  </div>

  <% if @current_membership.present? %>
    <section class="mt-8" data-test="current-workspace-row">
      <div class="flex items-center gap-3 p-4 border border-border rounded-lg">
        <%= workspace_icon_for(@current_membership.workspace, size: :md) %>
        <div class="flex-1">
          <p class="font-medium text-text-heading"><%= @current_membership.workspace.name %></p>
        </div>
        <span class="text-xs font-semibold uppercase tracking-wider px-2 py-1 rounded bg-interactive text-text-on-interactive">
          <%= t("workspaces.index.current_badge") %>
        </span>
      </div>
    </section>
  <% end %>

  <% if @other_memberships.any? %>
    <section class="mt-8">
      <h2 class="text-xs font-semibold uppercase tracking-wider text-text-muted mb-3">
        <%= t("workspaces.index.other_workspaces_heading") %>
      </h2>
      <ul class="flex flex-col gap-2" data-test="other-workspaces-list">
        <% @other_memberships.each do |membership| %>
          <li class="flex items-center gap-3 p-4 border border-border rounded-lg">
            <%= workspace_icon_for(membership.workspace, size: :md) %>
            <div class="flex-1">
              <p class="font-medium text-text-heading"><%= membership.workspace.name %></p>
            </div>
          </li>
        <% end %>
      </ul>
    </section>
  <% end %>

  <% if @memberships.empty? %>
    <div class="mt-8">
      <%= render "shared/empty_state",
            message: t("workspaces.index.empty"),
            action_text: t("workspaces.index.new_workspace"),
            action_url: new_workspace_path %>
    </div>
  <% end %>
</div>
```

This is intentionally minimal — full row metadata, Leave button, responsive layout, and partial extraction land in Task 7.

- [ ] **Step 5: Re-run system spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/workspaces/index_spec.rb
```

Expected: PASS (3 examples).

- [ ] **Step 6: Full suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1931 / 0 / 0** (1928 + 3 new system examples).

Verify no existing workspaces-index spec broke (the old `index_spec` is being replaced — if it exists at a different path, ensure both don't coexist by checking `find spec -name "index_spec*" -path "*workspaces*"`).

- [ ] **Step 7: Commit.**

```bash
git add app/controllers/workspaces_controller.rb app/views/workspaces/index.html.erb spec/system/workspaces/index_spec.rb
git commit -m "feat(views): workspaces#index pinned-current + others split (Path AA Task 6)

Controller rewrite: switches the @workspaces flat list for a sorted
membership-driven scope using
ORDER BY memberships.last_accessed_at DESC NULLS LAST, workspaces.name ASC.
Splits into @current_membership (first row) + @other_memberships (rest).

Minimal view scaffold renders the pinned current row with CURRENT badge
and the 'Other workspaces' section below. Row metadata, Leave button,
and partial extraction land in Task 7 — this commit just gets the
two-section structure in place so the system spec can pin the
'current = most-recently-accessed' semantics.

Suite: 1928 → 1931 / 0 / 0."
```

---

## Task 7: Full view rewrite — `_row.html.erb`, `_leave_button.html.erb`, single-membership branch

**Files:**
- Create: `app/views/workspaces/_row.html.erb`
- Create: `app/views/workspaces/_leave_button.html.erb`
- Modify: `app/views/workspaces/index.html.erb` (use new partials)
- Test: `spec/system/workspaces/index_spec.rb` (add metadata + leave + single-membership coverage)

- [ ] **Step 1: Extend the failing system spec with metadata + leave + single-membership cases.** Append to `spec/system/workspaces/index_spec.rb` (inside the top-level describe):

```ruby
  describe "row metadata" do
    it "shows plan, role, member count, and last-accessed text per row" do
      visit workspaces_path

      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_text(I18n.t("workspaces.plans.free"))
        expect(page).to have_text(I18n.t("workspaces.index.row.role.owner"))
        expect(page).to have_text(I18n.t("workspaces.index.row.member", count: 2))
        # "Last accessed 2 minutes ago" — use a partial substring to avoid
        # locale/clock fragility.
        expect(page).to have_text(/Last accessed/)
      end

      others = page.find("[data-test='other-workspaces-list']")
      within(others) do
        expect(page).to have_text(I18n.t("workspaces.index.row.role.member"))
      end
    end

    it "shows 'Never accessed' for memberships with nil last_accessed_at" do
      never_workspace = create(:workspace, name: "Never visited")
      create(:membership, user: user, workspace: never_workspace, last_accessed_at: nil)
      visit workspaces_path
      expect(page).to have_text(I18n.t("workspaces.index.row.last_accessed.never"))
    end
  end

  describe "Switch action" do
    it "navigates to the workspace overview when the row is clicked" do
      visit workspaces_path
      within(page.find("[data-test='other-workspaces-list']")) do
        click_link "Older"
      end
      expect(page).to have_current_path(workspace_path(older_workspace))
    end

    it "renders a Switch button on every row (including the pinned current)" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_link(I18n.t("workspaces.index.row.switch"))
      end
      others = page.find("[data-test='other-workspaces-list']")
      within(others) do
        expect(page).to have_link(I18n.t("workspaces.index.row.switch"))
      end
    end
  end

  describe "Leave action" do
    it "does NOT render a Leave button on the pinned current row" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_no_button(I18n.t("workspaces.index.row.leave"))
      end
    end

    it "renders Leave on non-current rows where policy permits" do
      visit workspaces_path
      others = page.find("[data-test='other-workspaces-list']")
      within(others) do
        expect(page).to have_button(I18n.t("workspaces.index.row.leave"))
      end
    end

    it "does NOT render Leave on the personal workspace" do
      personal = create(:workspace, name: "Personal")
      create(:membership, :owner, user: user, workspace: personal, last_accessed_at: 1.year.ago)
      user.update!(personal_workspace_id: personal.id)
      visit workspaces_path

      # Find the row for Personal in either pinned or others.
      personal_row = page.all("li, [data-test='current-workspace-row']")
                          .find { |el| el.text.include?("Personal") }
      within(personal_row) do
        expect(page).to have_no_button(I18n.t("workspaces.index.row.leave"))
      end
    end

    it "removes the row after a successful leave" do
      visit workspaces_path
      others = page.find("[data-test='other-workspaces-list']")

      # Click Leave on the Older workspace. Confirm pattern uses turbo confirm.
      within(others) do
        accept_confirm do
          click_button I18n.t("workspaces.index.row.leave")
        end
      end

      expect(page).to have_current_path(workspaces_path)
      expect(page).to have_text(I18n.t("workspaces.members.destroy.left", workspace: "Older"))
      expect(page).to have_no_text("Older")
    end
  end

  describe "single-membership user" do
    it "does NOT render the 'Other workspaces' heading when only one membership exists" do
      single_user = create(:user)
      only_workspace = create(:workspace, name: "Only One")
      create(:membership, :owner, user: single_user, workspace: only_workspace, last_accessed_at: 1.minute.ago)
      sign_out_via_user_menu  # helper assumed; otherwise manual click_button workflow
      sign_in_via_form(single_user)

      visit workspaces_path

      expect(page).to have_text("Only One")
      expect(page).to have_no_text(I18n.t("workspaces.index.other_workspaces_heading"))
    end
  end
```

- [ ] **Step 2: Run to confirm new examples fail.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/workspaces/index_spec.rb
```

Expected: 3 prior passing + ~9 failing (metadata, Switch buttons, Leave behaviors, single-membership branch).

- [ ] **Step 3: Create `app/views/workspaces/_row.html.erb`.**

```erb
<%# locals: (membership:, current: false) -%>
<%# Single workspace row partial used by both the pinned-current section
    and the "Other workspaces" list. `current: true` suppresses the Leave
    button (the user must navigate INTO the workspace to leave it) and
    adds the CURRENT badge. Whole-row click implemented via the absolute
    overlay link pattern — the link covers the row, action buttons sit
    above it with `relative z-10` so they intercept clicks first. JS-free. -%>
<%
  workspace = membership.workspace
  user_role = membership.role
  member_count = workspace.memberships.kept.size
  is_personal = membership.user.personal_workspace_id == workspace.id
%>

<li class="relative flex flex-col md:flex-row md:items-center gap-3 p-4 rounded-lg border border-border
           hover:border-interactive
           focus-within:ring-2 focus-within:ring-interactive-focus">
  <%= link_to workspace_path(workspace),
        "aria-label": t("workspaces.index.row.switch"),
        class: "absolute inset-0 z-0 rounded-lg
                focus:outline-none" do %><% end %>

  <%# Icon %>
  <div class="relative z-10 shrink-0">
    <%= workspace_icon_for(workspace, size: :md) %>
  </div>

  <%# Identity + metadata %>
  <div class="relative z-10 flex-1 min-w-0">
    <div class="flex items-center gap-2">
      <p class="font-medium text-text-heading truncate" title="<%= workspace.name %>">
        <%= workspace.name %>
      </p>
      <% if current %>
        <span class="text-xs font-semibold uppercase tracking-wider px-2 py-0.5 rounded
                     bg-interactive text-text-on-interactive">
          <%= t("workspaces.index.current_badge") %>
        </span>
      <% end %>
    </div>
    <p class="mt-1 text-sm text-text-muted">
      <%= t("workspaces.plans.#{workspace.plan}", default: workspace.plan.titleize) %>
      &middot;
      <%= t("workspaces.index.row.role.#{user_role.slug}", default: user_role.name) %>
      &middot;
      <%= t("workspaces.index.row.member", count: member_count) %>
    </p>
    <p class="mt-1 text-xs text-text-muted">
      <% if membership.last_accessed_at.present? %>
        <%= t("workspaces.index.row.last_accessed.touched",
               relative: time_ago_in_words(membership.last_accessed_at)) %>
      <% else %>
        <%= t("workspaces.index.row.last_accessed.never") %>
      <% end %>
    </p>
  </div>

  <%# Action buttons (relative + z-10 so they intercept clicks ahead of the overlay link). %>
  <div class="relative z-10 flex items-center gap-2 mt-2 md:mt-0">
    <%= link_to t("workspaces.index.row.switch"), workspace_path(workspace),
          class: "btn-touch-target inline-flex items-center px-3 py-2 rounded-md
                  text-sm font-medium text-text-body
                  bg-surface-raised border border-border
                  hover:bg-surface-sunken hover:text-interactive
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus" %>
    <% if !current && !is_personal %>
      <%= render "workspaces/leave_button", membership: membership %>
    <% end %>
  </div>
</li>
```

Note on the time-ago rendering: `time_ago_in_words(2.minutes.ago)` returns "2 minutes" (no "ago" suffix). The "ago" lives in the locale key itself (`"Last accessed %{relative} ago"`) so it's translatable as part of the sentence. Single `t()` call, single i18n unit. Spec assertion uses `/Last accessed/` regex to avoid clock fragility.

- [ ] **Step 4: Create `app/views/workspaces/_leave_button.html.erb`.**

```erb
<%# locals: (membership:) -%>
<%# Leave button — only rendered for memberships where the current user
    is permitted to deactivate their own membership (not personal, not
    last owner). Pundit gate is enforced both in the partial render
    condition AND at the controller via authorize — do not remove the
    policy check from the controller. Uses standard turbo confirm. -%>
<% return unless policy(membership).destroy? %>
<%= button_to t("workspaces.index.row.leave"),
      workspace_member_path(membership.workspace, membership),
      method: :delete,
      data: { turbo_confirm: t("workspaces.index.row.leave_confirm", workspace: membership.workspace.name) },
      class: "btn-touch-target inline-flex items-center px-3 py-2 rounded-md
              text-sm font-medium text-text-body
              bg-surface-raised border border-border
              hover:bg-surface-sunken hover:text-interactive
              focus:outline-none focus:ring-2 focus:ring-interactive-focus
              cursor-pointer" %>
```

- [ ] **Step 5: Rewrite `app/views/workspaces/index.html.erb` to use the new partials.**

```erb
<% content_for(:title) { t("workspaces.index.title") } %>
<div class="max-w-4xl mx-auto px-4 py-16">
  <div class="flex items-center justify-between">
    <h1 class="text-3xl font-bold text-text-heading">
      <%= t("workspaces.index.title") %>
    </h1>
    <%= link_to t("workspaces.index.new_workspace"), new_workspace_path,
          class: "btn-touch-target inline-flex items-center px-4 py-2 rounded-md
                  bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium
                  focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus" %>
  </div>

  <% if @current_membership.present? %>
    <section class="mt-8" data-test="current-workspace-row" aria-label="<%= t('workspaces.index.current_badge') %>">
      <ul class="flex flex-col gap-2">
        <%= render "workspaces/row", membership: @current_membership, current: true %>
      </ul>
    </section>
  <% end %>

  <% if @other_memberships.any? %>
    <section class="mt-8">
      <h2 class="text-xs font-semibold uppercase tracking-wider text-text-muted mb-3">
        <%= t("workspaces.index.other_workspaces_heading") %>
      </h2>
      <ul class="flex flex-col gap-2" data-test="other-workspaces-list">
        <% @other_memberships.each do |membership| %>
          <%= render "workspaces/row", membership: membership, current: false %>
        <% end %>
      </ul>
    </section>
  <% end %>

  <% if @memberships.empty? %>
    <div class="mt-8">
      <%= render "shared/empty_state",
            message: t("workspaces.index.empty"),
            action_text: t("workspaces.index.new_workspace"),
            action_url: new_workspace_path %>
    </div>
  <% end %>

  <div class="mt-12 text-center">
    <%= link_to t("workspaces.index.create_workspace_cta"), new_workspace_path,
          class: "btn-touch-target inline-flex items-center px-4 py-2 rounded-md
                  text-sm font-medium text-interactive
                  hover:bg-surface-sunken
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus" %>
  </div>
</div>
```

- [ ] **Step 6: Re-run system spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/workspaces/index_spec.rb
```

Expected: all examples PASS (3 + ~9).

- [ ] **Step 7: Full suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1940 / 0 / 0** (1931 + 9 new system examples).

- [ ] **Step 8: Commit.**

```bash
git add app/views/workspaces/_row.html.erb app/views/workspaces/_leave_button.html.erb app/views/workspaces/index.html.erb spec/system/workspaces/index_spec.rb
git commit -m "feat(views): row metadata + Leave button + single-membership branch (Path AA Task 7)

Extracts _row and _leave_button partials and rewrites the index view
to use them. Row carries the full Path AA metadata: plan badge, role
badge, member count (off preloaded relation), last-accessed timestamp
(or 'Never accessed').

Whole-row click via JS-free absolute-overlay-link pattern: the link
spans inset-0 with z-0, action buttons sit relative z-10 so they
intercept clicks ahead of the overlay. Keyboard focus order is
preserved (link is first tab stop).

Leave button is policy-gated (only renders when policy(membership).destroy?
permits) AND positionally gated (never on the pinned current row,
never on the user's personal workspace). Confirm via standard
turbo_confirm — no Stimulus controller needed. Server-side authorization
remains the source of truth.

Single-membership users see only the pinned section + 'Create workspace'
CTA — no 'Other workspaces' heading rendered for an empty group.

Suite: 1931 → 1940 / 0 / 0."
```

---

## Task 8: System spec rewrite — UX coverage + axe-AAA both themes

**Files:**
- Modify: `spec/system/workspaces/index_spec.rb` (append axe coverage + responsive sanity)

- [ ] **Step 1: Add axe-AAA + sort-order specs.** Append to `spec/system/workspaces/index_spec.rb`:

```ruby
  describe "sort order" do
    it "places never-visited workspaces alphabetically after touched ones" do
      a_never = create(:workspace, name: "AAA Never")
      z_never = create(:workspace, name: "ZZZ Never")
      create(:membership, user: user, workspace: a_never, last_accessed_at: nil)
      create(:membership, user: user, workspace: z_never, last_accessed_at: nil)
      visit workspaces_path

      # Order in 'Other workspaces': Older (touched 3d ago), AAA Never, ZZZ Never
      others = page.find("[data-test='other-workspaces-list']")
      names = others.all("li").map(&:text)
      expect(names.find_index { |t| t.include?("Older") }).to be < names.find_index { |t| t.include?("AAA Never") }
      expect(names.find_index { |t| t.include?("AAA Never") }).to be < names.find_index { |t| t.include?("ZZZ Never") }
    end
  end

  describe "accessibility (WCAG 2.2 AAA)" do
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    it "passes axe at default viewport in both themes" do
      visit workspaces_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations: #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "passes axe at iPhone-SE viewport in both themes (responsive sanity)" do
      page.driver.with_playwright_page do |pw_page|
        pw_page.set_viewport_size(width: 375, height: 667)
      end
      visit workspaces_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations (375x667): #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end
```

- [ ] **Step 2: Run the spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/workspaces/index_spec.rb
```

Expected: all examples PASS. If axe finds violations, fix them inline before committing — common culprits:

- Touch target size: every `<button>` and `<a>` action needs `btn-touch-target` OR `min-h-[44px]` (SC 2.5.5).
- Color contrast: `text-text-muted` should be 7:1 against the parent surface (already enforced in the design token system).
- Focus ring color: must use `interactive-focus` (cyan-700) variant.

- [ ] **Step 3: Full suite + manual a11y sanity.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1943 / 0 / 0** (1940 + 3 new examples).

- [ ] **Step 4: Commit.**

```bash
git add spec/system/workspaces/index_spec.rb
git commit -m "test(system): sort order + WCAG 2.2 AAA coverage (Path AA Task 8)

Adds three specs to spec/system/workspaces/index_spec.rb:

- Sort order with never-visited workspaces sorting alphabetically after
  touched ones (pins the 'NULLS LAST, name ASC' branch of the controller's
  ORDER BY clause).
- axe-core AAA at default desktop viewport in both light + dark themes.
- axe-core AAA at iPhone-SE viewport (375x667) in both themes — catches
  any responsive regressions where action buttons stack below metadata.

Per project memory feedback_ci_vs_local_axe.md, local axe can miss
contrast violations that CI catches; final verification still requires
CI pass post-PR.

Suite: 1940 → 1943 / 0 / 0."
```

---

## Task 9: CHANGELOG + final verification + merge

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a CHANGELOG entry under `[Unreleased]` > `### Changed`.**

Edit `CHANGELOG.md`, find the `### Changed` section under `[Unreleased]`, append:

```markdown
- Workspaces index (`/workspaces`) rewritten from a phonebook into a workbench per Jason Fried's "weak index" critique. Pinned-current row (by most-recently-accessed) with CURRENT badge; "Other workspaces" section sorted by `memberships.last_accessed_at DESC NULLS LAST, name ASC`. Each row carries plan badge, role badge, member count (from preloaded relation, no counter cache), last-accessed timestamp, Switch + Leave inline verbs (Leave gated by `MembershipPolicy#destroy?` which now permits self-leave under personal-workspace + last-owner safety guards). Adds `memberships.last_accessed_at` column + composite index, plus a `WorkspaceScoped` before_action that touches the timestamp on every workspace-scoped request (single UPDATE per request, silently rescued). Single-membership users see only the pinned section without an "Other workspaces" heading.
```

- [ ] **Step 2: Run the FULL suite one final time as the gate.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec --format progress
```

Expected: **1943 / 0 / 0**. If anything is red, stop and triage — DO NOT proceed to merge.

- [ ] **Step 3: Commit CHANGELOG.**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): Path AA strong workspaces index entry (Path AA Task 9)"
```

- [ ] **Step 4: Verify the commit graph.**

```bash
git log --oneline -12
```

Expected: 9 task commits (Task 1 through Task 9) plus the design spec commit at the base, plus prior settings-hub-spec history.

- [ ] **Step 5: Fast-forward into `docs/settings-hub-spec`.**

```bash
git checkout docs/settings-hub-spec
git merge --ff-only feat/path-aa-strong-workspaces-index
git branch -d feat/path-aa-strong-workspaces-index
git log --oneline -12
```

Expected: `--ff-only` succeeds (the feature branch is a linear descendant of `docs/settings-hub-spec`). `docs/settings-hub-spec` now points at the Task 9 CHANGELOG commit.

- [ ] **Step 6: Push to origin.** Lefthook will run the full pre-push gauntlet (brakeman + erb_lint + rspec + rubocop + tailwind_build). All must pass.

```bash
git push origin docs/settings-hub-spec
```

Expected: push succeeds. CI also re-runs against the PR (which is already open against `main`); axe-AAA on CI catches anything local axe missed.

- [ ] **Step 7: Manual cross-viewport browser verification (deferred — user task).**

`bin/dev`. Sign in. Visit `/workspaces`. Verify at:
- 375×667 (iPhone SE): pinned current row, sections collapse cleanly, Leave button stacked below metadata on mobile.
- 768×1024 (iPad portrait): boundary check at md breakpoint.
- 1280×800 (desktop): full inline layout, action buttons right-aligned.

Both themes (toggle via Appearance settings or system preference). Try Leave on a non-personal, non-last-owner workspace — confirm turbo_confirm dialog appears, accept it, verify redirect to `/workspaces` with success flash and the row removed.

---

## Verification matrix

After Task 9, verify Jason Fried's 5-criterion weak-index diagnostic flipped to all-passing:

| Criterion | Pre-AA | Post-AA verification |
| --- | --- | --- |
| Treats every row identically | ❌ | ✓ Pinned row has CURRENT badge + own section |
| No "you are here" | ❌ | ✓ Pinned row + CURRENT badge + last-accessed timestamp |
| Directory not workbench | ❌ | ✓ Switch on every row + Leave where permitted |
| Thin metadata | ⚠ | ✓ Plan + role + member count + last-accessed |
| Chrome compensating | ⚠ at threshold | ✓ Index is destination worth landing on; sidebar switcher + user-menu link both correctly defer to it |

Plus: full RSpec suite green at **1943 / 0 / 0**; GitHub Actions CI green on the PR; manual cross-viewport in both themes confirmed by user.

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| `NULLS LAST` syntax not supported by SQLite | Low | SQLite 3.30+ supports `NULLS LAST`; the project's CI + local SQLite are both modern. Verified empirically when running Task 6 — if the query raises, fall back to `ORDER BY memberships.last_accessed_at IS NULL, memberships.last_accessed_at DESC, workspaces.name ASC` (pre-3.30 idiom). |
| Existing Members controller request specs break from the new redirect branching in Task 5 | Medium | Task 5 Step 5 runs the full suite; if anything in `spec/requests/workspaces/members_spec.rb` (existing) breaks, the conditional branch needs review. Most likely: the existing admin-deactivate spec asserts on `flash[:notice]` matching `.deactivated` — that's preserved. |
| `policy(membership).destroy?` in `_leave_button.html.erb` raises if the policy class lookup fails | Low | `MembershipPolicy` exists; Pundit's view-level `policy()` helper auto-resolves from the record class. Sanity-checked in Task 4. |
| Touch UPDATE hot-path slowdown under heavy Turbo Frame traffic | Low | Single indexed UPDATE per request — sub-ms. Throttling via `session[:last_membership_touch_at]` is a 3-line addition if it ever matters. Not pre-optimized. |
| Whole-row click overlay link traps keyboard focus or breaks AT | Low | The overlay link has `aria-label="Switch"`; the buttons that sit above it are properly tab-ordered. The system spec covers this — if the Switch link doesn't navigate from inside the others list, axe + keyboard tests will catch. |
| Pundit `record.workspace.owners.size == 1` triggers a query inside the policy check (called per row in the view) | Medium | The index controller eager-loads `memberships: [:role, ...]`, so `record.workspace.owners` reads off the preloaded relation. Verify in dev console with `Bullet` running — fix with `.includes(workspace: { memberships: :role })` if a per-row query surfaces. |

---

## Rollback strategy

Each task is its own commit, atomic and revertable. If anything breaks post-merge:

- **Pre-push, mid-task:** abandon the feature branch (`git checkout docs/settings-hub-spec && git branch -D feat/path-aa-strong-workspaces-index`).
- **Post-merge to `docs/settings-hub-spec`:** revert commits in reverse task order. The migration (Task 1) is the only schema change; `bundle exec rails db:rollback` reverses it.
- **Post-merge to `main`:** standard revert flow. Migration rollback may require a follow-up migration to `remove_column` cleanly.

---

## Out of scope (re-stated)

- Inline rename
- Set-as-default workspace
- Search / filter (until N≥7 in real usage)
- Sign-in redirect to a workspace
- Counter cache for `memberships_count`
- Transfer-ownership UI changes
- Avatar trigger chevron (separate deferred item)
- Identity-picker herb-lint warnings (separate pre-existing tech debt)
- Workspace-branded color header banner (deferred per user)
