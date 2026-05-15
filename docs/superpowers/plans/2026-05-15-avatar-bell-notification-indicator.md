# Avatar-Overlaid Notification Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the standalone header notifications bell + dropdown with a small solid-bell glyph overlaid on the user avatar, where bell color reflects the highest-severity unread notification. The standalone dropdown panel + its Stimulus controller are deleted; `/account/notifications` becomes the only path to the full list.

**Architecture:** Severity becomes a per-notifier class-attribute (`severity :danger`) declared alongside the existing `category`. A new helper resolves unread state from a single grouped query on `User`. The bell overlay is a slim turbo-frame inside the avatar `<button>`. The Turbo broadcast trio grows to a quartet (avatar button frame + bell overlay frame + menu count span frame + aria-live region) so the avatar's `aria-label` stays fresh under live updates.

**Tech Stack:** Rails 8.1, Ruby 3.3+, Noticed gem v2, Turbo (Hotwire), TailwindCSS 4 with OKLCH semantic tokens, RSpec, Capybara/Playwright.

**Source spec:** [docs/superpowers/specs/2026-05-15-avatar-bell-notification-indicator-design.md](../specs/2026-05-15-avatar-bell-notification-indicator-design.md)

---

## Pre-flight checklist (do this first, no commit needed)

- [ ] **Verify branch state.** Confirm you're on a fresh feature branch off `main`:

```bash
git checkout -b feat/avatar-bell-indicator
git status  # expect: clean working tree
```

- [ ] **Verify suite is green before changes.** Memory rule: always run full suite before committing. Establish baseline now:

```bash
bundle exec rspec
```

Expected: 0 failures. If anything fails, do NOT proceed — fix `main` first.

- [ ] **Skim the spec.** Open the spec linked above. The "Severity assignments per concrete notifier" table is your reference for Task 2; the "Severity → color tokens" table is for Tasks 4 and 8.

---

## Task 1: Add `severity` DSL to `ApplicationNotifier`

**Files:**
- Modify: `app/notifiers/application_notifier.rb`
- Modify (test): `spec/notifiers/application_notifier_spec.rb`

- [ ] **Step 1: Write the failing test for the DSL.**

In `spec/notifiers/application_notifier_spec.rb`, add inside the existing top-level describe block:

```ruby
describe ".severity" do
  it "defaults to :info when not declared" do
    klass = Class.new(ApplicationNotifier)
    expect(klass.severity_name).to eq(:info)
  end

  it "stores the declared severity as a symbol" do
    klass = Class.new(ApplicationNotifier) do
      severity :danger
    end
    expect(klass.severity_name).to eq(:danger)
  end

  it "accepts string arguments and stores as symbol" do
    klass = Class.new(ApplicationNotifier) do
      severity "warning"
    end
    expect(klass.severity_name).to eq(:warning)
  end

  it "does not leak between subclasses" do
    a = Class.new(ApplicationNotifier) { severity :danger }
    b = Class.new(ApplicationNotifier) { severity :success }
    expect(a.severity_name).to eq(:danger)
    expect(b.severity_name).to eq(:success)
  end
end
```

- [ ] **Step 2: Run test to verify it fails.**

```bash
bundle exec rspec spec/notifiers/application_notifier_spec.rb -e "severity"
```

Expected: 4 failures with `NoMethodError: undefined method 'severity_name'` or `'severity'` on the class.

- [ ] **Step 3: Add the DSL.**

In `app/notifiers/application_notifier.rb`, add immediately below the existing `class_attribute :category_name, instance_accessor: false` line:

```ruby
class_attribute :severity_name, instance_accessor: false, default: :info
```

And add this class method directly below the existing `def self.category(name)`:

```ruby
def self.severity(name)
  self.severity_name = name.to_sym
end
```

- [ ] **Step 4: Run test to verify it passes.**

```bash
bundle exec rspec spec/notifiers/application_notifier_spec.rb -e "severity"
```

Expected: 4 passing.

- [ ] **Step 5: Run full suite to confirm no regressions.**

```bash
bundle exec rspec
```

Expected: 0 failures (Lefthook pre-push will also enforce this later).

- [ ] **Step 6: Commit.**

```bash
git add app/notifiers/application_notifier.rb spec/notifiers/application_notifier_spec.rb
git commit -m "feat(notifications): add severity DSL to ApplicationNotifier"
```

---

## Task 2: Declare severity on all 11 concrete notifiers

**Files (modified, one line each):**
- `app/notifiers/password_changed_notifier.rb`
- `app/notifiers/sign_in_from_new_device_notifier.rb`
- `app/notifiers/workspace_capacity_approaching_notifier.rb`
- `app/notifiers/workspace_invitation_expiring_soon_notifier.rb`
- `app/notifiers/workspace_invitation_received_notifier.rb`
- `app/notifiers/workspace_invitation_resent_notifier.rb`
- `app/notifiers/workspace_role_changed_notifier.rb`
- `app/notifiers/workspace_member_added_notifier.rb`
- `app/notifiers/workspace_invitation_accepted_notifier.rb`
- `app/notifiers/workspace_invitation_declined_notifier.rb`
- `app/notifiers/project_membership_changed_notifier.rb`

**Test:** `spec/notifiers/notifier_severity_assignments_spec.rb` (new, single spec covers all 11)

- [ ] **Step 1: Write the failing test enumerating all 11 expected severities.**

Create `spec/notifiers/notifier_severity_assignments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Notifier severity assignments" do
  expected = {
    PasswordChangedNotifier              => :danger,
    SignInFromNewDeviceNotifier          => :danger,
    WorkspaceCapacityApproachingNotifier => :warning,
    WorkspaceInvitationExpiringSoonNotifier => :warning,
    WorkspaceInvitationReceivedNotifier  => :info,
    WorkspaceInvitationResentNotifier    => :info,
    WorkspaceRoleChangedNotifier         => :info,
    WorkspaceMemberAddedNotifier         => :success,
    WorkspaceInvitationAcceptedNotifier  => :success,
    WorkspaceInvitationDeclinedNotifier  => :info,
    ProjectMembershipChangedNotifier     => :info
  }

  expected.each do |notifier_class, severity|
    it "#{notifier_class.name} declares severity #{severity.inspect}" do
      expect(notifier_class.severity_name).to eq(severity)
    end
  end
end
```

- [ ] **Step 2: Run test to verify all 11 fail.**

```bash
bundle exec rspec spec/notifiers/notifier_severity_assignments_spec.rb
```

