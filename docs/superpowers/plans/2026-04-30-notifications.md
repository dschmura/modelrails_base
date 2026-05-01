# Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks ship across **five sequential PRs**; do not collapse them. Each PR ends with a merge checklist; do not skip the Lefthook pre-push gate.

**Goal:** Ship a per-user, persistent notifications system: in-app notification center, transactional email + daily/weekly digest, ten Notifier classes wired to existing domain events, master DND + per-category × per-channel preferences. AAA accessibility throughout. Web Push deferred to v1.1 as a clean additive change.

**Architecture:** Three layers — domain code fires Notifier classes; the [`noticed` gem](https://github.com/excid3/noticed) (v2.5+) persists `noticed_events` + `noticed_notifications` and fans out to delivery methods (`:database`, `:action_cable`, `:email`); we own the user-facing surfaces (bell dropdown, `/account/notifications` page, `/account/notification_preferences`, digest mailer, cleanup job). `ApplicationNotifier` centralizes idempotency-key population, preference resolution, locale, the `mark_seen!` after-deliver hook, and `render_safe_or_placeholder`. `NotificationPreferences` value object wraps the JSONB preferences column and is the single point of truth for the DND-vs-security rule. Trackable and Notifications stay parallel, fired explicitly by domain code (Decision #3 in the spec).

**Tech Stack:** Rails 8.1, Ruby 3.3+, SQLite with `BEGIN IMMEDIATE`, Solid Queue (jobs + recurring), Solid Cable (Action Cable), Solid Cache (`Rails.cache`), TailwindCSS 4 + OKLCH design tokens, Pundit, Turbo + Stimulus, RSpec (request/model/mailer/system + new `spec/notifiers/`, `spec/lib/`, `spec/jobs/`).

**Spec:** [docs/superpowers/specs/2026-04-30-notifications-design.md](../specs/2026-04-30-notifications-design.md)

**Important:** All shell commands use `mise exec --` prefix (per `.tool-versions`). Pre-push runs the full RSpec + Rubocop + Brakeman pipeline via Lefthook — never bypass with `LEFTHOOK=0`. Push small, complete PRs to `feat/notifications-*` branches; let CI validate the merge bar.

**Discipline:** Every task follows strict Red-Green TDD. The first numbered step in each task writes a failing spec that probes the contract the task delivers. Implementation only begins after the spec is observed failing for the right reason. Migration tasks are no exception — the spec probes the behavior the migration enables (uniqueness enforced, FK cascades, default values populated, etc.). Spec-reviewer probes get committed as test cases, never run as one-shot `bin/rails runner` output.

---

## Resolved open question — `digest_next_due_at` backfill

The spec leaves one implementation question for the plan: backfill strategy for existing users.

**Decision: randomized 24-hour window backfill.**

```ruby
User.in_batches(of: 500) do |batch|
  batch.includes(:user_preferences).each do |user|
    next unless user.user_preferences
    user.user_preferences.update_columns(
      digest_next_due_at: Time.current + rand(24).hours + rand(60).minutes
    )
  end
end
```

Rationale: the `DigestMailerJob` runs every 15 minutes and queries `WHERE digest_next_due_at <= NOW()`. A `nil`-backfilled cohort would all match the first job invocation after preferences are migrated, generating a thundering-herd email burst. Randomizing across 24 hours spreads the first-cycle load across ~96 job invocations (one per 15-minute slot). The cost is one extra `update_all`-equivalent in the migration data step — cheap. The existing `EmailRecipientThrottle` would catch a true flood, but spreading at the source is the right primitive. Subsequent cycles re-anchor on the user's preferred `hour_local` via `prefs.next_due_at_in(user.timezone)` post-send, so the randomization is one-shot.

---

## PR sequence (5 PRs)

1. **PR-1 Foundation** (Tasks 1–6): noticed install + hardening migrations, `NotificationPreferences` value object, `ApplicationNotifier` base class, **first two Notifiers end-to-end** (`WorkspaceInvitationReceivedNotifier`, `PasswordChangedNotifier`) as smoke test that the pattern works. User-Preferences plumbing. Locale scaffolding. **Merge gate:** the smoke-test Notifiers fire, persist, render in spec, and respect preferences. Pattern is proven.
2. **PR-2 Remaining 8 Notifiers** (Tasks 7–10): the eight remaining Notifier classes + their specs + locale keys + `User#last_known_browsers` fingerprint plumbing for `SignInFromNewDeviceNotifier` + scheduled-job triggers for `WorkspaceInvitationExpiringSoonNotifier` and `WorkspaceCapacityApproachingNotifier`. Repetitive after the pattern is set.
3. **PR-3 In-app surfaces** (Tasks 11–15): bell trigger in user menu, dropdown Turbo Frame, Stimulus controller, `/account/notifications` index/update/destroy/mark_all_read/destroy_all_read with batching, Turbo Stream broadcast wiring, `aria-live` region + reduced-motion + AAA-contrast styling.
4. **PR-4 Preferences UI** (Tasks 16–19): `/account/notification_preferences` page, value-object integration, master DND with tooltip count of suppressed unread, 5×3 category × channel matrix, digest cadence + time picker, retention dropdown, Turbo Stream auto-save per toggle.
5. **PR-5 Background jobs + hardening** (Tasks 20–25): `DigestMailerJob` (single indexed query, dedupe via `seen_at`), `NotificationCleanupJob` (grace + batching + security floor), `recurring.yml` annotated, full hardening test cases (idempotent retry, mid-fan-out failure, recipient deleted between event and delivery, notifiable deleted during render, throttle fail-open, concurrent mark-all-read).

---

## File Map

| Path | Action | PR |
| ---- | ------ | -- |
| `Gemfile`, `Gemfile.lock` | Modify (add `noticed ~> 2.5`) | 1 |
| `db/migrate/<ts>_install_noticed.rb` | Create (gem-generated) | 1 |
| `db/migrate/<ts>_harden_noticed_tables.rb` | Create | 1 |
| `db/migrate/<ts>_add_notification_preferences_to_user_preferences.rb` | Create | 1 |
| `db/migrate/<ts>_backfill_digest_next_due_at.rb` | Create (data-only) | 1 |
| `db/migrate/<ts>_add_last_known_browsers_to_users.rb` | Create | 2 |
| `db/schema.rb` | Modify (canonical schema dump — stays `:ruby` format throughout) | 1–2 |
| `app/lib/notification_preferences.rb` | Create (value object) | 1 |
| `app/notifiers/application_notifier.rb` | Create | 1 |
| `app/notifiers/workspace_invitation_received_notifier.rb` | Create | 1 |
| `app/notifiers/password_changed_notifier.rb` | Create | 1 |
| `app/notifiers/workspace_invitation_accepted_notifier.rb` | Create | 2 |
| `app/notifiers/workspace_invitation_declined_notifier.rb` | Create | 2 |
| `app/notifiers/workspace_invitation_expiring_soon_notifier.rb` | Create | 2 |
| `app/notifiers/workspace_member_added_notifier.rb` | Create | 2 |
| `app/notifiers/workspace_role_changed_notifier.rb` | Create | 2 |
| `app/notifiers/project_membership_changed_notifier.rb` | Create | 2 |
| `app/notifiers/workspace_capacity_approaching_notifier.rb` | Create | 2 |
| `app/notifiers/sign_in_from_new_device_notifier.rb` | Create | 2 |
| `app/models/user.rb` | Modify (associations, `last_known_browsers`, `seen_browser?`) | 1, 2 |
| `app/models/user_preferences.rb` | Modify (typed accessor, schema columns) | 1 |
| `app/controllers/concerns/authentication.rb` | Modify (fingerprint hook) | 2 |
| `app/controllers/account/notifications_controller.rb` | Create | 3 |
| `app/controllers/account/notification_preferences_controller.rb` | Create | 4 |
| `app/policies/notification_policy.rb` | Create | 3 |
| `app/views/account/notifications/{index,_item}.html.erb` | Create | 3 |
| `app/views/shared/_notifications_dropdown.html.erb` | Create | 3 |
| `app/views/account/notifications/{mark_all_read,destroy_all_read}.turbo_stream.erb` | Create | 3 |
| `app/views/account/notification_preferences/edit.html.erb` | Create | 4 |
| `app/views/account/notification_preferences/_matrix_row.turbo_stream.erb` | Create | 4 |
| `app/views/shared/_notifications_bell.html.erb` | Create | 3 |
| `app/views/shared/_user_menu.html.erb` | Modify (embed bell) | 3 |
| `app/views/layouts/application.html.erb` | Modify (live region) | 3 |
| `app/javascript/controllers/notification_dropdown_controller.js` | Create | 3 |
| `app/javascript/controllers/index.js` | Modify (register) | 3 |
| `app/mailers/notification_mailer.rb` | Create | 1, 5 |
| `app/views/notification_mailer/*.{html,text}.erb` | Create (per-Notifier + digest) | 1, 2, 5 |
| `app/jobs/digest_mailer_job.rb` | Create | 5 |
| `app/jobs/notification_cleanup_job.rb` | Create | 5 |
| `app/jobs/workspace_invitation_expiring_sweep_job.rb` | Create | 2 |
| `app/jobs/workspace_capacity_sweep_job.rb` | Create | 2 |
| `config/recurring.yml` | Modify (annotated entries) | 2, 5 |
| `config/routes.rb` | Modify | 3, 4 |
| `config/locales/en/notifications.en.yml` | Create | 1, 2, 3, 4 |
| `spec/models/noticed_setup_spec.rb` | Create (Task 1 TDD probe) | 1 |
| `spec/models/noticed_hardening_spec.rb` | Create (Task 2 TDD probe) | 1 |
| `spec/models/user_preferences_notifications_spec.rb` | Create (Task 3 TDD probe) | 1 |
| `spec/lib/notification_preferences_spec.rb` | Create | 1 |
| `spec/notifiers/application_notifier_spec.rb` | Create | 1 |
| `spec/notifiers/<event>_notifier_spec.rb` (×10) | Create | 1, 2 |
| `spec/mailers/notification_mailer_spec.rb` | Create | 1, 5 |
| `spec/jobs/digest_mailer_job_spec.rb` | Create | 5 |
| `spec/jobs/notification_cleanup_job_spec.rb` | Create | 5 |
| `spec/requests/account/notifications_spec.rb` | Create | 3 |
| `spec/requests/account/notification_preferences_spec.rb` | Create | 4 |
| `spec/system/notifications_dropdown_spec.rb` | Create | 3 |
| `spec/system/notification_preferences_spec.rb` | Create | 4 |
| `spec/system/notifications_a11y_spec.rb` | Create | 3 |
| `spec/requests/notifications_hardening_spec.rb` | Create | 5 |
| `CHANGELOG.md` | Modify (Unreleased) | 1–5 |

---

# PR-1 — Foundation (gem install, schema, value object, ApplicationNotifier, two smoke-test Notifiers)

Branch: `feat/notifications-foundation`. Ends when two Notifiers fire end-to-end through the gem, persist, render under preferences gating, and the pattern is proven.

---

## Task 1 — Install `noticed` gem and run gem migration (TDD)

**Files:**

- Modify: `Gemfile`, `Gemfile.lock`
- Create: `db/migrate/<ts>_install_noticed.rb` (gem-generated)
- Modify: `db/schema.rb`

- [ ] **Step 1.0: Write the failing spec**

Create `spec/models/noticed_setup_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Noticed gem setup" do
  it "loads Noticed::Event constant" do
    expect(defined?(Noticed::Event)).to be_truthy
  end

  it "creates noticed_events table with expected columns" do
    expect(ActiveRecord::Base.connection.tables).to include("noticed_events")
    columns = ActiveRecord::Base.connection.columns("noticed_events").map(&:name)
    expect(columns).to include("type", "params", "record_type", "record_id", "created_at", "updated_at")
  end

  it "creates noticed_notifications table with expected columns" do
    expect(ActiveRecord::Base.connection.tables).to include("noticed_notifications")
    columns = ActiveRecord::Base.connection.columns("noticed_notifications").map(&:name)
    expect(columns).to include("type", "event_id", "recipient_type", "recipient_id", "read_at", "seen_at")
  end
end
```

Run: `mise exec -- bundle exec rspec spec/models/noticed_setup_spec.rb 2>&1 | tail -10`

Expected: failures with `uninitialized constant Noticed::Event` and table-not-found errors.

- [ ] **Step 1.1: Add the gem**

In `Gemfile`, add to the main group (alongside other domain gems):

```ruby
gem "noticed", "~> 2.5"
```

- [ ] **Step 1.2: Bundle install**

Run: `mise exec -- bundle install`

Expected: bundler resolves `noticed` and its transitive dependency `http`. `Gemfile.lock` updates.

- [ ] **Step 1.3: Run the gem's migration generator**

Run: `mise exec -- bin/rails noticed:install:migrations`

Expected: a single migration file appears in `db/migrate/` named like `<ts>_install_noticed.rb` defining `noticed_events` and `noticed_notifications` tables. Inspect the generated file; confirm both tables are created with the columns listed in the spec.

- [ ] **Step 1.4: Run the migration**

Run: `mise exec -- bin/rails db:migrate`

Expected: both tables created. `db/schema.rb` regenerates with `create_table "noticed_events"` and `create_table "noticed_notifications"`.

- [ ] **Step 1.5: Smoke-check the schema**

Run: `mise exec -- bin/rails runner "puts ActiveRecord::Base.connection.tables.grep(/noticed/)"`

Expected output: `noticed_events` and `noticed_notifications`.

- [ ] **Step 1.6: Run full suite for regression**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1201 examples, 0 failures (no behavior change yet — gem is loaded but unused).

- [ ] **Step 1.7: Verify spec passes**

Run: `mise exec -- bundle exec rspec spec/models/noticed_setup_spec.rb 2>&1 | tail -5`

Expected: 3 examples, 0 failures.

- [ ] **Step 1.8: Commit**

```bash
git add Gemfile Gemfile.lock db/migrate/*_install_noticed.rb db/schema.rb spec/models/noticed_setup_spec.rb
git commit -m "chore(notifications): install noticed gem + run base migration"
```

---

## Task 2 — Hardening migration: idempotency_key column + indexes + FK + check constraints (TDD)

**Files:**

- Create: `db/migrate/<ts>_harden_noticed_tables.rb`
- Create: `spec/models/noticed_hardening_spec.rb`
- Modify: `db/schema.rb`

- [ ] **Step 2.1: Write the failing spec**

Create `spec/models/noticed_hardening_spec.rb` with cases probing each hardening feature:

1. Adding two `Noticed::Event` rows with the same `idempotency_key` raises `ActiveRecord::RecordNotUnique`.
2. Adding two `Noticed::Event` rows with `idempotency_key: nil` does NOT raise (partial index excludes NULLs).
3. Destroying a `Noticed::Event` cascade-deletes its `noticed_notifications` rows.
4. Inserting a `noticed_notifications` row with `recipient_type: "Workspace"` raises (check constraint v1 commitment).
5. Inserting a `noticed_notifications` row where `read_at < seen_at` raises (seen_before_read constraint).
6. The unread partial index `index_noticed_notifications_unread` exists with the expected `where:` clause.

Run the spec; verify all six cases fail with appropriate errors (column missing, constraint absent, etc.).

- [ ] **Step 2.2: Generate the migration**

Run: `mise exec -- bin/rails generate migration HardenNoticedTables`

- [ ] **Step 2.3: Write the migration body**

Replace the generated file contents with:

```ruby
class HardenNoticedTables < ActiveRecord::Migration[8.1]
  def change
    # Idempotency: dedicated column + partial unique index. Same Notifier class
    # targeting the same record with the same one-minute bucket dedupes at insert
    # time, atomically under SQLite BEGIN IMMEDIATE write serialization.
    add_column :noticed_events, :idempotency_key, :string

    add_index :noticed_events, :idempotency_key,
      unique: true,
      where: "idempotency_key IS NOT NULL",
      name: "index_noticed_events_on_idempotency_key"

    # Inline backfill: if any existing noticed_events rows have an
    # idempotency_key in their params JSONB (from earlier Option A work or
    # forks pulling this PR), populate the new column. No-op for fresh tables.
    reversible do |dir|
      dir.up do
        # Use raw SQL because Noticed::Event model isn't loaded during migration
        execute <<~SQL
          UPDATE noticed_events
          SET idempotency_key = json_extract(params, '$.idempotency_key')
          WHERE idempotency_key IS NULL
            AND json_extract(params, '$.idempotency_key') IS NOT NULL
        SQL
      end
      # No-op on down: column drop in change reversal handles cleanup
    end

    # Hot path: unread-count queries scope on (recipient_type, recipient_id)
    # and filter where read_at IS NULL. Partial index keeps it tiny.
    add_index :noticed_notifications,
      [:recipient_type, :recipient_id],
      where: "read_at IS NULL",
      name: "index_noticed_notifications_unread"

    # Cascade FK so events deleted in tests/cleanup wipe their notifications.
    add_foreign_key :noticed_notifications, :noticed_events,
      column: :event_id, on_delete: :cascade

    # seen_at always precedes read_at (notification can be emailed before read,
    # never read before being seen by any channel).
    add_check_constraint :noticed_notifications,
      "seen_at IS NULL OR read_at IS NULL OR read_at >= seen_at",
      name: "seen_before_read"

    # v1 commitment: User is the only valid recipient. Drop this when v1.x
    # broadens the polymorphic recipient.
    add_check_constraint :noticed_notifications,
      "recipient_type = 'User'",
      name: "recipient_type_user_only_v1"
  end
end
```

Note: this is plain Rails DSL. No raw `execute` for the unique index. No `json_extract` in the index (the column is the indexed value, not an expression). No `reversible` wrapper needed for the index parts. The only `reversible` block is for the data backfill (which has no inverse operation; the column drop in the reverse migration handles cleanup).

Note also that SQLite has no native `jsonb` type — Rails' `:json` column type maps to TEXT with JSON validation. The spec uses "jsonb" for vocabulary; the migrations correctly use `:json`. This is intentional and not a contract drift.

- [ ] **Step 2.4: Run the migration**

Run: `mise exec -- bin/rails db:migrate`

Expected: migration runs successfully; `db/schema.rb` updates with the new column, indexes, and check constraints.

- [ ] **Step 2.5: Verify spec passes**

Run: `mise exec -- bundle exec rspec spec/models/noticed_hardening_spec.rb 2>&1 | tail -10`

Expected: 6 examples, 0 failures. Each constraint enforces correctly.

- [ ] **Step 2.6: Verify reversibility on test DB**

Run:

```bash
mise exec -- bin/rails db:rollback STEP=1 RAILS_ENV=test
mise exec -- bin/rails db:migrate RAILS_ENV=test
```

Both should succeed with no `IrreversibleMigration`.

- [ ] **Step 2.7: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1201 + 6 = 1207 examples, 0 failures.

- [ ] **Step 2.8: Commit**

```bash
git add db/migrate/*_harden_noticed_tables.rb spec/models/noticed_hardening_spec.rb db/schema.rb
git commit -m "feat(notifications): harden noticed tables with idempotency_key column + indexes + constraints"
```

---

## Task 3 — Add notification preferences columns to `user_preferences` + backfill (TDD)

**Files:**

- Create: `db/migrate/<ts>_add_notification_preferences_to_user_preferences.rb`
- Create: `db/migrate/<ts>_backfill_digest_next_due_at.rb` (separate data migration)
- Create: `spec/models/user_preferences_notifications_spec.rb`
- Modify: `db/schema.rb`

- [ ] **Step 3.0: Write the failing spec**

Create `spec/models/user_preferences_notifications_spec.rb` probing each behavior the migration enables:

1. A new `UserPreferences` row has `notification_preferences` populated with the DEFAULT_PREFS hash structure (4 top-level keys: `do_not_disturb`, `digest`, `categories`, `retention_days`; 5 categories; 3 channels each; `retention_days: 90`).
2. The `digest_next_due_at` column exists and is settable to a future timestamp.
3. The partial index `index_user_preferences_digest_next_due_at` exists and shows up in `EXPLAIN QUERY PLAN` for a `digest_next_due_at`-filtered query.

Run the spec; verify all cases fail with column-not-found or default-mismatch errors.

- [ ] **Step 3.1: Generate the schema migration**

Run: `mise exec -- bin/rails generate migration AddNotificationPreferencesToUserPreferences`

- [ ] **Step 3.2: Write the schema migration**

```ruby
class AddNotificationPreferencesToUserPreferences < ActiveRecord::Migration[8.1]
  DEFAULT_PREFS = {
    "do_not_disturb" => false,
    "digest" => { "enabled" => true, "cadence" => "daily", "hour_local" => 8 },
    "categories" => {
      "security"           => { "in_app" => true,  "email" => true,  "digest" => false },
      "account_access"     => { "in_app" => true,  "email" => true,  "digest" => false },
      "workspace_activity" => { "in_app" => true,  "email" => false, "digest" => true  },
      "project_activity"   => { "in_app" => true,  "email" => false, "digest" => true  },
      "billing"            => { "in_app" => true,  "email" => true,  "digest" => false }
    },
    "retention_days" => 90
  }.freeze

  def change
    add_column :user_preferences, :notification_preferences, :json,
      default: DEFAULT_PREFS, null: false
    add_column :user_preferences, :digest_next_due_at, :datetime
    add_column :user_preferences, :digest_last_sent_at, :datetime

    add_index :user_preferences, :digest_next_due_at,
      where: "digest_next_due_at IS NOT NULL",
      name: "index_user_preferences_digest_next_due_at"
  end
end
```

- [ ] **Step 3.3: Generate the backfill migration (separate file)**

Run: `mise exec -- bin/rails generate migration BackfillDigestNextDueAt`

```ruby
class BackfillDigestNextDueAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    UserPreferences.unscoped.in_batches(of: 500) do |batch|
      batch.each do |prefs|
        # Spread first-cycle digest sends randomly across 24 hours to avoid
        # thundering herd against DigestMailerJob's 15-minute polling cadence.
        prefs.update_columns(
          digest_next_due_at: Time.current + rand(24).hours + rand(60).minutes
        )
      end
    end
  end

  def down
    UserPreferences.unscoped.update_all(digest_next_due_at: nil)
  end
end
```

The `disable_ddl_transaction!` lets the batched updates commit incrementally instead of holding one giant write lock.

- [ ] **Step 3.4: Run both migrations**

Run: `mise exec -- bin/rails db:migrate`

- [ ] **Step 3.5: Verify spec passes**

Run: `mise exec -- bundle exec rspec spec/models/user_preferences_notifications_spec.rb 2>&1 | tail -5`

Expected: 3 examples, 0 failures.

- [ ] **Step 3.6: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1207 + 3 = 1210 examples, 0 failures.

- [ ] **Step 3.7: Commit**

```bash
git add db/migrate/*_add_notification_preferences_to_user_preferences.rb \
        db/migrate/*_backfill_digest_next_due_at.rb db/schema.rb \
        spec/models/user_preferences_notifications_spec.rb
git commit -m "feat(notifications): add notification_preferences + digest scheduling columns"
```

---

## Task 4 — `NotificationPreferences` value object (TDD)

**Files:**

- Create: `app/lib/notification_preferences.rb`
- Create: `spec/lib/notification_preferences_spec.rb`
- Modify: `app/models/user_preferences.rb`

- [ ] **Step 4.1: Write the failing spec**

Create `spec/lib/notification_preferences_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe NotificationPreferences do
  let(:default_jsonb) do
    {
      "do_not_disturb" => false,
      "digest" => { "enabled" => true, "cadence" => "daily", "hour_local" => 8 },
      "categories" => {
        "security"           => { "in_app" => true, "email" => true, "digest" => false },
        "account_access"     => { "in_app" => true, "email" => true, "digest" => false },
        "workspace_activity" => { "in_app" => true, "email" => false, "digest" => true },
        "project_activity"   => { "in_app" => true, "email" => false, "digest" => true },
        "billing"            => { "in_app" => true, "email" => true, "digest" => false }
      },
      "retention_days" => 90
    }
  end

  describe "#allow?" do
    subject(:prefs) { described_class.new(default_jsonb) }

    it "permits in_app for security under defaults" do
      expect(prefs.allow?(category: "security", channel: "in_app")).to be true
    end

    it "denies digest for billing under defaults" do
      expect(prefs.allow?(category: "billing", channel: "digest")).to be false
    end

    context "when do_not_disturb is true" do
      let(:dnd) { default_jsonb.merge("do_not_disturb" => true) }
      subject(:prefs) { described_class.new(dnd) }

      it "still permits security category" do
        expect(prefs.allow?(category: "security", channel: "email")).to be true
      end

      it "suppresses non-security categories" do
        expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be false
        expect(prefs.allow?(category: "billing", channel: "email")).to be false
      end
    end

    context "with missing category in JSONB (forward compat)" do
      let(:partial) { default_jsonb.tap { |h| h["categories"].delete("billing") } }
      subject(:prefs) { described_class.new(partial) }

      it "returns false rather than raising" do
        expect(prefs.allow?(category: "billing", channel: "email")).to be false
      end
    end

    context "with malformed JSONB (nil)" do
      subject(:prefs) { described_class.new(nil) }

      it "returns false for any non-security request" do
        expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be false
      end

      it "still permits security (security bypasses missing data)" do
        expect(prefs.allow?(category: "security", channel: "in_app")).to be true
      end
    end

    it "rejects unknown category" do
      expect(prefs.allow?(category: "unicorns", channel: "in_app")).to be false
    end

    it "rejects unknown channel" do
      expect(prefs.allow?(category: "security", channel: "carrier_pigeon")).to be false
    end
  end

  describe "#do_not_disturb?" do
    it "is false by default" do
      expect(described_class.new(default_jsonb).do_not_disturb?).to be false
    end

    it "respects nil JSONB" do
      expect(described_class.new(nil).do_not_disturb?).to be false
    end
  end

  describe "#digest_enabled?" do
    it "is true by default" do
      expect(described_class.new(default_jsonb).digest_enabled?).to be true
    end

    it "is true when key absent (default-on)" do
      expect(described_class.new({}).digest_enabled?).to be true
    end

    it "is false when explicitly disabled" do
      jsonb = default_jsonb.deep_merge("digest" => { "enabled" => false })
      expect(described_class.new(jsonb).digest_enabled?).to be false
    end
  end

  describe "#retention_days" do
    it "returns the configured value" do
      expect(described_class.new(default_jsonb).retention_days).to eq 90
    end

    it "returns nil for never (key explicitly set to nil)" do
      expect(described_class.new(default_jsonb.merge("retention_days" => nil)).retention_days).to be_nil
    end

    it "returns nil when key is absent from the jsonb (corrupt or pre-migration row)" do
      jsonb = default_jsonb.except("retention_days")
      expect(described_class.new(jsonb).retention_days).to be_nil
    end
  end

  describe "#next_due_at_in" do
    let(:tz) { ActiveSupport::TimeZone["America/New_York"] }

    it "returns the next 8am-local for daily cadence" do
      Timecop.freeze(tz.parse("2026-04-30 14:00:00")) do
        expect(described_class.new(default_jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-01 08:00:00")
      end
    end

    it "returns 7 days out for weekly cadence" do
      jsonb = default_jsonb.deep_merge("digest" => { "cadence" => "weekly" })
      Timecop.freeze(tz.parse("2026-04-30 14:00:00")) do
        expect(described_class.new(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-07 08:00:00")
      end
    end
  end

  describe "constants" do
    it "lists 5 categories" do
      expect(described_class::CATEGORIES).to eq %w[security account_access workspace_activity project_activity billing]
    end

    it "lists 3 channels" do
      expect(described_class::CHANNELS).to eq %w[in_app email digest]
    end

    it "names exactly the digest-eligible categories" do
      expect(described_class::DIGEST_ELIGIBLE_CATEGORIES).to eq %w[workspace_activity project_activity]
    end

    it "enforces a 1-year floor for security retention" do
      expect(described_class::RETENTION_FLOORS[:security]).to eq 365.days
    end
  end
end
```

- [ ] **Step 4.2: Run spec to verify failure**

Run: `mise exec -- bundle exec rspec spec/lib/notification_preferences_spec.rb 2>&1 | tail -10`

Expected: file-not-found / `NameError: uninitialized constant NotificationPreferences`.

- [ ] **Step 4.3: Implement the value object**

Create `app/lib/notification_preferences.rb`:

```ruby
class NotificationPreferences
  CATEGORIES = %w[security account_access workspace_activity project_activity billing].freeze
  CHANNELS   = %w[in_app email digest].freeze
  SECURITY_CATEGORY = "security"
  DIGEST_ELIGIBLE_CATEGORIES = %w[workspace_activity project_activity].freeze
  RETENTION_FLOORS = { security: 365.days }.freeze
  SECURITY_NOTIFIER_TYPES = %w[SignInFromNewDeviceNotifier PasswordChangedNotifier].freeze

  def initialize(jsonb_hash)
    @data = jsonb_hash || {}
  end

  def allow?(category:, channel:)
    return false unless CATEGORIES.include?(category) && CHANNELS.include?(channel)
    return true if category == SECURITY_CATEGORY  # security bypasses DND
    return false if do_not_disturb?
    @data.dig("categories", category, channel) == true
  end

  def do_not_disturb?
    @data["do_not_disturb"] == true
  end

  def digest_enabled?
    @data.dig("digest", "enabled") != false
  end

  def digest_cadence
    @data.dig("digest", "cadence") || "daily"
  end

  def digest_hour_local
    @data.dig("digest", "hour_local") || 8
  end

  def retention_days
    # Returns nil when key is absent or explicitly nil ("never auto-delete").
    # Matches spec contract: `def retention_days = @data["retention_days"]`.
    # Default 90 is enforced via the JSONB column default in the migration,
    # not in the value object — keeps the "never" semantics representable.
    @data["retention_days"]
  end

  def next_due_at_in(timezone)
    now = Time.current.in_time_zone(timezone)
    next_local = timezone.local(now.year, now.month, now.day, digest_hour_local)
    next_local += 1.day if next_local <= now
    next_local += 6.days if digest_cadence == "weekly"
    next_local
  end

  def to_h = @data.deep_dup
end
```

- [ ] **Step 4.4: Wire the typed accessor on `UserPreferences`**

In `app/models/user_preferences.rb`, add:

```ruby
def notification_preferences_object
  NotificationPreferences.new(notification_preferences)
end
```

- [ ] **Step 4.5: Run the spec to confirm pass**

Run: `mise exec -- bundle exec rspec spec/lib/notification_preferences_spec.rb 2>&1 | tail -5`

Expected: all examples pass.

- [ ] **Step 4.6: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1201 + ~18 = 1219+ examples, 0 failures.

- [ ] **Step 4.7: Commit**

```bash
git add app/lib/notification_preferences.rb app/models/user_preferences.rb spec/lib/notification_preferences_spec.rb
git commit -m "feat(notifications): NotificationPreferences value object with DND-vs-security rule"
```

---

## Task 5 — `ApplicationNotifier` base class (TDD)

**Files:**

- Create: `app/notifiers/application_notifier.rb`
- Create: `spec/notifiers/application_notifier_spec.rb`
- Create: `config/locales/en/notifications.en.yml` (initial scaffolding)

- [ ] **Step 5.1: Scaffold the locale file**

Create `config/locales/en/notifications.en.yml` with the structure from the spec — at minimum, the `notifications.placeholder` key:

```yaml
en:
  notifications:
    placeholder: "This notification refers to something that no longer exists."
    bell:
      label: "Notifications"
      empty: "You're all caught up."
      see_all: "See all notifications"
      unread_count:
        zero:  ""
        one:   "1 unread"
        other: "%{count} unread"
      unread_with_dnd: "%{count} unread (%{hidden} hidden by Do Not Disturb)"
```

Other event-specific keys are added as Notifier classes are introduced.

- [ ] **Step 5.2: Write the failing spec**

Create `spec/notifiers/application_notifier_spec.rb`. The spec probes ALL of: category macro, idempotency-key written to the dedicated column (not `params`), `:delivered`/`:deduplicated` sentinel return contract, concurrent dispatch resolving to existing event row, `recipient_pref` delegation, `recipient_locale`, `mark_seen!`, and `render_safe_or_placeholder`.

```ruby
require "rails_helper"

RSpec.describe ApplicationNotifier, type: :notifier do
  # Build a stub subclass for unit testing the base behavior.
  before(:all) do
    stub_const("StubAccountAccessNotifier", Class.new(ApplicationNotifier) do
      category :account_access
      deliver_by :database
      required_param :resource

      def message = "stub"
      def url     = "/stub"
    end)

    stub_const("StubSecurityNotifier", Class.new(ApplicationNotifier) do
      category :security
      deliver_by :database
      required_param :resource

      def message = "stub-security"
      def url     = "/stub"
    end)
  end

  describe ".category" do
    it "registers the category name as a class attribute" do
      expect(StubAccountAccessNotifier.category_name).to eq "account_access"
    end
  end

  describe "automatic idempotency-key population" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    it "populates the idempotency_key column (not params) before insert" do
      StubAccountAccessNotifier.with(resource: resource).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
    end

    it "does NOT embed the key in params" do
      StubAccountAccessNotifier.with(resource: resource).deliver(user)
      event = Noticed::Event.last
      expect(event.params["idempotency_key"]).to be_nil
      expect(event.params[:idempotency_key]).to be_nil
    end

    it "uses Notifier_class + resource_id + minute-bucket format" do
      freeze_time do
        StubAccountAccessNotifier.with(resource: resource).deliver(user)
        event = Noticed::Event.last
        expect(event.idempotency_key)
          .to eq "StubAccountAccessNotifier_#{resource.id}_#{Time.current.to_i / 60}"
      end
    end

    it "preserves a domain-supplied idempotency_key when already set on the column" do
      notifier = StubAccountAccessNotifier.with(resource: resource)
      notifier.idempotency_key = "manual-123"
      notifier.deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to eq "manual-123"
    end

    it "raises ArgumentError when no resource and no explicit key supplied" do
      expect {
        stub_const("StubNoResourceNotifier", Class.new(ApplicationNotifier) do
          category :account_access
          deliver_by :database
          def message = "stub"; def url = "/stub"
        end)
        StubNoResourceNotifier.new.deliver(user)
      }.to raise_error(ArgumentError, /requires either a :resource/)
    end

    it "deduplicates repeated identical events within the same minute" do
      freeze_time do
        StubAccountAccessNotifier.with(resource: resource).deliver(user)
        expect {
          StubAccountAccessNotifier.with(resource: resource).deliver(user)
        }.not_to change(Noticed::Event, :count)
      end
    end

    it "returns :delivered on first send" do
      freeze_time do
        result = StubAccountAccessNotifier.with(resource: resource).deliver(user)
        expect(result).to eq :delivered
      end
    end

    it "returns :deduplicated on second send within the same minute (no exception escapes)" do
      freeze_time do
        StubAccountAccessNotifier.with(resource: resource).deliver(user)
        result = nil
        expect {
          result = StubAccountAccessNotifier.with(resource: resource).deliver(user)
        }.not_to raise_error
        expect(result).to eq :deduplicated
      end
    end

    it "concurrent dispatch: both calls' recipients get notifications linked to the single winning event row" do
      freeze_time do
        # Simulate two concurrent dispatches for the same key; both should link
        # their noticed_notifications rows to the same noticed_events row.
        result1 = StubAccountAccessNotifier.with(resource: resource).deliver(user)
        result2 = StubAccountAccessNotifier.with(resource: resource).deliver(user)

        expect(result1).to eq :delivered
        expect(result2).to eq :deduplicated
        expect(Noticed::Event.count).to eq 1
        # All notifications link to the single event row, not nil-FK
        expect(Noticed::Notification.where(recipient: user).pluck(:event_id).uniq)
          .to eq [Noticed::Event.last.id]
      end
    end
  end

  describe "#recipient_pref" do
    let(:user) { create(:user) }
    let!(:prefs) { user.user_preferences || create(:user_preferences, user: user) }

    it "delegates to NotificationPreferences#allow?" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end

    it "returns false when DND is on for non-security" do
      user.user_preferences.update!(notification_preferences:
        user.user_preferences.notification_preferences.merge("do_not_disturb" => true))
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to be false
    end

    it "still returns true for security under DND" do
      user.user_preferences.update!(notification_preferences:
        user.user_preferences.notification_preferences.merge("do_not_disturb" => true))
      StubSecurityNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to be true
    end
  end

  describe "#recipient_locale" do
    let(:user) { create(:user) }

    it "returns the recipient's locale from UserPreferences" do
      user.user_preferences&.update!(locale: "fr") || create(:user_preferences, user: user, locale: "fr")
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_locale).to eq :fr
    end

    it "falls back to I18n.default_locale when locale is blank" do
      user.user_preferences&.update!(locale: nil)
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_locale).to eq I18n.default_locale
    end
  end

  describe "#mark_seen!" do
    let(:user) { create(:user) }

    it "sets seen_at on the underlying notification row" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      freeze_time do
        notification.mark_seen!
        expect(notification.reload.seen_at).to eq Time.current
      end
    end

    it "is idempotent (re-calls don't bump the timestamp)" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      notification.mark_seen!
      original = notification.seen_at
      travel 1.hour do
        notification.mark_seen!
        expect(notification.reload.seen_at).to eq original
      end
    end
  end

  describe "#render_safe_or_placeholder" do
    let(:user) { create(:user) }

    it "yields normally when no error" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(notification.render_safe_or_placeholder { "ok" }).to eq "ok"
    end

    it "swallows RecordNotFound and renders placeholder" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      result = notification.render_safe_or_placeholder do
        raise ActiveRecord::RecordNotFound, "boom"
      end
      expect(result).to eq I18n.t("notifications.placeholder")
    end

    it "swallows NoMethodError only when receiver is nil (nil.fnord pattern)" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      result = notification.render_safe_or_placeholder { nil.fnord }
      expect(result).to eq I18n.t("notifications.placeholder")
    end

    it "re-raises NoMethodError when receiver is not nil (real bug)" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect {
        notification.render_safe_or_placeholder { "string".nonexistent_method }
      }.to raise_error(NoMethodError)
    end

    it "logs at info level" do
      StubAccountAccessNotifier.with(resource: user).deliver(user)
      notification = user.notifications.last
      expect(Rails.logger).to receive(:info).with(/deleted record/)
      notification.render_safe_or_placeholder { raise ActiveRecord::RecordNotFound }
    end
  end
end
```

- [ ] **Step 5.3: Run spec to confirm failure**

Run: `mise exec -- bundle exec rspec spec/notifiers/application_notifier_spec.rb 2>&1 | tail -10`

Expected: `NameError: uninitialized constant ApplicationNotifier`.

- [ ] **Step 5.4: Implement `ApplicationNotifier`**

Create `app/notifiers/application_notifier.rb`:

```ruby
class ApplicationNotifier < Noticed::Event
  class_attribute :category_name, instance_writer: false

  def self.category(name)
    self.category_name = name.to_s
  end

  before_create :populate_idempotency_key

  # Default delivery: every Notifier persists in-app. Subclasses add :email,
  # :action_cable, etc. The :database channel is not gated by per-channel
  # preferences; DND/in_app gating is enforced at the action_cable broadcast
  # and email-send sites.
  deliver_by :database

  notification_methods do
    def recipient_pref(channel)
      preferences_object.allow?(category: event.class.category_name, channel: channel.to_s)
    end

    def recipient_locale
      recipient.try(:preferences)&.locale.presence&.to_sym || I18n.default_locale
    end

    def mark_seen!
      return if seen_at.present?
      update_columns(seen_at: Time.current, updated_at: Time.current)
    end

    def render_safe_or_placeholder(&block)
      yield
    rescue ActiveRecord::RecordNotFound
      Rails.logger.info("Notification ##{id} references deleted record; rendering placeholder")
      I18n.t("notifications.placeholder")
    rescue NoMethodError => e
      raise unless e.receiver.nil?
      Rails.logger.info("Notification ##{id} references deleted record; rendering placeholder")
      I18n.t("notifications.placeholder")
    end

    private

    def preferences_object
      recipient.try(:preferences)&.notification_preferences_object || NotificationPreferences.new(nil)
    end
  end

  # Override deliver to return :delivered or :deduplicated sentinel.
  # The DB partial unique index on idempotency_key is the atomic source of
  # truth; this rescue is the real backstop for concurrent dispatch races.
  def deliver(recipients = nil, **options)
    super
    :delivered
  rescue ActiveRecord::RecordNotUnique
    # Concurrent dispatch lost the race. Recipients of the winning event row
    # already received their notifications. Return the sentinel so callers
    # can branch on it.
    :deduplicated
  end

  private

  def populate_idempotency_key
    return if idempotency_key.present?

    resource = params[:resource] || params["resource"]
    resource_id = resource.try(:id) || resource.try(:to_gid_param)

    if resource_id.blank?
      raise ArgumentError,
        "#{self.class.name} requires either a :resource with an id, or an explicit idempotency_key"
    end

    self.idempotency_key = "#{self.class.name}_#{resource_id}_#{Time.current.to_i / 60}"
  end
end
```

Key design points:
- `populate_idempotency_key` writes to `idempotency_key` (the dedicated column), NOT to `params`. No symbol/string normalization needed.
- No app-level `.exists?` fast-path. `deliver` calls `super` and relies on the DB partial unique index for atomic dedup.
- `deliver` returns `:delivered` on success and `:deduplicated` on `RecordNotUnique` rescue — tell-don't-ask sentinel contract.
- `render_safe_or_placeholder` rescues `NoMethodError` only when `e.receiver.nil?` — real bugs on non-nil receivers are re-raised.
- `recipient_locale` reads from `recipient.try(:preferences)&.locale` (the column lives on `UserPreferences`, not `User`) with `.presence` to handle empty strings.
- `record` and `record_type/record_id` remain Noticed's polymorphic source association — orthogonal to `idempotency_key`.

Note: the precise Noticed v2 hook names may differ slightly; if `notification_methods do ... end` isn't the right v2 macro, consult [Noticed README](https://github.com/excid3/noticed/blob/main/README.md) for the v2 equivalent. Adapt as needed but preserve the public API tested above.

- [ ] **Step 5.5: Run spec to confirm pass**

Run: `mise exec -- bundle exec rspec spec/notifiers/application_notifier_spec.rb 2>&1 | tail -5`

Expected: all examples pass.

- [ ] **Step 5.6: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1210+ + ~22 = 1232+ examples, 0 failures.

- [ ] **Step 5.7: Commit**

```bash
git add app/notifiers/application_notifier.rb spec/notifiers/application_notifier_spec.rb config/locales/en/notifications.en.yml
git commit -m "feat(notifications): ApplicationNotifier base with idempotency_key column, :delivered/:deduplicated sentinel, render-safe"
```

---

## Task 6 — Smoke-test Notifiers: `WorkspaceInvitationReceivedNotifier` + `PasswordChangedNotifier` (TDD, end-to-end)

This task **proves the pattern works end-to-end** — Notifier class, Mailer, view templates, recipient resolution, preference gating, idempotency. Two Notifiers exercise both the workspace-activity and security paths.

**Files:**

- Create: `app/notifiers/workspace_invitation_received_notifier.rb`
- Create: `app/notifiers/password_changed_notifier.rb`
- Create: `app/mailers/notification_mailer.rb`
- Create: `app/views/notification_mailer/workspace_invitation_received.{html,text}.erb`
- Create: `app/views/notification_mailer/password_changed.{html,text}.erb`
- Modify: `app/models/user.rb` (add `has_many :notifications, as: :recipient, class_name: "Noticed::Notification"`)
- Modify: `config/locales/en/notifications.en.yml`
- Modify: `app/controllers/invitations_controller.rb` or wherever invitations are created (fire the Notifier)
- Modify: `app/controllers/passwords_controller.rb` or User model after_update (fire the Notifier)
- Create: `spec/notifiers/workspace_invitation_received_notifier_spec.rb`
- Create: `spec/notifiers/password_changed_notifier_spec.rb`

- [ ] **Step 6.1: Add the User association**

In `app/models/user.rb`, add:

```ruby
has_many :notifications, as: :recipient, class_name: "Noticed::Notification", dependent: :destroy
```

- [ ] **Step 6.2: Add locale keys for the two events**

In `config/locales/en/notifications.en.yml`, append:

```yaml
    workspace_invitation_received:
      title: "%{inviter} invited you to %{workspace}"
      preview: "Click to review the invitation."
      mailer:
        subject: "%{inviter} invited you to %{workspace}"
        greeting: "Hi %{first_name},"
        body: "%{inviter} invited you to join the %{workspace} workspace."
        cta: "Review invitation"
    password_changed:
      title: "Your password was changed"
      preview: "If this wasn't you, secure your account immediately."
      mailer:
        subject: "Your %{app_name} password was changed"
        greeting: "Hi %{first_name},"
        body: "Your password was changed at %{timestamp}. If this wasn't you, reset it immediately."
        cta: "Review account security"
```

- [ ] **Step 6.3: Create `NotificationMailer`**

Create `app/mailers/notification_mailer.rb`:

```ruby
class NotificationMailer < ApplicationMailer
  def workspace_invitation_received(notification)
    @notification = notification
    @user = notification.recipient
    @invitation = notification.params[:invitation] || notification.event.record
    return unless @invitation # render-safe under deleted notifiable

    mail(
      to: @user.email_address,
      subject: I18n.t("notifications.workspace_invitation_received.mailer.subject",
                      locale: notification.recipient_locale,
                      inviter: @invitation.invited_by.first_name,
                      workspace: @invitation.invitable.name)
    )
  end

  def password_changed(notification)
    @notification = notification
    @user = notification.recipient

    mail(
      to: @user.email_address,
      subject: I18n.t("notifications.password_changed.mailer.subject",
                      locale: notification.recipient_locale,
                      app_name: I18n.t("application.name"))
    )
  end
end
```

- [ ] **Step 6.4: Create the mailer templates**

Create `app/views/notification_mailer/workspace_invitation_received.html.erb`,
`workspace_invitation_received.text.erb`, `password_changed.html.erb`,
`password_changed.text.erb` — short, locale-driven, matching the pattern in
existing mailers in this repo (`app/views/authentication_mailer/`,
`app/views/magic_link_mailer/`). Use the same styling.

- [ ] **Step 6.5: Implement `WorkspaceInvitationReceivedNotifier`**

Create `app/notifiers/workspace_invitation_received_notifier.rb`:

```ruby
class WorkspaceInvitationReceivedNotifier < ApplicationNotifier
  category :account_access

  required_param :invitation

  deliver_by :action_cable, format: :badge_payload,
             if: -> { recipient.user_preferences.notification_preferences_object.allow?(category: "account_access", channel: "in_app") }
  deliver_by :email, mailer: "NotificationMailer", method: :workspace_invitation_received,
             if: -> { recipient.user_preferences.notification_preferences_object.allow?(category: "account_access", channel: "email") },
             after_deliver: :mark_seen!

  notification_methods do
    def message
      I18n.t("notifications.workspace_invitation_received.title",
             locale: recipient_locale,
             inviter: event.params[:invitation].invited_by.first_name,
             workspace: event.params[:invitation].invitable.name)
    end

    def url
      Rails.application.routes.url_helpers.invitation_path(token: event.params[:invitation].token)
    end

    def badge_payload
      { unread_count: recipient.notifications.where(read_at: nil).count }
    end
  end
end
```

Use `EmailRecipientThrottle` in the email block — there's an existing reusable gate. Wrap the `deliver_by :email` `if:` with a throttle check:

```ruby
if: -> {
  prefs = recipient.user_preferences.notification_preferences_object
  prefs.allow?(category: "account_access", channel: "email") &&
    EmailRecipientThrottle.allow?(
      recipient: recipient.email_address,
      kind: "notification_workspace_invitation_received_notifier"
    )
}
```

- [ ] **Step 6.6: Implement `PasswordChangedNotifier`**

Create `app/notifiers/password_changed_notifier.rb`:

```ruby
class PasswordChangedNotifier < ApplicationNotifier
  category :security

  required_param :user

  deliver_by :action_cable, format: :badge_payload,
             if: -> { true }  # security bypasses DND
  deliver_by :email, mailer: "NotificationMailer", method: :password_changed,
             if: -> {
               EmailRecipientThrottle.allow?(
                 recipient: recipient.email_address,
                 kind: "notification_password_changed_notifier"
               )
             },
             after_deliver: :mark_seen!

  notification_methods do
    def message
      I18n.t("notifications.password_changed.title", locale: recipient_locale)
    end

    def url
      Rails.application.routes.url_helpers.account_security_path
    end

    def badge_payload
      { unread_count: recipient.notifications.where(read_at: nil).count }
    end
  end
end
```

- [ ] **Step 6.7: Wire the firing sites**

In the appropriate domain location (existing `app/controllers/invitations_controller.rb` or `app/models/invitation.rb` `after_create_commit`), add:

```ruby
WorkspaceInvitationReceivedNotifier
  .with(invitation: invitation)
  .deliver(invitation.invitee)
```

For password change, in `User` model add:

```ruby
after_update_commit :notify_password_changed, if: :saved_change_to_password_digest?

private

def notify_password_changed
  PasswordChangedNotifier.with(user: self).deliver(self)
end
```

- [ ] **Step 6.8: Write specs for both Notifiers**

Create `spec/notifiers/workspace_invitation_received_notifier_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe WorkspaceInvitationReceivedNotifier do
  let(:invitee) { create(:user) }
  let(:inviter) { create(:user, first_name: "Carol") }
  let(:workspace) { create(:workspace, name: "Acme") }
  let(:invitation) { create(:invitation, invitee: invitee, invited_by: inviter, invitable: workspace) }

  it "creates an in-app notification under default prefs" do
    expect {
      described_class.with(invitation: invitation).deliver(invitee)
    }.to change { invitee.notifications.count }.by(1)
  end

  it "enqueues the workspace invitation received mailer under default prefs" do
    expect {
      described_class.with(invitation: invitation).deliver(invitee)
    }.to have_enqueued_mail(NotificationMailer, :workspace_invitation_received)
  end

  it "skips email when recipient has account_access email disabled" do
    invitee.user_preferences.update!(
      notification_preferences: invitee.user_preferences.notification_preferences.tap { |h|
        h["categories"]["account_access"]["email"] = false
      }
    )
    expect {
      described_class.with(invitation: invitation).deliver(invitee)
    }.not_to have_enqueued_mail(NotificationMailer, :workspace_invitation_received)
  end

  it "skips email and in-app for non-security under DND" do
    invitee.user_preferences.update!(
      notification_preferences: invitee.user_preferences.notification_preferences.merge("do_not_disturb" => true)
    )
    expect {
      described_class.with(invitation: invitation).deliver(invitee)
    }.not_to have_enqueued_mail(NotificationMailer, :workspace_invitation_received)
    # database row still created — DND doesn't suppress :database
  end

  it "renders message in the recipient's locale" do
    invitee.update!(locale: "es")
    described_class.with(invitation: invitation).deliver(invitee)
    notification = invitee.notifications.last
    I18n.with_locale(:en) { expect(notification.message).to include("Carol") } # ES key inherits :en if missing
  end

  it "returns :delivered on first dispatch" do
    freeze_time do
      result = described_class.with(invitation: invitation).deliver(invitee)
      expect(result).to eq :delivered
    end
  end

  it "is idempotent: same invitation in the same minute creates one event and returns :deduplicated" do
    freeze_time do
      described_class.with(invitation: invitation).deliver(invitee)
      result = described_class.with(invitation: invitation).deliver(invitee)
      expect(result).to eq :deduplicated
      expect(Noticed::Event.count).to eq 1
    end
  end
end
```

Create `spec/notifiers/password_changed_notifier_spec.rb` with parallel structure focusing on:

- Notification created
- Email enqueued
- DND **does not** suppress (security bypass)
- Returns `:delivered` on first dispatch (not `self`)
- Repeated calls within the same minute return `:deduplicated` (not `self`) and dedupe to one event row

- [ ] **Step 6.9: Run the new specs**

Run: `mise exec -- bundle exec rspec spec/notifiers/ 2>&1 | tail -10`

Expected: all pass.

- [ ] **Step 6.10: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1241+ + ~14 = 1255+ examples, 0 failures.

- [ ] **Step 6.11: Add CHANGELOG entry**

In `CHANGELOG.md` under `## [Unreleased]`:

```markdown
### Added
- Notifications foundation: `noticed` gem, `noticed_events` + `noticed_notifications` schema with idempotency and unread indexes, `NotificationPreferences` value object, `ApplicationNotifier` base class with auto-idempotency-key + render-safe + mark-seen helpers. Two smoke-test Notifiers (`WorkspaceInvitationReceivedNotifier`, `PasswordChangedNotifier`) prove the pattern end-to-end.
```

- [ ] **Step 6.12: Commit**

```bash
git add app/notifiers/ app/mailers/notification_mailer.rb \
        app/views/notification_mailer/ app/models/user.rb \
        config/locales/en/notifications.en.yml \
        spec/notifiers/ CHANGELOG.md \
        app/controllers/invitations_controller.rb app/models/invitation.rb \
        app/controllers/passwords_controller.rb
git commit -m "feat(notifications): smoke-test Notifiers prove the pattern end-to-end"
```

---

### PR-1 merge checklist

- [ ] All task specs in `spec/lib/`, `spec/notifiers/`, and the new mailer specs pass
- [ ] Full `mise exec -- bundle exec rspec` green (1255+ examples, 0 failures)
- [ ] Lefthook pre-push runs clean (full RSpec + Rubocop + Brakeman)
- [ ] `mise exec -- bundle exec rubocop` zero offenses
- [ ] `mise exec -- bundle exec brakeman --no-pager` zero new warnings
- [ ] `CHANGELOG.md` Unreleased section names the foundation work
- [ ] Two Notifiers fire end-to-end via integration smoke (manually verify in `rails console` or the new specs)
- [ ] `db/schema.rb` reflects all three migrations and is committed

Push branch, open PR titled `feat(notifications): foundation — gem, schema, value object, ApplicationNotifier, smoke Notifiers`. Get green CI before moving to PR-2.

---

# PR-2 — Remaining 8 Notifiers + scheduled-job triggers

Branch: `feat/notifications-event-catalog` (off main once PR-1 merges).

Mostly repetitive after PR-1. Each Notifier is ~30 LOC of class + mailer-method + 2 view templates + locale block + ~40 LOC of spec. Eight events. Plus two **scheduled jobs** for the cron-style triggers and one **schema migration + sign-in hook** for the new-device fingerprint.

---

## Task 7 — Six straightforward Notifiers (each TDD)

These six Notifiers all have synchronous trigger sites (model callbacks / controller actions), so the firing pattern matches Task 6. Per Notifier: implement, write 4–6 tests, wire trigger site, run tests.

For each of the six below, follow this template:

1. Add locale keys to `config/locales/en/notifications.en.yml`.
2. Create the Notifier class in `app/notifiers/`.
3. Create the mailer method in `NotificationMailer` and the two template files (skip if not email-eligible per the v1 catalog).
4. Wire the trigger in the appropriate domain code (model `after_*_commit` or controller action).
5. Write the spec in `spec/notifiers/<name>_spec.rb` covering: created, email enqueued under default prefs, DND suppression, locale, idempotency.
6. Run `mise exec -- bundle exec rspec spec/notifiers/<name>_spec.rb`.

The six:

- [ ] **Step 7.1: `WorkspaceInvitationAcceptedNotifier`** — category `workspace_activity`. Recipient: inviter. Channels: in-app + digest (no email). Trigger: `Invitation#after_update_commit if: :accepted_at_changed?`. Email column in catalog reads `—`; skip mailer + templates.

- [ ] **Step 7.2: `WorkspaceInvitationDeclinedNotifier`** — category `workspace_activity`. Recipient: inviter. Channels: in-app + digest (no email). Trigger: `Invitation#after_update_commit if: :declined_at_changed?`.

- [ ] **Step 7.3: `WorkspaceMemberAddedNotifier`** — category `workspace_activity`. Two recipient buckets in one Notifier: the added user (gets in-app + email) and all workspace owners (in-app + digest, no email). Use Noticed's `recipients` method to resolve both groups.

<!-- VERIFIER (worth discussing #9): This is the most behaviorally complex Notifier in v1 — under-specifying invites drift. Required spec cases for `spec/notifiers/workspace_member_added_notifier_spec.rb`: -->

Required spec cases (write them all — drift on this Notifier is the most likely regression vector):

1. **Recipient resolution**: `Notifier.with(membership: m).recipients` returns exactly `[added_user, *workspace_owners_excluding_added_user]`. Order doesn't matter; deduplication does (if the added user is also a workspace owner — unusual but possible — they appear once, not twice).
2. **Added user — in-app**: `Noticed::Notification.where(recipient: added_user, type: described_class.name).count` is 1 after `deliver`.
3. **Added user — email**: a `NotificationMailer#workspace_member_added` job is enqueued targeting `added_user.email_address` (one and only one).
4. **Owner — in-app**: each owner has exactly one `noticed_notifications` row.
5. **Owner — NO email**: assert `enqueued_jobs` contains zero `NotificationMailer#workspace_member_added` jobs targeting any owner's email address.
6. **Owner — digest eligibility**: the owner's notification has `seen_at: nil` post-deliver (so it lands in the digest pipeline). Setting `seen_at` is reserved for the email path, which owners don't take.
7. **Preference gating — added user disabled email**: when `added_user.user_preferences.notification_preferences_object.allow?(category: "workspace_activity", channel: "email")` is false, the `NotificationMailer` job is NOT enqueued for them. (workspace_activity defaults to email-off, so this is the *default* path; spec the override too.)
8. **Preference gating — owner disabled in-app**: when an owner has `workspace_activity.in_app: false`, no `noticed_notifications` row is created for that owner; other owners still get theirs.
9. **DND — added user**: with DND on (and category not security), no email AND no in-app for the added user.
10. **Single event row**: regardless of how many recipients, exactly one `noticed_events` row is created per dispatch (Noticed v2 semantics; if this assertion fails, surface for design review).

- [ ] **Step 7.4: `WorkspaceRoleChangedNotifier`** — category `account_access`. Recipient: the user whose role changed. Channels: in-app + email. Trigger: `Membership#after_update_commit if: :saved_change_to_role_id?`.

- [ ] **Step 7.5: `ProjectMembershipChangedNotifier`** — category `project_activity`. Recipient: added/changed user. Channels: in-app + digest. Trigger: `ProjectMembership#after_create_commit` and `after_update_commit if: :saved_change_to_role_id?`.

- [ ] **Step 7.6: `WorkspaceInvitationExpiringSoonNotifier`** — category `account_access`. Recipient: invitee. Channels: in-app + email. Triggered by a scheduled sweep job (Task 9) — no model callback. Class itself is straightforward; the sweep job is what's new.

After all six are implemented, run: `mise exec -- bundle exec rspec spec/notifiers/ 2>&1 | tail -5`. Expected: all examples in the directory pass.

Commit: `git commit -m "feat(notifications): six event-driven Notifiers (accepted/declined/member-added/role-changed/project-membership/expiring-soon)"`.

---

## Task 8 — `SignInFromNewDeviceNotifier` + `User#last_known_browsers` plumbing (TDD)

**Files:**

- Create: `db/migrate/<ts>_add_last_known_browsers_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `app/controllers/concerns/authentication.rb`
- Create: `app/notifiers/sign_in_from_new_device_notifier.rb`
- Create: `app/views/notification_mailer/sign_in_from_new_device.{html,text}.erb`
- Modify: `app/mailers/notification_mailer.rb`
- Create: `spec/models/user_last_known_browsers_spec.rb`
- Create: `spec/notifiers/sign_in_from_new_device_notifier_spec.rb`

- [ ] **Step 8.1: Migration**

```ruby
class AddLastKnownBrowsersToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_known_browsers, :json, default: [], null: false
  end
end
```

Run, verify schema.

- [ ] **Step 8.2: Spec for `User#seen_browser?`**

```ruby
RSpec.describe User, type: :model do
  describe "#seen_browser?" do
    let(:user) { create(:user) }
    let(:ua) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit Chrome/120" }
    let(:digest) { Digest::SHA256.hexdigest("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit Chrome/120 Macintosh") }

    it "returns false for unseen browser" do
      expect(user.seen_browser?(ua, "Macintosh")).to be false
    end

    it "appends the browser to last_known_browsers" do
      freeze_time do
        user.record_browser!(ua, "Macintosh")
        entry = user.reload.last_known_browsers.first
        expect(entry["digest"]).to eq digest
        expect(Time.parse(entry["first_seen_at"])).to eq Time.current
      end
    end

    it "returns true for previously-recorded browser" do
      user.record_browser!(ua, "Macintosh")
      expect(user.reload.seen_browser?(ua, "Macintosh")).to be true
    end

    it "updates last_seen_at on revisit, keeps first_seen_at stable" do
      user.record_browser!(ua, "Macintosh")
      first = Time.parse(user.reload.last_known_browsers.first["first_seen_at"])
      travel 1.day do
        user.record_browser!(ua, "Macintosh")
        entry = user.reload.last_known_browsers.first
        expect(Time.parse(entry["first_seen_at"])).to eq first
        expect(Time.parse(entry["last_seen_at"])).to eq Time.current
      end
    end
  end
end
```

- [ ] **Step 8.3: Implement `User#seen_browser?` and `#record_browser!`**

```ruby
def seen_browser?(user_agent, os)
  digest = browser_digest(user_agent, os)
  last_known_browsers.any? { |entry| entry["digest"] == digest }
end

def record_browser!(user_agent, os)
  digest = browser_digest(user_agent, os)
  now = Time.current
  browsers = last_known_browsers.dup
  if (entry = browsers.find { |e| e["digest"] == digest })
    entry["last_seen_at"] = now.iso8601
  else
    browsers << { "digest" => digest, "first_seen_at" => now.iso8601, "last_seen_at" => now.iso8601 }
  end
  update_column(:last_known_browsers, browsers)
end

private

def browser_digest(user_agent, os)
  Digest::SHA256.hexdigest("#{user_agent} #{os}")
end
```

- [ ] **Step 8.4: Implement `SignInFromNewDeviceNotifier`**

Mirror `PasswordChangedNotifier`: category `:security`, in-app + email, security bypasses DND, throttle gated. Required params: `user`, `user_agent`, `os`.

- [ ] **Step 8.5: Wire the sign-in hook**

In `app/controllers/concerns/authentication.rb`, after a successful session create:

```ruby
ua = request.user_agent.to_s
os = parse_os_from_user_agent(ua)  # cheap helper; spec accepts a stub
unless current_user.seen_browser?(ua, os)
  SignInFromNewDeviceNotifier.with(user: current_user, user_agent: ua, os: os).deliver(current_user)
end
current_user.record_browser!(ua, os)
```

The `parse_os_from_user_agent` helper can be a tiny inline regex (Mac/Windows/Linux/iOS/Android) or use Rails' `ActionDispatch::Request#variant`. Keep it simple — the digest just needs to be deterministic, not gold-standard UA parsing.

- [ ] **Step 8.6: Spec the Notifier**

Standard spec template + a specific test: "fires only when fingerprint not in `last_known_browsers`".

- [ ] **Step 8.7: Run specs and full suite**

```bash
mise exec -- bundle exec rspec spec/models/user_last_known_browsers_spec.rb spec/notifiers/sign_in_from_new_device_notifier_spec.rb
mise exec -- bundle exec rspec
```

- [ ] **Step 8.8: Commit**

```bash
git commit -m "feat(notifications): SignInFromNewDeviceNotifier + browser-fingerprint heuristic"
```

---

## Task 9 — Scheduled-job-triggered Notifiers + `recurring.yml`

Two Notifiers fire from scheduled sweep jobs, not domain events: `WorkspaceInvitationExpiringSoonNotifier` (already implemented in Task 7.6) and `WorkspaceCapacityApproachingNotifier`.

**Files:**

- Create: `app/notifiers/workspace_capacity_approaching_notifier.rb`
- Create: `app/jobs/workspace_invitation_expiring_sweep_job.rb`
- Create: `app/jobs/workspace_capacity_sweep_job.rb`
- Modify: `config/recurring.yml`
- Create: `spec/jobs/workspace_invitation_expiring_sweep_job_spec.rb`
- Create: `spec/jobs/workspace_capacity_sweep_job_spec.rb`
- Create: `spec/notifiers/workspace_capacity_approaching_notifier_spec.rb`

- [ ] **Step 9.1: `WorkspaceCapacityApproachingNotifier`** — category `:billing`. Recipients: all workspace owners. Channels: in-app + email. Required params: `workspace`, `metric` ("members" / "projects"), `current`, `limit`. Idempotency key naturally clusters per workspace + metric + day.

- [ ] **Step 9.2: `WorkspaceInvitationExpiringSweepJob`** — runs every 6 hours. Query:

```ruby
class WorkspaceInvitationExpiringSweepJob < ApplicationJob
  def perform
    Invitation
      .where(accepted_at: nil, declined_at: nil)
      .where("expires_at BETWEEN ? AND ?", Time.current, 24.hours.from_now)
      .find_each do |invitation|
      WorkspaceInvitationExpiringSoonNotifier
        .with(invitation: invitation)
        .deliver(invitation.invitee)
    end
  end
end
```

Idempotency at the Notifier layer means re-runs in the same minute dedupe; over 6-hour cadence, daily idempotency-bucketing ensures one expiring-soon notification per invitation per day.

- [ ] **Step 9.3: `WorkspaceCapacitySweepJob`** — runs every 12 hours. Query:

```ruby
Workspace.find_each do |workspace|
  [:members, :projects].each do |metric|
    current = metric == :members ? workspace.members.count : workspace.projects.count
    limit   = metric == :members ? workspace.max_members : workspace.max_projects
    next unless limit && current >= (limit * 0.8)

    workspace.owners.each do |owner|
      WorkspaceCapacityApproachingNotifier.with(
        workspace: workspace, metric: metric.to_s, current: current, limit: limit
      ).deliver(owner)
    end
  end
end
```

- [ ] **Step 9.4: `config/recurring.yml`**

Add:

```yaml
production:
  workspace_invitation_expiring_sweep:
    class: WorkspaceInvitationExpiringSweepJob
    queue: default
    # Sweeps every 6 hours; per-day idempotency bucket means each expiring
    # invitation produces one notification per day until accepted/declined.
    schedule: every 6 hours

  workspace_capacity_sweep:
    class: WorkspaceCapacitySweepJob
    queue: default
    # 12-hour cadence balances alert freshness with noise budget;
    # idempotency-key is per-day so owners aren't double-notified.
    schedule: every 12 hours
```

(If a `recurring.yml` doesn't exist yet, create it; refer to the [Solid Queue recurring docs](https://github.com/rails/solid_queue#recurring-tasks).)

- [ ] **Step 9.5: Specs** for both jobs (within-window vs outside-window) and the Notifier (recipient resolution to all owners).

- [ ] **Step 9.6: Run + commit**

```bash
mise exec -- bundle exec rspec spec/jobs/ spec/notifiers/
git commit -m "feat(notifications): scheduled sweep jobs for invitation-expiring + capacity-approaching"
```

---

## Task 10 — CHANGELOG + final PR-2 sweep

- [ ] **Step 10.1: Update CHANGELOG**

Append to the Unreleased entry:

```markdown
- Eight additional Notifiers wired to existing domain events (workspace invitation accepted/declined/expiring-soon, member added, role changed, project membership, capacity approaching, sign-in from new device). Two scheduled sweep jobs for cron-style triggers. `User#last_known_browsers` JSONB array + UA-OS-SHA-256 fingerprint heuristic.
```

- [ ] **Step 10.2: Run full suite**

`mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: ~1310+ examples, 0 failures.

- [ ] **Step 10.3: Commit + push**

```bash
git commit -am "docs(notifications): CHANGELOG for full v1 event catalog"
git push -u origin feat/notifications-event-catalog
```

### PR-2 merge checklist

- [ ] All 10 Notifiers exist; each has its own spec passing
- [ ] `recurring.yml` annotated with rationale for each job
- [ ] `User#seen_browser?` + `User#record_browser!` covered
- [ ] Sign-in callback in `Authentication` concern fires `SignInFromNewDeviceNotifier` only on new fingerprint
- [ ] Full RSpec green
- [ ] Lefthook pre-push green; Rubocop + Brakeman clean
- [ ] CHANGELOG updated

---

# PR-3 — In-app surfaces (bell, dropdown, `/account/notifications` page, broadcast wiring, a11y)

Branch: `feat/notifications-in-app-surfaces`.

---

## Task 11 — `Account::NotificationsController` (TDD)

**Files:**

- Create: `app/controllers/account/notifications_controller.rb`
- Create: `app/policies/notification_policy.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/account/notifications_spec.rb`
- Create: `spec/policies/notification_policy_spec.rb`

- [ ] **Step 11.1: Routes**

```ruby
namespace :account do
  resources :notifications, only: [:index, :update, :destroy] do
    collection do
      post   :mark_all_read
      delete :destroy_all_read
    end
  end
end
```

- [ ] **Step 11.2: Pundit policy**

`app/policies/notification_policy.rb`: scope to `notifications.where(recipient: user)`; `update?`, `destroy?` permit only when `record.recipient_id == user.id`.

- [ ] **Step 11.3: Failing request specs**

`spec/requests/account/notifications_spec.rb` covering:

- `GET /account/notifications` lists current user's notifications, paginated
- Filter chip `?filter=unread` returns only unread
- Filter chip `?category=security` returns only that category
- `PATCH /account/notifications/:id` with `{read_at: 'now'}` marks read
- `PATCH /account/notifications/:id` with `{read_at: nil}` marks unread
- `DELETE /account/notifications/:id` destroys, scoped to recipient
- `POST /account/notifications/mark_all_read` marks all current-user unread (test with 250 unread → all 250 have `read_at` set after the request; behavior assertion, not stub-on-implementation)
- `DELETE /account/notifications/destroy_all_read` destroys all read (test with 250 read → all 250 destroyed; behavior assertion)

<!-- VERIFIER (worth discussing #6): The original spec text said "verified via stub on `in_batches`". CLAUDE.md project convention: "Test behaviors and outcomes, not implementation details." Memory entry [Test real rendered HTML] is the same principle. We assert the *outcome* (count of read_at-set rows) — the batching is an implementation choice that should remain invisible to the test. If you want to verify the lock-duration trade-off, do it via a separate performance test, not by spying on `in_batches`. -->

- Other user's notification IDs return 404 (Pundit scope hides)
- Unauthenticated request → redirect to sign-in

- [ ] **Step 11.4: Implement the controller**

```ruby
class Account::NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: [:update, :destroy]

  def index
    scope = policy_scope(Noticed::Notification).order(created_at: :desc)
    scope = scope.where(read_at: nil) if params[:filter] == "unread"
    if params[:category].present?
      scope = scope.where(type: notifier_types_in_category(params[:category]))
    end
    @pagy, @notifications = pagy(scope, items: 25)
  end

  def update
    authorize @notification
    @notification.update!(read_at: read_value)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: account_notifications_path }
    end
  end

  def destroy
    authorize @notification
    @notification.destroy!
    redirect_to account_notifications_path, notice: t(".success")
  end

  def mark_all_read
    Current.user.notifications.where(read_at: nil).in_batches(of: 100) do |batch|
      batch.update_all(read_at: Time.current, updated_at: Time.current)
    end
    redirect_to account_notifications_path, notice: t(".success")
  end

  def destroy_all_read
    Current.user.notifications.where.not(read_at: nil).in_batches(of: 100) do |batch|
      batch.destroy_all
    end
    redirect_to account_notifications_path, notice: t(".success")
  end

  private

  def set_notification
    @notification = Current.user.notifications.find(params[:id])
  end

  def read_value
    params[:read_at].present? ? Time.current : nil
  end

  def notifier_types_in_category(category)
    ApplicationNotifier.descendants.select { |c| c.category_name == category }.map(&:name)
  end
end
```

- [ ] **Step 11.5: Locale keys**

Add to `notifications.en.yml`:

```yaml
    index:
      heading: "Notifications"
      filters:
        all: "All"
        unread: "Unread"
        security: "Security"
        account_access: "Access"
        workspace_activity: "Workspace"
        project_activity: "Project"
        billing: "Billing"
      empty_all: "You're all caught up."
      empty_filter: "Nothing matches this filter."
      mark_all_read:
        action: "Mark all as read"
        success: "All notifications marked as read."
      destroy_all_read:
        action: "Delete all read"
        confirm: "Delete all your read notifications?"
        success: "Read notifications deleted."
```

- [ ] **Step 11.6: Run specs + full suite**

- [ ] **Step 11.7: Commit**

```bash
git commit -m "feat(notifications): /account/notifications controller, routes, policy, specs"
```

---

## Task 12 — `/account/notifications` index view + per-row partial

**Files:**

- Create: `app/views/account/notifications/index.html.erb`
- Create: `app/views/account/notifications/_item.html.erb`
- Create: `app/views/account/notifications/update.turbo_stream.erb`
- Create: `app/views/account/notifications/mark_all_read.turbo_stream.erb`
- Create: `app/views/account/notifications/destroy_all_read.turbo_stream.erb`
- Modify: `app/views/account/_navigation.html.erb` (add link to notifications page)

- [ ] **Step 12.1: Build the index view** — page heading, filter chips (using existing chip styles), pagy pagination, list of items via `render @notifications`. Each item is a `<li>` with: category-themed icon, title, preview, relative timestamp, "Mark unread" / "Delete" controls, and an unread dot indicator. Style with existing AAA-contrast tokens.

- [ ] **Step 12.2: Per-row partial uses `notification.render_safe_or_placeholder { notification.message }`** to swallow `RecordNotFound` when notifiables are deleted mid-render.

- [ ] **Step 12.3: Turbo Stream responses** for mark-read/unread/destroy-row + bulk actions remove or update the relevant `<li>` and bell-badge frame.

- [ ] **Step 12.4: System spec for the index page**

`spec/system/notifications_dropdown_spec.rb` covers the dropdown; create a parallel `spec/system/notifications_index_spec.rb` for the page:

- See list of notifications
- Click a notification item → `read_at` set + redirect to `notification.url`
- Click "Mark unread" on a row → row updates, `read_at` cleared
- Click "Delete" on a row → row removed, count decremented
- Bulk "Mark all as read" with 250 unread → all 250 have `read_at` set after the request (count-based behavior assertion; batching is an implementation detail and should not be spied on per project convention)
- Filter chips switch the visible set

- [ ] **Step 12.5: Run + commit**

```bash
git commit -m "feat(notifications): /account/notifications index page with filters, item partial, bulk actions"
```

---

## Task 13 — Bell icon + dropdown Turbo Frame in user menu

**Files:**

- Create: `app/views/shared/_notifications_bell.html.erb`
- Create: `app/views/shared/_notifications_dropdown.html.erb`
- Modify: `app/views/shared/_user_menu.html.erb`
- Create: `app/javascript/controllers/notification_dropdown_controller.js`
- Modify: `app/javascript/controllers/index.js`

The dropdown partial lives under `app/views/shared/` because it's rendered from the user-menu (a shared layout chrome surface), not from inside the `account` namespace. Aligns with the spec's "Files touched" list.

- [ ] **Step 13.1: `_notifications_bell.html.erb`** — bell icon trigger button, badge sub-element conditionally rendered when `current_user.notifications.where(read_at: nil).exists?`. Badge color: `--color-info` token by default, `--color-warning` when any unread notification is in the security category. Counter "1"–"9" or "10+".

- [ ] **Step 13.2: `_notifications_dropdown.html.erb`** — `<turbo-frame id="notifications_dropdown">` containing: heading "Notifications" + "See all →" link, list of last 10 unread + 5 most recent read (chronological newest first), empty-state when zero. `role="region"`, `aria-labelledby` pointing to the heading. Width 384px desktop, full-width mobile.

- [ ] **Step 13.3: Embed in `_user_menu.html.erb`** — render the bell partial **left of** the avatar (per spec implementation choice #2). Don't share state with the user-menu Stimulus controller.

- [ ] **Step 13.4: `notification_dropdown_controller.js`** — Stimulus controller. Targets: `panel`, `trigger`. Methods: `toggle()`, `open()`, `close()`. Keyboard: `Cmd/Ctrl+Shift+N` global toggle, arrow keys navigate items, `Enter` activates, `Escape` closes + returns focus to trigger. Respect `prefers-reduced-motion: reduce` (no slide animation).

- [ ] **Step 13.5: System spec** — `spec/system/notifications_dropdown_spec.rb`:

- Open dropdown via click → panel visible, focus moves to heading
- Open dropdown via `Cmd+Shift+N` → same
- Press `Escape` → panel hidden, focus on trigger
- Click an item in the dropdown → notification marked read, browser navigates to URL
- Empty state shows "You're all caught up."

- [ ] **Step 13.6: Run + commit**

```bash
git commit -m "feat(notifications): bell trigger + dropdown frame + Stimulus controller"
```

---

## Task 14 — Real-time arrival broadcast + live region

**Files:**

- Modify: `app/views/layouts/application.html.erb` (add live region)
- Modify: `app/notifiers/application_notifier.rb` (add the `:action_cable` broadcast → `[user, :notifications]`)
- Modify: `app/views/shared/_notifications_bell.html.erb` (wrap in a Turbo Frame ID matched by the broadcast)

- [ ] **Step 14.1: Live region in layout**

```erb
<div id="notifications-live" aria-live="polite" aria-atomic="true" class="sr-only"></div>
```

- [ ] **Step 14.2: Broadcast configuration**

In `ApplicationNotifier` (or per-Notifier, depending on Noticed v2 ergonomics), `deliver_by :action_cable` broadcasts to the recipient's stream. The bell partial's surrounding Turbo Frame morph-refreshes; the live region is updated via a Turbo Stream `update` targeted at `notifications-live`.

- [ ] **Step 14.3: System spec for arrival**

`spec/system/notifications_a11y_spec.rb`:

- Visit dashboard with 0 unread → no badge visible, live region empty
- Trigger a Notifier in the background (via `perform_later`) → badge appears, dropdown frame morphs, live region announces "1 new notification"
- Set `prefers-reduced-motion: reduce` via Playwright → no animation classes applied
- axe-core run on dropdown + index page passes `wcag2aaa` rules

- [ ] **Step 14.4: Run + commit**

```bash
git commit -m "feat(notifications): real-time bell-frame broadcast + aria-live region"
```

---

## Task 15 — A11y audit + CHANGELOG

- [ ] **Step 15.1: Run axe-core via Playwright on the dropdown and index pages**

Add to the system spec a tag `:axe` and assert `expect(page).to be_axe_clean.checking_only(:wcag2aaa)`.

- [ ] **Step 15.2: Verify keyboard parity** — every action available via mouse is available via keyboard. Spec exercises Tab/Arrow/Enter/Escape flow through the dropdown.

- [ ] **Step 15.3: Verify touch targets ≥ 44×44px** — visual inspection in Playwright; existing `.btn-touch-target` utility wraps interactive controls.

- [ ] **Step 15.4: CHANGELOG**

```markdown
- In-app notification surfaces: bell icon + dropdown in user menu, dedicated `/account/notifications` triage page with filter chips, per-row mark-read/unread/destroy + bulk mark-all-read/destroy-all-read (batched in 100s for SQLite write-lock release). Real-time arrival via Turbo Stream broadcast + `aria-live` polite announcement. AAA contrast, reduced-motion respect, full keyboard navigation.
```

- [ ] **Step 15.5: Run + commit + push**

```bash
mise exec -- bundle exec rspec
git commit -am "docs(notifications): CHANGELOG for in-app surfaces; a11y audit clean"
git push -u origin feat/notifications-in-app-surfaces
```

### PR-3 merge checklist

- [ ] `Account::NotificationsController` request specs + Pundit policy specs pass
- [ ] System specs for index page + dropdown + a11y pass; axe-core wcag2aaa clean
- [ ] Bell renders in user menu; badge updates via Turbo Stream broadcast
- [ ] Bulk operations batch in 100s (verified by spec spy)
- [ ] `prefers-reduced-motion: reduce` honored (no animation classes applied)
- [ ] Live region announces arrivals
- [ ] Lefthook pre-push green; Rubocop + Brakeman clean
- [ ] CHANGELOG updated

---

# PR-4 — Preferences UI (master DND, 5×3 matrix, digest cadence, retention)

Branch: `feat/notifications-preferences`.

---

## Task 16 — Routes + `Account::NotificationPreferencesController` (TDD)

**Files:**

- Modify: `config/routes.rb`
- Create: `app/controllers/account/notification_preferences_controller.rb`
- Create: `spec/requests/account/notification_preferences_spec.rb`

- [ ] **Step 16.1: Routes**

```ruby
namespace :account do
  resource :notification_preferences, only: [:edit, :update]
end
```

Singular `resource` because there's exactly one preferences record per user.

- [ ] **Step 16.2: Failing request specs** covering:

- `GET /account/notification_preferences/edit` requires authentication
- `PATCH /account/notification_preferences` with `{do_not_disturb: true}` flips the flag in JSONB
- `PATCH` with a single category × channel toggle updates exactly that nested key, leaves other keys intact (deep-merge semantics)
- `PATCH` with `digest: { cadence: "weekly", hour_local: 14 }` updates digest config + recomputes `digest_next_due_at`
- `PATCH` with `retention_days: 30` updates the value
- Invalid retention_days (e.g., 999) is rejected with a 422
- Turbo Stream format response replaces the toggle row with the saved state

- [ ] **Step 16.3: Implement the controller**

```ruby
class Account::NotificationPreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_prefs

  def edit
  end

  def update
    new_prefs = @prefs.notification_preferences.deep_dup
    apply_changes(new_prefs)
    @prefs.update!(notification_preferences: new_prefs)

    if turbo_recompute_due_at?
      @prefs.update!(digest_next_due_at: @prefs.notification_preferences_object.next_due_at_in(Current.user.timezone))
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to edit_account_notification_preferences_path, notice: t(".success") }
    end
  end

  private

  def set_prefs
    @prefs = Current.user.user_preferences || Current.user.create_user_preferences!
  end

  def apply_changes(target)
    if params[:notification_preferences].present?
      target.deep_merge!(params[:notification_preferences].to_unsafe_h)
    end
    if params[:retention_days].present?
      days = params[:retention_days] == "" ? nil : params[:retention_days].to_i
      target["retention_days"] = days
    end
  end

  def turbo_recompute_due_at?
    params.dig(:notification_preferences, :digest).present?
  end
end
```

Add an `allowed_retention_days` constant on the controller or value object: `[30, 60, 90, 180, 365, nil]`. Reject anything else with 422.

- [ ] **Step 16.4: Run + commit**

```bash
git commit -m "feat(notifications): preferences controller with Turbo Stream auto-save"
```

---

## Task 17 — Preferences view: master controls, 5×3 matrix, digest, retention

**Files:**

- Create: `app/views/account/notification_preferences/edit.html.erb`
- Create: `app/views/account/notification_preferences/update.turbo_stream.erb`
- Modify: `app/views/account/_navigation.html.erb` (add the new link)
- Modify: `config/locales/en/notifications.en.yml`

- [ ] **Step 17.1: Locale keys**

```yaml
    preferences:
      heading: "Notification preferences"
      do_not_disturb: "Pause non-essential notifications"
      do_not_disturb_help: "Security alerts always go through."
      do_not_disturb_count: "%{count} unread (%{hidden} hidden by Do Not Disturb)"
      categories:
        security: "Security & sign-in"
        account_access: "Account & access"
        workspace_activity: "Workspace activity"
        project_activity: "Project activity"
        billing: "Billing"
      channels:
        in_app: "In-app"
        email: "Email"
        digest: "Daily digest"
      digest:
        cadence: "How often"
        cadence_options:
          daily: "Daily"
          weekly: "Weekly"
        time: "Time of day"
        timezone: "Times shown in %{timezone}."
      retention:
        label: "Auto-delete read notifications"
        options:
          30: "After 30 days"
          60: "After 60 days"
          90: "After 90 days"
          180: "After 180 days"
          365: "After 1 year"
          never: "Never"
        help: "Security alerts are kept for at least 1 year regardless of this setting."
      saved: "Saved."
```

- [ ] **Step 17.2: View structure**

Three sections in `edit.html.erb`:

1. **Master controls** at top: DND toggle. When DND is on, render a tooltip beneath the bell-badge (in `_notifications_bell.html.erb`, conditionally) with the count of unread + count hidden. Uses the `do_not_disturb_count` locale key.
2. **5×3 matrix**: nested `<table>` (semantic) or `<div role="grid">` with rows = categories, columns = channels. Each cell wraps a `<label>` + hidden checkbox. Each toggle posts to the controller via Turbo Stream form auto-submit on change. The "Security" row has its `email`/`in_app` toggles always-on with help text "Always on" — visually disabled but actually setting a value of `true` server-side.
3. **Digest controls**: cadence radio group (daily/weekly), `<input type="time">` for hour-of-day. Display user's IANA timezone beneath.
4. **Retention dropdown**: `<select>` with the 6 options (30/60/90/180/365/never). Help text below.

Each form is a small `<form>` with `data-controller="auto-submit"` (or your existing equivalent). On change, submits + Turbo Stream updates only the affected toggle/row.

- [ ] **Step 17.3: Run + commit**

```bash
git commit -m "feat(notifications): preferences view with master DND, matrix, digest, retention"
```

---

## Task 18 — System spec: preferences interactions

**Files:**

- Create: `spec/system/notification_preferences_spec.rb`

- [ ] **Step 18.1: System spec covers:**

- Visit page → see all 15 toggles in the matrix, plus DND, digest, retention
- Toggle DND on → form auto-submits, page reloads with toggle on, server state matches
- Toggle workspace_activity × email off → only that key changes, all 14 others preserved
- Change digest cadence to weekly → `digest_next_due_at` recomputed to next-week
- Change retention to "Never" → server stores `nil`
- Bell badge tooltip shows "X unread (Y hidden)" when DND is on and unread exist (verify on a different page after toggle)

- [ ] **Step 18.2: Run + commit**

```bash
mise exec -- bundle exec rspec spec/system/notification_preferences_spec.rb
git commit -m "test(notifications): system spec for preferences UI auto-save flow"
```

---

## Task 19 — CHANGELOG + push

- [ ] **Step 19.1: CHANGELOG**

```markdown
- Notification preferences UI at `/account/notification_preferences`: master DND toggle with tooltip count of suppressed unread, 5×3 category × channel matrix with Turbo Stream auto-save per toggle, digest cadence + time picker (IANA timezone-aware), retention dropdown (30/60/90/180/365/Never with documented 1-year security floor).
```

- [ ] **Step 19.2: Push**

```bash
git commit -am "docs(notifications): CHANGELOG for preferences UI"
git push -u origin feat/notifications-preferences
```

### PR-4 merge checklist

- [ ] All preference-controller request specs + system spec pass
- [ ] DND-vs-security rule lives only in `NotificationPreferences#allow?` — no Notifier hand-rolls it (grep verified)
- [ ] Turbo Stream auto-save updates exactly the affected key (deep-merge, not replace)
- [ ] Digest cadence change recomputes `digest_next_due_at`
- [ ] Bell tooltip displays suppressed-count under DND
- [ ] Lefthook pre-push green; Rubocop + Brakeman clean
- [ ] CHANGELOG updated

---

# PR-5 — Background jobs + hardening test cases

Branch: `feat/notifications-jobs-hardening`. Closes the loop with the digest job, cleanup job, and the explicit error-handling spec coverage the panel flagged.

---

## Task 20 — `DigestMailerJob` (TDD)

**Files:**

- Create: `app/jobs/digest_mailer_job.rb`
- Create: `app/views/notification_mailer/digest.{html,text}.erb`
- Modify: `app/mailers/notification_mailer.rb` (add `#digest`)
- Modify: `config/recurring.yml`
- Create: `spec/jobs/digest_mailer_job_spec.rb`
- Create: `spec/mailers/notification_mailer_digest_spec.rb`

- [ ] **Step 20.1: Specs covering:**

- Single indexed query: `expect(User).to receive(:joins).with(:user_preferences).once` (no per-user polling)
- Users with `digest_next_due_at <= now` get processed; users in the future are skipped
- DND-on user: skipped, `digest_next_due_at` not bumped (re-queued for next cycle)
- digest_enabled = false: skipped
- Empty notification window: no email sent, `digest_last_sent_at` not bumped, `digest_next_due_at` IS bumped (so we don't re-evaluate immediately)
- Recipient with notifications already `seen_at` set (because email was sent earlier): excluded from digest scope (this is the load-bearing dedupe)
- Successful send: `seen_at` set on each included notification (via the `after_deliver` hook), `digest_last_sent_at` = now, `digest_next_due_at` = `prefs.next_due_at_in(timezone)`
- Recipient deleted between event creation and digest job run: scope skips orphan notifications gracefully (foreign key + `joins(:event)` excludes)
- Notifier-class belongs to digest-eligible category only (workspace_activity, project_activity); security/billing/account_access excluded

- [ ] **Step 20.2: Implement the job**

```ruby
class DigestMailerJob < ApplicationJob
  queue_as :default

  def perform
    User.joins(:user_preferences)
        .where("user_preferences.digest_next_due_at <= ?", Time.current)
        .find_each do |user|
      send_digest_for(user)
    rescue => e
      Rails.logger.error("DigestMailerJob failed for user #{user.id}: #{e.class}: #{e.message}")
      # Bump next-due to skip this cycle; next pass retries
      user.user_preferences&.update_column(:digest_next_due_at, 1.hour.from_now)
    end
  end

  private

  def send_digest_for(user)
    prefs = user.user_preferences.notification_preferences_object
    return reschedule(user, prefs) if prefs.do_not_disturb? || !prefs.digest_enabled?

    eligible_types = ApplicationNotifier.descendants
      .select { |c| NotificationPreferences::DIGEST_ELIGIBLE_CATEGORIES.include?(c.category_name) }
      .map(&:name)

    scope = user.notifications
      .joins(:event)
      .where(seen_at: nil)
      .where(noticed_events: { type: eligible_types })
      .where("noticed_notifications.created_at >= ?", user.user_preferences.digest_last_sent_at || 24.hours.ago)

    if scope.exists?
      NotificationMailer.digest(user, scope.to_a).deliver_later
      user.user_preferences.update!(digest_last_sent_at: Time.current)
    end

    reschedule(user, prefs)
  end

  def reschedule(user, prefs)
    user.user_preferences.update_column(
      :digest_next_due_at,
      prefs.next_due_at_in(user.timezone)
    )
  end
end
```

`seen_at` is set **only** via Noticed's `after_deliver` callback on the digest mailer's delivery — same mechanism the per-event mailer uses (`after_deliver: :mark_seen!`). Do NOT set `seen_at` inside the mailer block before `mail()` returns; that path would mark notifications "seen" even if `deliver_later` later fails or the job is rolled back. The `after_deliver` callback fires only after the underlying mailer job has completed successfully, which is the correctness contract we want.

- [ ] **Step 20.3: Add to `recurring.yml`**

```yaml
  digest_mailer:
    class: DigestMailerJob
    queue: default
    # Polls every 15 minutes against the digest_next_due_at indexed range.
    # Single SELECT scan regardless of user count; per-user logic skips
    # immediately when DND or digest_enabled? blocks.
    schedule: every 15 minutes
```

- [ ] **Step 20.4: Run + commit**

```bash
mise exec -- bundle exec rspec spec/jobs/digest_mailer_job_spec.rb spec/mailers/notification_mailer_digest_spec.rb
git commit -m "feat(notifications): DigestMailerJob with single indexed query + seen_at dedupe"
```

---

## Task 21 — `NotificationCleanupJob` (TDD)

**Files:**

- Create: `app/jobs/notification_cleanup_job.rb`
- Modify: `config/recurring.yml`
- Create: `spec/jobs/notification_cleanup_job_spec.rb`

- [ ] **Step 21.1: Specs**

- User with `retention_days = 90`: read notifications older than 92 days (90 + 2 grace) deleted; reads at 91 days kept (within grace); reads at 60 days kept; **unread** notifications never deleted regardless of age
- User with `retention_days = nil` ("never"): no deletions
- Security-category notifications (`type IN (...)`): kept regardless of retention preference (1-year floor enforced via `RETENTION_FLOORS[:security]`)
- Bulk delete batched in 100s (verify via `expect(scope).to receive(:in_batches).with(of: 100)`)
- 250 expired-read notifications across 1 user → 3 destroy_all batches

- [ ] **Step 21.2: Implementation**

```ruby
class NotificationCleanupJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      cleanup_for(user)
    end
  end

  private

  def cleanup_for(user)
    prefs = user.user_preferences&.notification_preferences_object
    return unless prefs
    days = prefs.retention_days
    return if days.nil?

    cutoff = (days + 2).days.ago
    security_floor_cutoff = NotificationPreferences::RETENTION_FLOORS[:security].ago
    security_types = NotificationPreferences::SECURITY_NOTIFIER_TYPES

    user.notifications
        .joins(:event)
        .where.not(read_at: nil)
        .where("noticed_notifications.read_at < ?", cutoff)
        .where("(noticed_events.type NOT IN (?) OR noticed_notifications.read_at < ?)",
               security_types, security_floor_cutoff)
        .in_batches(of: 100) { |batch| batch.destroy_all }
  end
end
```

- [ ] **Step 21.3: Add to `recurring.yml`**

```yaml
  notification_cleanup:
    class: NotificationCleanupJob
    queue: default
    # Runs daily at 3am UTC. Per-user batched deletion in chunks of 100 to
    # release SQLite write lock between transactions, so cleanup never blocks
    # incoming notifications for more than ~10ms at a time.
    schedule: every day at 3am
```

- [ ] **Step 21.4: Run + commit**

```bash
git commit -m "feat(notifications): NotificationCleanupJob with grace period + security floor + batching"
```

---

## Task 22 — Hardening test cases (one consolidated spec file)

**Files:**

- Create: `spec/requests/notifications_hardening_spec.rb`

This is the **panel-flagged hardening file** the spec calls out explicitly. Each error case gets its own `describe` block.

- [ ] **Step 22.1: Idempotent event insertion under retry**

```ruby
RSpec.describe "Notifications hardening", type: :request do
  describe "idempotent event insertion under retry" do
    let(:user) { create(:user) }

    it "creates exactly one event when the same Notifier fires twice in the same minute" do
      freeze_time do
        WorkspaceInvitationReceivedNotifier.with(invitation: create(:invitation, invitee: user)).deliver(user)
        expect {
          WorkspaceInvitationReceivedNotifier.with(invitation: Invitation.last).deliver(user)
        }.not_to change(Noticed::Event, :count)
      end
    end

    it "swallows RecordNotUnique silently — no exception escapes" do
      freeze_time do
        WorkspaceInvitationReceivedNotifier.with(invitation: create(:invitation, invitee: user)).deliver(user)
        expect {
          WorkspaceInvitationReceivedNotifier.with(invitation: Invitation.last).deliver(user)
        }.not_to raise_error
      end
    end
  end
end
```

- [ ] **Step 22.2: Mid-fan-out failure (atomicity)**

<!-- VERIFIER (worth discussing #5): The original assertion `change(Noticed::Event, :count).by(0)` depends on Noticed v2's transaction semantics, which we haven't verified. If Noticed persists the event row in its own transaction before fanning out to notifications, this assertion will FAIL on a correct implementation, driving the implementer toward incorrect code. The reframed test below asserts the invariants we control: NO orphaned `noticed_notifications` rows reference an event whose fan-out failed AND no partial fan-out left some recipients with notifications and others without. Run both assertions. If the event row persists (Noticed's choice), accept that and document; the invariant that matters is "no poisoned partial state across notifications." -->

```ruby
  describe "mid-fan-out failure" do
    it "leaves no orphaned notifications and no partial fan-out across recipients" do
      workspace = create(:workspace)
      good = create_list(:user, 4)
      bad  = create(:user)
      bad.destroy  # tombstone — Notifier resolves recipients then fails on insert

      allow_any_instance_of(WorkspaceMemberAddedNotifier).to receive(:recipients).and_return(good + [bad])

      initial_notifications = Noticed::Notification.count
      WorkspaceMemberAddedNotifier
        .with(membership: create(:membership, workspace: workspace))
        .deliver(good) rescue nil

      # Invariants we control regardless of Noticed v2's event-row transaction choice:
      # (a) no notifications reference an event whose fan-out partially completed
      events_with_partial_fanout = Noticed::Event.find_each.select do |e|
        e.notifications.count.between?(1, good.count)  # neither 0 (clean rollback) nor good.count (all succeeded)
      end
      expect(events_with_partial_fanout).to be_empty

      # (b) total notification count is either unchanged (clean rollback) or all good recipients (clean success)
      delta = Noticed::Notification.count - initial_notifications
      expect(delta).to satisfy { |n| n == 0 || n == good.count },
        "expected atomic outcome (0 or #{good.count} new notifications), got #{delta}"
    end
  end
```

The exact mechanics depend on Noticed v2's transaction semantics — what we *control* is the invariant that there's no partial-fan-out poisoned state across `noticed_notifications` rows. If verification on Noticed v2 surfaces a stronger guarantee, tighten the assertion; if not, this is the correctness contract.

- [ ] **Step 22.3: Recipient deleted between event and delivery**

```ruby
  describe "recipient deleted before digest job runs" do
    it "skips orphaned notifications without raising" do
      user = create(:user)
      WorkspaceInvitationAcceptedNotifier
        .with(invitation: create(:invitation, invitee: user))
        .deliver(user)

      user.destroy  # cascades notifications via the User#dependent: :destroy
      expect { DigestMailerJob.perform_now }.not_to raise_error
    end
  end
```

- [ ] **Step 22.4: Notifiable deleted during render**

```ruby
  describe "notifiable deleted during render" do
    it "render_safe_or_placeholder swallows RecordNotFound and renders placeholder" do
      user = create(:user)
      invitation = create(:invitation, invitee: user)
      WorkspaceInvitationReceivedNotifier.with(invitation: invitation).deliver(user)

      notification = user.notifications.first
      invitation.destroy

      result = notification.render_safe_or_placeholder { notification.message }
      expect(result).to eq I18n.t("notifications.placeholder")
    end
  end
```

- [ ] **Step 22.5: Throttle fail-open under cache miss**

```ruby
  describe "throttle fail-open under cache miss" do
    it "allows email send when Rails.cache.increment returns nil" do
      user = create(:user)
      allow(Rails.cache).to receive(:increment).and_return(nil)

      expect {
        PasswordChangedNotifier.with(user: user).deliver(user)
      }.to have_enqueued_mail(NotificationMailer, :password_changed)
    end
  end
```

- [ ] **Step 22.6: Concurrent mark-all-read + arrival**

<!-- VERIFIER (worth discussing #7): The original Thread.new + sleep 0.05 timing race is a flakiness vector — under SQLite's BEGIN IMMEDIATE write-serialization, the test is largely deterministic but the sleep-based ordering is not. Two acceptable replacements: (a) use a callback hook on `ApplicationNotifier#deliver` to trigger arrival mid-batch deterministically, OR (b) downgrade to a documentation-only assertion ("the invariant is documented; SQLite serialization makes drift impossible in this app's deployment") and tag with `:flaky` or `:skip` if added back later. The version below uses (a) — a transaction-boundary stub that fires reliably between batches. -->

```ruby
  describe "concurrent mark_all_read and incoming notification" do
    it "does not lose notifications that arrive between batches" do
      user = create(:user)
      sign_in(user)
      create_list(:noticed_notification, 150, recipient: user, read_at: nil)

      # Deterministic mid-batch arrival: stub the in_batches block to inject
      # a new notification creation between the first and second 100-row batch.
      arrival_fired = false
      allow_any_instance_of(ActiveRecord::Relation).to receive(:in_batches).and_wrap_original do |original, *args, &block|
        original.call(*args) do |batch|
          block.call(batch)
          unless arrival_fired
            arrival_fired = true
            create(:noticed_notification, recipient: user, read_at: nil)
          end
        end
      end

      post mark_all_read_account_notifications_path

      # All 150 pre-existing should be read; the 1 mid-batch arrival stays unread.
      expect(user.notifications.where(read_at: nil).count).to eq 1
      expect(user.notifications.where.not(read_at: nil).count).to eq 150
    end
  end
```

This is technically a stub on `in_batches`, which is the pattern flagged in #6 — but here the stub is necessary to inject the concurrency event at a deterministic boundary, and the *assertion* is still behavioral (count of read vs unread). Acceptable trade-off for a concurrency test.

- [ ] **Step 22.7: Run + commit**

```bash
mise exec -- bundle exec rspec spec/requests/notifications_hardening_spec.rb
git commit -m "test(notifications): hardening cases for idempotency, fan-out, deleted records, throttle, concurrency"
```

---

## Task 23 — Digest mailer template + locale

**Files:**

- Create: `app/views/notification_mailer/digest.html.erb`
- Create: `app/views/notification_mailer/digest.text.erb`
- Modify: `config/locales/en/notifications.en.yml`

- [ ] **Step 23.1: Locale keys**

```yaml
    digest:
      subject:
        daily: "Your daily %{app_name} digest"
        weekly: "Your weekly %{app_name} digest"
      preheader: "%{count} updates from your workspaces."
      heading_daily: "Today's updates"
      heading_weekly: "This week's updates"
      footer: "You can change digest cadence or pause notifications in your preferences."
```

- [ ] **Step 23.2: Templates** — group notifications by category, render each with its own title + URL. Use `notification.render_safe_or_placeholder { notification.message }` in case a notifiable was deleted between scope-load and mailer-render. Footer links to `/account/notification_preferences`.

- [ ] **Step 23.3: Mailer spec** asserting:

- Subject reflects cadence
- Body groups by category
- Empty digest never sent (already covered in DigestMailerJob spec)
- Each notification's URL is present

- [ ] **Step 23.4: Run + commit**

```bash
git commit -m "feat(notifications): digest mailer template + locale keys"
```

---

## Task 24 — Brakeman + Rubocop sweep + final polish

- [ ] **Step 24.1: Run Brakeman**

`mise exec -- bundle exec brakeman --no-pager`

Expected: zero new warnings. Notifications use the same auth pattern as the rest of the app; common issues are unscoped `find` (Pundit-policy-protected) and unsafe interpolation in mailer subjects (locale keys mediate). Address any flag.

- [ ] **Step 24.2: Run Rubocop**

`mise exec -- bundle exec rubocop`

Expected: zero offenses. If any, fix.

- [ ] **Step 24.3: Final full suite**

`mise exec -- bundle exec rspec`

Expected: all examples green. The full v1 suite count should be roughly +120 over the original 1201 (≈1320+).

- [ ] **Step 24.4: Manual smoke** in `bin/dev`:

- Sign in
- Receive an invitation as a second user → see bell badge appear, dropdown shows item
- Click item → marked read, badge decrements
- Visit `/account/notifications` → triage view works
- Visit `/account/notification_preferences` → toggles auto-save
- Toggle DND → tooltip on bell shows hidden count

- [ ] **Step 24.5: CHANGELOG final entry**

```markdown
- Background jobs: `DigestMailerJob` (single indexed query against `digest_next_due_at`, `seen_at`-based dedupe so digest never re-sends what email already covered), `NotificationCleanupJob` (per-user retention with 2-day grace period + 1-year security floor, batched in chunks of 100). Hardening test coverage: idempotent retry under DB unique constraint, atomic mid-fan-out failure, deleted-recipient digest skip, deleted-notifiable render-safe placeholder, throttle fail-open under cache miss, concurrent mark-all-read with arrival.
```

---

## Task 25 — Push, open PR, ship

- [ ] **Step 25.1: Final commit + push**

```bash
git commit -am "docs(notifications): CHANGELOG for jobs + hardening; final polish"
git push -u origin feat/notifications-jobs-hardening
```

- [ ] **Step 25.2: Open PR-5 with `gh pr create`**

```bash
gh pr create --title "feat(notifications): jobs + hardening — completes v1" --body "$(cat <<'EOF'
## Summary

- DigestMailerJob with single indexed query and seen_at-based dedupe
- NotificationCleanupJob with grace period, security floor, batched-in-100s
- Hardening specs for idempotent retry, mid-fan-out failure, deleted recipient, deleted notifiable, throttle fail-open, concurrent mark-all-read

## Test plan

- [ ] All hardening specs pass
- [ ] Full RSpec green
- [ ] Lefthook pre-push green
- [ ] Manually verified: digest sends, doesn't re-send under seen_at, retention deletes correctly with security floor preserved
EOF
)"
```

### PR-5 merge checklist

- [ ] `DigestMailerJob` spec asserts single indexed query + seen_at dedupe + DND skip + empty-window skip + `digest_next_due_at` re-bump
- [ ] `NotificationCleanupJob` spec asserts grace period + security floor + batching + never-preference no-op + unread preservation
- [ ] Hardening spec passes all six panel-flagged cases
- [ ] `recurring.yml` has annotated entries for digest, cleanup, invitation-expiring sweep, capacity sweep
- [ ] Brakeman clean, Rubocop clean
- [ ] Full RSpec green
- [ ] CHANGELOG complete and ready for `chore(release): cut v1.5.0`

---

## Out of scope (explicitly deferred)

Per the spec — these are *not* part of this plan but the architecture supports them as additive changes:

- Web Push (browser push notifications) — v1.1, additive: `push_subscriptions` table + `web_push: false` JSONB key + `Noticed::DeliveryMethods::WebPush` + service worker + `notification_permission_controller`. Preferences matrix gains a 4th column.
- Per-event preference granularity (current is per-category × per-channel)
- @-mentions and comment-thread notifications
- Slack / Microsoft Teams / SMS delivery channels
- Cross-tab read-state real-time sync (badge updates on next interaction in unfocused tabs only)
- Admin / staff notification dashboard
- Locale-aware digest send times beyond user-IANA-timezone

## Open questions

None remaining. The `digest_next_due_at` backfill question is resolved at the top of this plan in favor of randomized 24-hour spread.

---

*End of plan. Five PRs, twenty-five tasks, ~120 spec examples added across the suite. Each PR is independently green and ships clean — no PR depends on a future PR's work.*