Expected: 11 failures (each says got `:info` (the default) but wanted the assigned severity).

- [ ] **Step 3: Add severity declaration to each notifier.**

For each file, add the `severity` line immediately after the existing `category` line. Exact insertions:

`app/notifiers/password_changed_notifier.rb`:
```ruby
category :security
severity :danger
```

`app/notifiers/sign_in_from_new_device_notifier.rb`:
```ruby
category :security
severity :danger
```

`app/notifiers/workspace_capacity_approaching_notifier.rb`:
```ruby
category :billing
severity :warning
```

`app/notifiers/workspace_invitation_expiring_soon_notifier.rb`:
```ruby
category :account_access
severity :warning
```

`app/notifiers/workspace_invitation_received_notifier.rb`:
```ruby
category :account_access
severity :info
```

`app/notifiers/workspace_invitation_resent_notifier.rb`:
```ruby
category :account_access
severity :info
```

`app/notifiers/workspace_role_changed_notifier.rb`:
```ruby
category :account_access
severity :info
```

`app/notifiers/workspace_member_added_notifier.rb`:
```ruby
category :workspace_activity
severity :success
```

`app/notifiers/workspace_invitation_accepted_notifier.rb`:
```ruby
category :workspace_activity
severity :success
```

`app/notifiers/workspace_invitation_declined_notifier.rb`:
```ruby
category :workspace_activity
severity :info
```

`app/notifiers/project_membership_changed_notifier.rb`:
```ruby
category :project_activity
severity :info
```

- [ ] **Step 4: Run the test to verify all 11 pass.**

```bash
bundle exec rspec spec/notifiers/notifier_severity_assignments_spec.rb
```

Expected: 11 passing.

- [ ] **Step 5: Run full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 6: Commit.**

```bash
git add app/notifiers/ spec/notifiers/notifier_severity_assignments_spec.rb
git commit -m "feat(notifications): declare severity on all 11 notifiers"
```

---

## Task 3: Add `User#unread_notification_breakdown`

**Files:**
- Modify: `app/models/user.rb`
- Modify (test): `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing test.**

In `spec/models/user_spec.rb`, add a new describe block:

```ruby
describe "#unread_notification_breakdown" do
  let(:user) { create(:user) }

  it "returns an empty hash when there are no notifications" do
    expect(user.unread_notification_breakdown).to eq({})
  end

  it "returns an empty hash when all notifications are read" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    user.notifications.update_all(read_at: Time.current)
    expect(user.unread_notification_breakdown).to eq({})
  end

  it "groups unread notifications by notifier event type with counts" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    PasswordChangedNotifier.with(record: user, idempotency_key: "another").deliver(user)
    SignInFromNewDeviceNotifier.with(record: user).deliver(user)

    expect(user.unread_notification_breakdown).to eq(
      "PasswordChangedNotifier"     => 2,
      "SignInFromNewDeviceNotifier" => 1
    )
  end

  it "ignores read notifications when counting unread" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    SignInFromNewDeviceNotifier.with(record: user).deliver(user)
    user.notifications.where(type: "PasswordChangedNotifier::Notification")
        .update_all(read_at: Time.current)

    expect(user.unread_notification_breakdown).to eq(
      "SignInFromNewDeviceNotifier" => 1
    )
  end
end
```

- [ ] **Step 2: Run test to verify it fails.**

```bash
bundle exec rspec spec/models/user_spec.rb -e "unread_notification_breakdown"
```

Expected: 4 failures with `NoMethodError: undefined method 'unread_notification_breakdown'`.

- [ ] **Step 3: Implement the method.**

In `app/models/user.rb`, add this method (near other notification-related code if any; otherwise group it with public association readers):

```ruby
# Returns { notifier_class_name => unread_count, ... } for the user.
# Used by NotificationBellHelper to compute count and severity in one DB hit.
def unread_notification_breakdown
  notifications
    .where(read_at: nil)
    .joins("INNER JOIN noticed_events ON noticed_events.id = noticed_notifications.event_id")
    .group("noticed_events.type")
    .count
end
```

- [ ] **Step 4: Run test to verify it passes.**

```bash
bundle exec rspec spec/models/user_spec.rb -e "unread_notification_breakdown"
```

Expected: 4 passing.

- [ ] **Step 5: Run full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 6: Commit.**

```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "feat(notifications): add User#unread_notification_breakdown grouped query"
```

---

## Task 4: Create `NotificationBellHelper`

**Files:**
- Create: `app/helpers/notification_bell_helper.rb`
- Create (test): `spec/helpers/notification_bell_helper_spec.rb`

- [ ] **Step 1: Write the failing test.**

Create `spec/helpers/notification_bell_helper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe NotificationBellHelper, type: :helper do
  let(:user) { create(:user) }

  describe "#unread_notification_summary" do
    it "returns count 0 and nil severity when there are no unread notifications" do
      expect(helper.unread_notification_summary(user)).to eq(count: 0, severity: nil)
    end

    it "returns the total count and the highest severity present" do
      PasswordChangedNotifier.with(record: user).deliver(user)             # danger
      WorkspaceCapacityApproachingNotifier.with(record: create(:workspace, owner: user)).deliver(user)  # warning
      WorkspaceMemberAddedNotifier.with(record: create(:workspace_member, user: user)).deliver(user)    # success

      result = helper.unread_notification_summary(user)
      expect(result[:count]).to eq(3)
      expect(result[:severity]).to eq(:danger)
    end

    it "ranks warning above info above success" do
      WorkspaceCapacityApproachingNotifier.with(record: create(:workspace, owner: user)).deliver(user)
      WorkspaceInvitationReceivedNotifier.with(record: create(:invitation, recipient: user)).deliver(user)

      result = helper.unread_notification_summary(user)
      expect(result[:severity]).to eq(:warning)
    end

    it "defaults to :info severity when a notifier class is missing" do
      # Simulate orphaned notifier row by direct insertion against the join target
      allow(user).to receive(:unread_notification_breakdown).and_return("DeletedNotifier" => 1)
      expect(Rails.logger).to receive(:warn).with(/Stale notifier class.*DeletedNotifier/)

      result = helper.unread_notification_summary(user)
      expect(result[:severity]).to eq(:info)
      expect(result[:count]).to eq(1)
    end
  end

  describe "#notification_bell_classes" do
    it "returns bg-danger and text-danger-icon for :danger" do
      expect(helper.notification_bell_classes(:danger)).to eq(
        bg: "bg-danger", icon: "text-danger-icon"
      )
    end

    it "returns the info classes for an unknown severity" do
      expect(helper.notification_bell_classes(:unknown)).to eq(
        bg: "bg-info", icon: "text-info-icon"
      )
    end

    {
      warning: { bg: "bg-warning", icon: "text-warning-icon" },
      info:    { bg: "bg-info",    icon: "text-info-icon"    },
      success: { bg: "bg-success", icon: "text-success-icon" }
    }.each do |severity, classes|
      it "returns the expected classes for #{severity.inspect}" do
        expect(helper.notification_bell_classes(severity)).to eq(classes)
      end
    end
  end

  describe "#avatar_button_aria_label" do
    it "returns the plain label when there are no unread notifications" do
      expect(helper.avatar_button_aria_label(user)).to eq("User menu for #{user.full_name}")
    end

    it "includes count and severity phrase when unread > 0" do
      PasswordChangedNotifier.with(record: user).deliver(user)

      label = helper.avatar_button_aria_label(user)
      expect(label).to include("1 unread notifications")
      expect(label).to include("a security alert")
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail.**

```bash
bundle exec rspec spec/helpers/notification_bell_helper_spec.rb
```

Expected: All examples fail with `uninitialized constant NotificationBellHelper`.

- [ ] **Step 3: Create the helper.**

Create `app/helpers/notification_bell_helper.rb`:

```ruby
module NotificationBellHelper
  SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }.freeze

  SEVERITY_CLASSES = {
    danger:  { bg: "bg-danger",  icon: "text-danger-icon"  },
    warning: { bg: "bg-warning", icon: "text-warning-icon" },
    info:    { bg: "bg-info",    icon: "text-info-icon"    },
    success: { bg: "bg-success", icon: "text-success-icon" }
  }.freeze

  def unread_notification_summary(user)
    breakdown = user.unread_notification_breakdown
    return { count: 0, severity: nil } if breakdown.empty?

    count = breakdown.values.sum
    severity = breakdown.keys
      .map { resolve_severity_for(_1) }
      .max_by { SEVERITY_RANK.fetch(_1) }

    { count: count, severity: severity }
  end

  def notification_bell_classes(severity)
    SEVERITY_CLASSES.fetch(severity, SEVERITY_CLASSES[:info])
  end

  def avatar_button_aria_label(user, summary = unread_notification_summary(user))
    if summary[:count].zero?
      t("navigation.user_menu_label", name: user.full_name)
    else
      t("navigation.user_menu_label_with_unread",
        name: user.full_name,
        count: summary[:count],
        phrase: t("notifications.severity_phrase.#{summary[:severity]}"))
    end
  end

  private

  def resolve_severity_for(notifier_class_name)
    case notifier_class_name.safe_constantize
    in nil
      Rails.logger.warn("Stale notifier class in unread notifications: #{notifier_class_name}")
      :info
    in notifier_class
      notifier_class.severity_name || :info
    end
  end
end
```

- [ ] **Step 4: Run helper tests to confirm they pass.**

```bash
bundle exec rspec spec/helpers/notification_bell_helper_spec.rb
```

Expected: All passing. (Note: the `avatar_button_aria_label` test for the unread case will fail until Task 5 adds the i18n keys. If you get an `I18n::MissingTranslationData` error here, that's expected — skip to Task 5 then come back. If you want green tests right now, temporarily stub the i18n call.)

- [ ] **Step 5: Run full suite.**

```bash
bundle exec rspec
```

Expected: helper test for `avatar_button_aria_label` with unread may fail until Task 5. Everything else: 0 failures.

- [ ] **Step 6: Commit.**

```bash
git add app/helpers/notification_bell_helper.rb spec/helpers/notification_bell_helper_spec.rb
git commit -m "feat(notifications): add NotificationBellHelper with severity resolution"
```

---

## Task 5: Add I18n keys (new + cleanup)

**Files:**
- Modify: `config/locales/en/application.en.yml`
- Modify: `config/locales/en/notifications.en.yml`

- [ ] **Step 1: Add new keys to `config/locales/en/application.en.yml`.**

Find the existing `navigation:` block (around line 11) and add this key immediately after `user_menu_label:`:

```yaml
user_menu_label_with_unread: "User menu for %{name}. %{count} unread notifications, including %{phrase}."
```

- [ ] **Step 2: Update `config/locales/en/notifications.en.yml` — remove old keys, add severity phrases.**

Remove these keys from the `bell:` block:
- `see_all`
- `unread_with_dnd`
- `unread_count` (if present)

Then, at the top level of the `notifications:` namespace (sibling of `bell:`), add:

```yaml
severity_phrase:
  danger: "a security alert"
  warning: "an important update"
  info: "an account update"
  success: "a workspace update"
```

- [ ] **Step 3: Re-run the helper tests that were waiting on these keys.**

```bash
bundle exec rspec spec/helpers/notification_bell_helper_spec.rb
```

Expected: All passing now.

- [ ] **Step 4: Run full suite.**

```bash
bundle exec rspec
```

Expected: Some specs may fail because they reference the removed `see_all` / `unread_with_dnd` keys. Note which specs are affected — these are the ones we'll update or delete in later tasks. If only the dropdown-related specs fail, that's expected.

- [ ] **Step 5: Commit.**

```bash
git add config/locales/
git commit -m "feat(notifications): replace bell tooltip i18n with severity phrase keys"
```

---

## Task 6: Add the `pulse-danger` Tailwind utility

**Files:**
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Write a tiny visual-state spec that asserts the class is present on a danger bell.**

This will be covered by the partial spec in Task 8. No standalone spec for the keyframes themselves (CSS animation can't be unit-tested meaningfully).

- [ ] **Step 2: Add the animation via `@theme` + `@keyframes` to `app/assets/tailwind/application.css`.**

This is the canonical v4 pattern Tailwind itself uses for `animate-pulse`, `animate-spin`, etc. Defining `--animate-pulse-danger` inside a `@theme` block automatically generates the `animate-pulse-danger` utility. Add at the bottom of the file (or in a clearly-marked "Animations" section if there's a convention):

```css
/* Subtle attention pulse for danger-severity notification bells.
   3s opacity cycle (100% → 70% → 100%). Wrapped via `motion-safe:`
   in the partial so it's suppressed under prefers-reduced-motion. */
@theme {
  --animate-pulse-danger: pulse-danger 3s ease-in-out infinite;
}

@keyframes pulse-danger {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.7; }
}
```

- [ ] **Step 3: Rebuild Tailwind to confirm no CSS syntax errors.**

```bash
bin/rails tailwindcss:build
```

Expected: Build completes without errors. (If the project uses `bin/dev` for live rebuild, that also works.)

- [ ] **Step 4: Quick smoke check — confirm the utility is generated.**

```bash
grep -c "animate-pulse-danger" app/assets/builds/tailwind.css
```

Expected: 0 (utility classes are only emitted when used in markup; this confirms it's not orphaned somewhere). Will become non-zero after Task 8.

- [ ] **Step 5: Commit.**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat(notifications): add pulse-danger Tailwind utility for severity bells"
```

---

## Task 7: Create `_notifications_menu_count_span.html.erb` partial

**Files:**
- Create: `app/views/shared/_notifications_menu_count_span.html.erb`
- Create (test): `spec/views/shared/_notifications_menu_count_span.html.erb_spec.rb`

- [ ] **Step 1: Write the failing partial spec.**

Create `spec/views/shared/_notifications_menu_count_span.html.erb_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "shared/_notifications_menu_count_span.html.erb", type: :view do
  let(:user) { create(:user) }

  it "renders empty when there are no unread notifications" do
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered.strip).to eq("")
  end

  it "renders the unread count when positive" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered).to include("(1)")
  end

  it "renders '10+' when unread exceeds 9" do
    11.times do |i|
      PasswordChangedNotifier.with(record: user, idempotency_key: "n_#{i}").deliver(user)
    end
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered).to include("(10+)")
  end
end
```

- [ ] **Step 2: Run spec to verify failure.**

```bash
bundle exec rspec spec/views/shared/_notifications_menu_count_span.html.erb_spec.rb
```

Expected: failures because the partial doesn't exist.

- [ ] **Step 3: Create the partial.**

Create `app/views/shared/_notifications_menu_count_span.html.erb`:

```erb
<%# locals: (user:) -%>
<% summary = unread_notification_summary(user) %>
<% if summary[:count].positive? %>
  <span class="ml-1 text-text-muted">
    (<%= summary[:count] > 9 ? "10+" : summary[:count] %>)
  </span>
<% end %>
```

- [ ] **Step 4: Run spec to confirm pass.**

```bash
bundle exec rspec spec/views/shared/_notifications_menu_count_span.html.erb_spec.rb
```

Expected: 3 passing.

- [ ] **Step 5: Run full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures except previously-noted dropdown-specs that are still pending cleanup.

- [ ] **Step 6: Commit.**

```bash
git add app/views/shared/_notifications_menu_count_span.html.erb spec/views/shared/_notifications_menu_count_span.html.erb_spec.rb
git commit -m "feat(notifications): add slim count-span partial for user menu"
```

---

## Task 8: Repurpose `_notifications_bell.html.erb` to slim overlay

**Files:**
- Modify: `app/views/shared/_notifications_bell.html.erb` (replace contents)
- Create (test): `spec/views/shared/_notifications_bell.html.erb_spec.rb`

- [ ] **Step 1: Write the failing partial spec.**

Create `spec/views/shared/_notifications_bell.html.erb_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "shared/_notifications_bell.html.erb", type: :view do
  let(:user) { create(:user) }

  it "renders an empty turbo-frame when there are no unread notifications" do
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('<turbo-frame id="notifications_bell_indicator_frame">')
    expect(rendered).not_to include('<span')
  end

  it "renders a danger-colored bell when the highest severity is :danger" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-danger')
    expect(rendered).to include('text-danger-icon')
    expect(rendered).to include('data-bell-severity="danger"')
    expect(rendered).to include('motion-safe:animate-pulse-danger')
    expect(rendered).to include('aria-hidden="true"')
  end

  it "renders a warning-colored bell without the pulse class" do
    WorkspaceCapacityApproachingNotifier.with(record: create(:workspace, owner: user)).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-warning')
    expect(rendered).to include('text-warning-icon')
    expect(rendered).not_to include('animate-pulse-danger')
  end

  it "renders an info-colored bell for account_access notifications" do
    WorkspaceInvitationReceivedNotifier.with(record: create(:invitation, recipient: user)).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-info')
    expect(rendered).to include('text-info-icon')
  end

  it "renders a success-colored bell for workspace_activity notifications" do
    WorkspaceMemberAddedNotifier.with(record: create(:workspace_member, user: user)).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-success')
    expect(rendered).to include('text-success-icon')
  end
end
```

- [ ] **Step 2: Run spec to confirm failure.**

```bash
bundle exec rspec spec/views/shared/_notifications_bell.html.erb_spec.rb
```

Expected: failures (current partial still has the old dropdown wrapper markup).

- [ ] **Step 3: Replace the contents of `app/views/shared/_notifications_bell.html.erb`.**

Replace the entire file with:

```erb
<%# locals: (user: Current.user) -%>
<%# Slim overlay partial: rendered inside the user-avatar button. Shows a
    solid bell glyph in a severity-colored chip when there are unread
    notifications; renders an empty turbo-frame otherwise. Broadcast target
    is `notifications_bell_indicator_frame`. %>
<% bell_user = local_assigns.fetch(:user) { Current.user } %>
<% summary = unread_notification_summary(bell_user) %>
<turbo-frame id="notifications_bell_indicator_frame">
  <% if summary[:severity] %>
    <% colors = notification_bell_classes(summary[:severity]) %>
    <span class="absolute -bottom-0.5 -right-0.5
                 flex size-4 items-center justify-center
                 rounded-full ring-2 ring-surface-raised
                 motion-safe:transition-opacity motion-safe:duration-150
                 <%= colors[:bg] %>
                 <%= "motion-safe:animate-pulse-danger" if summary[:severity] == :danger %>"
          data-bell-severity="<%= summary[:severity] %>"
          aria-hidden="true">
      <%= icon(:bell, style: :solid, class: "size-2.5 #{colors[:icon]}") %>
    </span>
  <% end %>
</turbo-frame>
```

- [ ] **Step 4: Run partial spec to confirm pass.**

```bash
bundle exec rspec spec/views/shared/_notifications_bell.html.erb_spec.rb
```

Expected: 5 passing.

- [ ] **Step 5: Full suite (expect dropdown-related fallout — that's fine for now).**

```bash
bundle exec rspec
```

Expected: dropdown-system specs are still pending deletion; non-dropdown specs should pass. Document any other failures that aren't in `spec/system/notifications_dropdown_spec.rb` for triage.

- [ ] **Step 6: Commit.**

```bash
git add app/views/shared/_notifications_bell.html.erb spec/views/shared/_notifications_bell.html.erb_spec.rb
git commit -m "feat(notifications): replace bell wrapper with slim severity overlay"
```

---

## Task 9: Create `_user_menu_avatar_button.html.erb` partial

**Files:**
- Create: `app/views/shared/_user_menu_avatar_button.html.erb`
- Create (test): `spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb`

- [ ] **Step 1: Write the failing partial spec.**

Create `spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "shared/_user_menu_avatar_button.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Dave", last_name: "Chmura") }

  it "renders a button with the plain aria-label when there are no unread" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('aria-label="User menu for Dave Chmura"')
    expect(rendered).to include('id="user-menu-button"')
    expect(rendered).to include('aria-haspopup="true"')
    expect(rendered).to include('aria-expanded="false"')
  end

  it "includes the count and severity phrase in the aria-label when unread > 0" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to match(/aria-label="User menu for Dave Chmura\. 1 unread notifications, including a security alert\."/)
  end

  it "nests the avatar image inside the button" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('id="user_avatar_header"')
  end

  it "renders the bell overlay partial as a sibling of the avatar inside the button" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('notifications_bell_indicator_frame')
    expect(rendered).to include('bg-danger')
  end
end
```

- [ ] **Step 2: Run spec to confirm failure.**

```bash
bundle exec rspec spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb
```

Expected: all 4 fail (partial doesn't exist).

- [ ] **Step 3: Create the partial.**

Create `app/views/shared/_user_menu_avatar_button.html.erb`:

```erb
<%# locals: (user:) -%>
<%# Slim partial: the avatar trigger button. Used both inline by
    `_user_menu.html.erb` and as the broadcast target for
    `notifications_avatar_button_frame`. Holds the state-aware
    aria-label (refreshes via broadcast) and nests the bell overlay
    inside the button so there's a single 44x44 focus + touch target. %>
<button data-dropdown-target="button"
        data-action="click->dropdown#toggle"
        id="user-menu-button"
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls="user-menu"
        aria-label="<%= avatar_button_aria_label(user) %>"
        class="btn-touch-target relative rounded-full
               focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
               cursor-pointer">
  <span id="user_avatar_header"><%= avatar_for(user, size: :md) %></span>
  <%= render "shared/notifications_bell", user: user %>
</button>
```

- [ ] **Step 4: Run spec to confirm pass.**

```bash
bundle exec rspec spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb
```

Expected: 4 passing.

- [ ] **Step 5: Run full suite (dropdown failures still acceptable).**

```bash
bundle exec rspec
```

- [ ] **Step 6: Commit.**

```bash
git add app/views/shared/_user_menu_avatar_button.html.erb spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb
git commit -m "feat(notifications): add slim avatar-button partial for broadcast"
```

---

## Task 10: Wire the new partials into `_user_menu.html.erb`

**Files:**
- Modify: `app/views/shared/_user_menu.html.erb`

- [ ] **Step 1: Find the section to replace.**

In `app/views/shared/_user_menu.html.erb` the current desktop section renders the standalone bell as a sibling of the avatar dropdown:

```erb
<%# Desktop: bell + avatar-triggered dropdown %>
<div class="hidden md:flex items-center gap-2">
  <%= render "shared/notifications_bell" %>
<div data-controller="dropdown"
     class="relative">
  <button data-dropdown-target="button"
          data-action="click->dropdown#toggle"
          id="user-menu-button"
          ...
```

You will replace that nested structure with the new turbo-frame-wrapped avatar button.

- [ ] **Step 2: Replace the desktop avatar section.**

Update the desktop branch so it looks like this (the structure around `<%= render "shared/notifications_bell" %>` and the inline `<button>` becomes a single turbo-frame'd partial render):

```erb
<% if context == :desktop %>
<%# Desktop: avatar with notification overlay; bell + count broadcast targets %>
<div class="hidden md:flex items-center gap-2">
  <div data-controller="dropdown"
       class="relative">
    <turbo-frame id="notifications_avatar_button_frame">
      <%= render "shared/user_menu_avatar_button", user: Current.user %>
    </turbo-frame>

    <div data-dropdown-target="menu"
         id="user-menu"
         role="menu"
         aria-orientation="vertical"
         aria-labelledby="user-menu-button"
         class="hidden absolute right-0 mt-2 w-64 rounded-lg
                bg-surface-raised border border-border shadow-lg z-50">
      <div class="px-4 py-3">
        <p class="text-sm font-semibold text-text-heading"><%= Current.user.full_name %></p>
        <p class="text-sm text-text-muted truncate"><%= Current.user.email_address %></p>
      </div>

      <div class="border-t border-border">
        <%= link_to t("navigation.profile"), main_app.edit_account_profile_path,
              role: "menuitem", tabindex: "-1",
              class: "flex items-center min-h-[var(--form-input-height)] px-4 py-2
                      text-sm text-text-body
                      hover:bg-surface hover:text-interactive
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:text-interactive" %>
      </div>

      <div class="border-t border-border">
        <%= link_to main_app.account_notifications_path,
              role: "menuitem", tabindex: "-1",
              class: "flex items-center min-h-[var(--form-input-height)] px-4 py-2
                      text-sm text-text-body
                      hover:bg-surface hover:text-interactive
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:text-interactive" do %>
          <%= t("navigation.notifications") %>
          <turbo-frame id="notifications_menu_count_frame">
            <%= render "shared/notifications_menu_count_span", user: Current.user %>
          </turbo-frame>
        <% end %>
      </div>

      <div class="border-t border-border">
        <%= link_to t("navigation.notification_preferences"), main_app.edit_account_notification_preferences_path,
              role: "menuitem", tabindex: "-1",
              data: prefs_dot_data,
              class: "flex items-center min-h-[var(--form-input-height)] px-4 py-2
                      text-sm text-text-body
                      hover:bg-surface hover:text-interactive
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:text-interactive
                      #{prefs_dot_classes}" %>
      </div>

      <div class="border-t border-border">
        <%= button_to t("navigation.sign_out"), main_app.session_path, method: :delete,
              role: "menuitem", tabindex: "-1",
              class: "w-full flex items-center min-h-[var(--form-input-height)] px-4 py-2
                      text-sm text-text-body
                      hover:bg-surface hover:text-interactive
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:text-interactive
                      cursor-pointer" %>
      </div>
    </div>
  </div>
</div>
<% end %>
```

For the mobile branch (`if context == :mobile`), update the Notifications link to include the count span inline (no turbo-frame — mobile menu doesn't get broadcast updates):

```erb
<%= link_to main_app.account_notifications_path,
      class: "min-h-[var(--form-input-height)] flex items-center px-2 text-text-body
              hover:text-interactive-hover rounded
              focus:outline-none focus:ring-2 focus:ring-interactive-focus" do %>
  <%= t("navigation.notifications") %>
  <%= render "shared/notifications_menu_count_span", user: Current.user %>
<% end %>
```

- [ ] **Step 3: Boot the app and visually verify.**

```bash
bin/dev
```

Open `http://localhost:3000`, log in, and verify:
- Header now shows only [Workspaces] [theme toggle] [avatar] — no standalone bell
- Avatar with no unread: clean, no overlay
- Avatar with unread: small colored chip at bottom-right
- Click avatar: user menu opens; "Notifications" link shows `(N)` count

If the bell doesn't render where expected, check that `_user_menu_avatar_button` is rendering inside the `<button>` element (the avatar should still be the button, with the bell `<span>` absolute-positioned within it).

- [ ] **Step 4: Run the full suite. Expect dropdown specs to fail; everything else green.**

```bash
bundle exec rspec
```

Note any system spec failures outside `spec/system/notifications_dropdown_spec.rb` and `spec/system/notifications_a11y_spec.rb` for follow-up.

- [ ] **Step 5: Commit.**

```bash
git add app/views/shared/_user_menu.html.erb
git commit -m "feat(notifications): wire avatar-button + count partials into user menu"
```

---

## Task 11: Update `NotificationBroadcaster` to the 4-target quartet

**Files:**
- Modify: `app/lib/notification_broadcaster.rb`
- Modify: `spec/lib/notification_broadcaster_spec.rb`

- [ ] **Step 1: Read the existing broadcaster spec to understand what's there.**

```bash
cat spec/lib/notification_broadcaster_spec.rb
```

Note the assertions on `notifications_bell_frame` and `notifications_dropdown_frame` — these need to be updated.

- [ ] **Step 2: Update the spec to assert the new four targets.**

In `spec/lib/notification_broadcaster_spec.rb`, replace expectations referencing the old targets. The exact shape depends on how the spec is structured, but here is the expectation pattern that needs to hold:

```ruby
it "broadcasts replace to the avatar button frame" do
  expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
    [user, :notifications],
    target: "notifications_avatar_button_frame",
    partial: "shared/user_menu_avatar_button",
    locals: { user: user }
  )
  # ... and similarly for the other three broadcasts
  NotificationBroadcaster.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
end

it "broadcasts replace to the bell indicator frame" do
  expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
    [user, :notifications],
    target: "notifications_bell_indicator_frame",
    partial: "shared/notifications_bell",
    locals: { user: user }
  ).and_call_original.at_least(:once)
  # ...
end

it "broadcasts replace to the menu count frame" do
  expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
    [user, :notifications],
    target: "notifications_menu_count_frame",
    partial: "shared/notifications_menu_count_span",
    locals: { user: user }
  ).and_call_original.at_least(:once)
  # ...
end

it "broadcasts update to the aria-live region" do
  expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
    [user, :notifications],
    target: "notifications-live",
    content: I18n.t("notifications.bell.arrival_announcement")
  )
  # ...
end
```

If the existing spec uses a single test that checks all targets, restructure to four assertions (or use `expect(...).to receive(...).exactly(:once)` style for each).

- [ ] **Step 3: Run spec to confirm failure.**

```bash
bundle exec rspec spec/lib/notification_broadcaster_spec.rb
```

Expected: failures (broadcaster still emits old target names).

- [ ] **Step 4: Update `app/lib/notification_broadcaster.rb`.**

Replace the body of `refresh_for` with:

```ruby
def refresh_for(user, announcement_key:)
  stream_key = [user, :notifications]

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_avatar_button_frame",
    partial: "shared/user_menu_avatar_button",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_bell_indicator_frame",
    partial: "shared/notifications_bell",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_menu_count_frame",
    partial: "shared/notifications_menu_count_span",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_update_to(
    stream_key,
    target: "notifications-live",
    content: I18n.t(announcement_key)
  )
rescue StandardError => e
  Rails.logger.warn("notification broadcast failed: #{e.class}: #{e.message}")
  Rails.error.report(
    e,
    handled: true,
    severity: :warning,
    context: { source: "NotificationBroadcaster.refresh_for", announcement_key: announcement_key }
  )
end
```

Keep `module_function` and the module structure unchanged.

- [ ] **Step 5: Run broadcaster spec to confirm pass.**

```bash
bundle exec rspec spec/lib/notification_broadcaster_spec.rb
```

Expected: passing.

- [ ] **Step 6: Run `spec/models/notification_broadcasts_spec.rb` and update if it asserts the old targets.**

```bash
bundle exec rspec spec/models/notification_broadcasts_spec.rb
```

If failures reference `notifications_bell_frame` or `notifications_dropdown_frame`, update those expectations to the new four-target shape and re-run.

- [ ] **Step 7: Commit.**

```bash
git add app/lib/notification_broadcaster.rb spec/lib/notification_broadcaster_spec.rb spec/models/notification_broadcasts_spec.rb
git commit -m "feat(notifications): broadcast quartet — avatar button + bell + count + live"
```

---

## Task 12: Delete the obsolete dropdown files

**Files:**
- Delete: `app/views/shared/_notifications_dropdown.html.erb`
- Delete: `app/views/shared/_notifications_dropdown_list.html.erb`
- Delete: `app/views/shared/_notifications_bell_button.html.erb`
- Delete: `app/javascript/controllers/notification_dropdown_controller.js`
- Delete: `spec/system/notifications_dropdown_spec.rb`

- [ ] **Step 1: Confirm nothing else references these files.**

```bash
grep -rln "notifications_dropdown\|notifications_bell_button\|notification-dropdown\|notifications_dropdown_frame" app/ spec/ config/ 2>/dev/null
```

Expected output should be empty or only show the files about to be deleted. If anything else references them (a stray test, a comment, an i18n key), resolve that first.

- [ ] **Step 2: Delete the files.**

```bash
git rm app/views/shared/_notifications_dropdown.html.erb \
       app/views/shared/_notifications_dropdown_list.html.erb \
       app/views/shared/_notifications_bell_button.html.erb \
       app/javascript/controllers/notification_dropdown_controller.js \
       spec/system/notifications_dropdown_spec.rb
```

- [ ] **Step 3: Rebuild the JS importmap manifest (only needed if your project regenerates it).**

If `config/importmap.rb` had an explicit pin for the controller, remove it. Search:

```bash
grep -n "notification_dropdown" config/importmap.rb
```

If present, remove that line. If absent, no change.

- [ ] **Step 4: Run the full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures. (If anything fails referencing the deleted files, you missed a reference in Step 1.)

- [ ] **Step 5: Restart the dev server and visually confirm the dropdown is gone.**

```bash
bin/dev
```

Clicking the avatar should open the user menu only (no separate notifications dropdown anywhere). The bell, when present, should be a passive overlay (not clickable separately from the avatar).

- [ ] **Step 6: Commit.**

```bash
git commit -m "chore(notifications): remove obsolete dropdown partials, controller, spec"
```

---

## Task 13: Update `spec/system/notifications_a11y_spec.rb`

**Files:**
- Modify: `spec/system/notifications_a11y_spec.rb`

- [ ] **Step 1: Read the existing spec.**

```bash
cat spec/system/notifications_a11y_spec.rb
```

Identify any assertions about:
- `notifications_bell_frame` or `notifications_dropdown_frame` → replace with new target names
- The standalone bell button being keyboard-reachable → remove (bell is no longer a button)
- The dropdown panel being announced with `role="region"` → remove
- DND tooltip / `unread_with_dnd` → remove

- [ ] **Step 2: Rewrite the relevant examples to match the new design.**

Add or update examples to assert:

```ruby
it "exposes a state-aware aria-label on the avatar button" do
  PasswordChangedNotifier.with(record: user).deliver(user)
  visit root_path

  button = page.find("#user-menu-button")
  expect(button["aria-label"]).to include("1 unread notifications")
  expect(button["aria-label"]).to include("a security alert")
end

it "marks the bell overlay as aria-hidden" do
  PasswordChangedNotifier.with(record: user).deliver(user)
  visit root_path

  overlay = page.find('[data-bell-severity]')
  expect(overlay["aria-hidden"]).to eq("true")
end

it "refreshes the avatar button aria-label via broadcast on new arrival" do
  visit root_path
  expect(page.find("#user-menu-button")["aria-label"]).not_to include("unread notifications")

  perform_enqueued_jobs do
    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  expect(page).to have_css("#user-menu-button[aria-label*='1 unread notifications']", wait: 5)
end

it "updates the polite live region on broadcast" do
  visit root_path
  perform_enqueued_jobs do
    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  live_region = page.find("#notifications-live", visible: :all)
  expect(live_region.text).to include(I18n.t("notifications.bell.arrival_announcement"))
end

it "remains AAA compliant on every severity state" do
  [PasswordChangedNotifier, WorkspaceCapacityApproachingNotifier,
   WorkspaceInvitationReceivedNotifier, WorkspaceMemberAddedNotifier].each do |notifier|
    notifier.with(record: appropriate_record_for(notifier, user)).deliver(user)
    visit root_path
    # axe after-hook in this project asserts AAA automatically
  end
end
```

If any helper like `appropriate_record_for` doesn't already exist, define it inline in this spec or use the appropriate factory for each notifier.

- [ ] **Step 3: Run the spec to confirm pass.**

```bash
bundle exec rspec spec/system/notifications_a11y_spec.rb
```

Expected: passing. If axe flags anything, that's a real issue — investigate (likely contrast on a hue not anticipated).

- [ ] **Step 4: Run full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 5: Commit.**

```bash
git add spec/system/notifications_a11y_spec.rb
git commit -m "test(notifications): update a11y spec for avatar bell + broadcast freshness"
```

---

## Task 14: Add the new end-to-end system spec

**Files:**
- Create: `spec/system/notifications_avatar_indicator_spec.rb`

- [ ] **Step 1: Write the spec.**

Create `spec/system/notifications_avatar_indicator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Notifications avatar indicator", type: :system do
  let(:user) { create(:user) }

  before { login_as(user) }

  it "renders no bell overlay when there are no unread notifications" do
    visit root_path
    expect(page).not_to have_css('[data-bell-severity]')
  end

  it "renders a danger overlay when a security notification is unread" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit root_path
    expect(page).to have_css('[data-bell-severity="danger"]')
    expect(page).to have_css('.bg-danger')
    expect(page).to have_css('.motion-safe\\:animate-pulse-danger')
  end

  it "renders a warning overlay for billing notifications" do
    workspace = create(:workspace, owner: user)
    WorkspaceCapacityApproachingNotifier.with(record: workspace).deliver(user)
    visit root_path
    expect(page).to have_css('[data-bell-severity="warning"]')
    expect(page).to have_css('.bg-warning')
    expect(page).not_to have_css('.motion-safe\\:animate-pulse-danger')
  end

  it "shows highest-severity color when mixed categories are unread" do
    PasswordChangedNotifier.with(record: user).deliver(user)  # danger
    WorkspaceMemberAddedNotifier.with(record: create(:workspace_member, user: user)).deliver(user)  # success
    visit root_path
    expect(page).to have_css('[data-bell-severity="danger"]')
  end

  it "no notifications dropdown panel exists in the DOM" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit root_path
    expect(page).not_to have_css('#notifications-dropdown-panel')
    expect(page).not_to have_css('[data-controller~="notification-dropdown"]')
  end

  it "opens the user menu (not a notifications dropdown) when the avatar is clicked" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit root_path
    find("#user-menu-button").click
    expect(page).to have_css('#user-menu')
    expect(page).to have_text("Notifications (1)")
  end

  it "shows '10+' in the menu when more than 9 unread" do
    11.times do |i|
      PasswordChangedNotifier.with(record: user, idempotency_key: "k_#{i}").deliver(user)
    end
    visit root_path
    find("#user-menu-button").click
    expect(page).to have_text("Notifications (10+)")
  end

  it "live-updates overlay + count + aria-label when a notification arrives via broadcast" do
    visit root_path
    expect(page).not_to have_css('[data-bell-severity]')

    perform_enqueued_jobs do
      PasswordChangedNotifier.with(record: user).deliver(user)
    end

    expect(page).to have_css('[data-bell-severity="danger"]', wait: 5)
    expect(page.find("#user-menu-button")["aria-label"]).to include("1 unread notifications")
    find("#user-menu-button").click
    expect(page).to have_text("Notifications (1)")
  end

  it "removes the overlay live when all notifications are marked read" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit account_notifications_path
    expect(page).to have_css('[data-bell-severity="danger"]')

    perform_enqueued_jobs do
      click_button "Mark all as read"
    end

    expect(page).not_to have_css('[data-bell-severity]', wait: 5)
  end
end
```

- [ ] **Step 2: Run the spec.**

```bash
bundle exec rspec spec/system/notifications_avatar_indicator_spec.rb
```

Expected: all passing. If anything fails, the most likely culprits are:
- Test waits not long enough for Turbo broadcasts → bump the `wait:` value
- "Mark all as read" button text differs from the actual UI → adjust the locator
- Factory associations differ → adapt `create(:workspace, owner: user)` etc.

- [ ] **Step 3: Run full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 4: Commit.**

```bash
git add spec/system/notifications_avatar_indicator_spec.rb
git commit -m "test(notifications): add end-to-end avatar-indicator system spec"
```

---

## Task 15: Update `spec/requests/account/notifications_spec.rb`

**Files:**
- Modify: `spec/requests/account/notifications_spec.rb`

- [ ] **Step 1: Read existing assertions.**

```bash
grep -n "notifications_bell_frame\|notifications_dropdown_frame\|see_all\|unread_with_dnd" spec/requests/account/notifications_spec.rb
```

- [ ] **Step 2: Remove or rewrite obsolete assertions.**

Specifically:
- Any assertion that mark-all-as-read triggers a Turbo stream targeting `notifications_dropdown_frame` → replace with the new target names (`notifications_avatar_button_frame`, `notifications_bell_indicator_frame`, `notifications_menu_count_frame`).
- Any assertion that the response includes the `see_all` link text → remove.
- Any assertion about the dropdown panel HTML → remove.

The mark-all-as-read action's page-level behavior (HTTP status, redirect) should remain unchanged and stays asserted.

- [ ] **Step 3: Run spec to confirm pass.**

```bash
bundle exec rspec spec/requests/account/notifications_spec.rb
```

Expected: passing.

- [ ] **Step 4: Run full suite.**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 5: Commit.**

```bash
git add spec/requests/account/notifications_spec.rb
git commit -m "test(notifications): align request spec with new broadcast targets"
```

---

## Task 16: Final verification + audit

**Files:** (none modified)

- [ ] **Step 1: Run the full suite once more and confirm green.**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 2: Lefthook pre-push dry-run (or just push and let it enforce).**

```bash
bundle exec rubocop --parallel
bundle exec brakeman --quiet --no-summary --no-pager 2>&1 | tail
```

Expected: clean. Address any new offenses.

- [ ] **Step 3: Severity declaration audit in Rails console.**

```bash
bin/rails runner 'ApplicationNotifier.descendants.sort_by(&:name).each { |c| puts "#{c.name}: #{c.severity_name}" }'
```

Expected output (compare to the spec's "Severity assignments" table):

```
PasswordChangedNotifier: danger
ProjectMembershipChangedNotifier: info
SignInFromNewDeviceNotifier: danger
WorkspaceCapacityApproachingNotifier: warning
WorkspaceInvitationAcceptedNotifier: success
WorkspaceInvitationDeclinedNotifier: info
WorkspaceInvitationExpiringSoonNotifier: warning
WorkspaceInvitationReceivedNotifier: info
WorkspaceInvitationResentNotifier: info
WorkspaceMemberAddedNotifier: success
WorkspaceRoleChangedNotifier: info
```

- [ ] **Step 4: Manual visual check.**

Run `bin/dev`, log in, and visit `/` (or wherever the header is visible). Verify:

| State | Expected appearance |
|---|---|
| Zero unread | Avatar alone, no overlay; user menu opens; "Notifications" link has no count |
| 1 danger unread (e.g., password changed) | Red chip with solid bell at avatar bottom-right; pulse animation visible on normal motion preference; menu shows "Notifications (1)" |
| Mixed unread (security + workspace activity) | Red chip (danger wins); count reflects total |
| Mark-all-as-read in `/account/notifications` | Overlay vanishes within ~1s; menu count returns to "Notifications" with no number |
| Two browser tabs, dispatch a new notification | Both tabs' overlays appear simultaneously |

- [ ] **Step 5: Reduced-motion check.**

In macOS System Settings: Accessibility → Display → Reduce motion = ON. Reload. Verify:
- Overlay still appears when there's unread (correct semantically)
- No fade-in animation
- No pulse on danger
- Snap behavior throughout

- [ ] **Step 6: Stale-class graceful-degrade check.**

In a scratch console session:

```bash
bin/rails console
user = User.first
user.notifications.create!(
  type: "DeletedNotifier::Notification",
  recipient: user,
  event: Noticed::Event.create!(type: "DeletedNotifier", record: user, idempotency_key: "stale_test_#{Time.now.to_i}")
)
```

Reload the page. Verify the bell renders (as `:info` blue), the page doesn't 500, and a warning was logged to `log/development.log`:

```bash
grep "Stale notifier class" log/development.log
```

Expected: at least one match.

Clean up the row when done.

- [ ] **Step 7: Push the branch.**

```bash
git push -u origin feat/avatar-bell-indicator
```

Lefthook pre-push enforces the full suite locally. Pass → branch is ready for review.

---

## Self-review (do this before marking the plan complete)

Spec coverage — verify each spec requirement maps to a task:

| Spec section | Task(s) |
|---|---|
| `severity` DSL on ApplicationNotifier | Task 1 |
| Severity declared per notifier (table of 11) | Task 2 |
| `User#unread_notification_breakdown` | Task 3 |
| `NotificationBellHelper` (rank, classes, summary, aria-label, resolver) | Task 4 |
| I18n keys (add severity_phrase + user_menu_label_with_unread; remove dropdown keys) | Task 5 |
| Tailwind `animate-pulse-danger` utility | Task 6 |
| `_notifications_menu_count_span` partial | Task 7 |
| Repurposed `_notifications_bell` overlay | Task 8 |
| `_user_menu_avatar_button` partial | Task 9 |
| `_user_menu.html.erb` wiring | Task 10 |
| 4-target broadcaster quartet | Task 11 |
| Delete dropdown partials, Stimulus controller, dropdown spec | Task 12 |
| Update a11y spec | Task 13 |
| New system spec | Task 14 |
| Update request spec | Task 15 |
| Verification (severity audit, visual, reduced-motion, stale-class) | Task 16 |

Out of scope per spec:
- Mobile hamburger button decoration (intentionally deferred)
- Per-locale customization beyond English defaults (i18n machinery supports it; just no extra translations shipped here)
- Animation on severities below `:danger`
- `/account/notifications` page rework

DND open question: resolved in spec — no surface on the bell.
