# Notifications — Design Spec

**Goal:** Ship a notifications system that turns ModelRails from "real-time-broadcast app" into a "collaboration app that knows who needs to know what." Persistent per-user notifications with read/unread state, an in-app notification center, transactional email, and daily digest email — wired to events that exist in the app today (workspace invitations, member changes, role changes, project membership, security events, billing readiness). Per-user preferences gate every channel; sensible category-level defaults out of the box; the foundation extends cleanly when downstream apps want richer per-event control. Web Push is explicitly deferred to v1.1 — the architecture supports clean addition as a purely additive change.

**Scope:** Add the [`noticed` gem (v2)](https://github.com/excid3/noticed) for persistence + dispatch + channel routing. Build the user-facing surface ourselves: notification center dropdown in the user menu, dedicated `/account/notifications` page, preferences UI in the existing account-settings hub, daily-digest mailer. Ten Notifier classes for v1, each routing to in-app + (optionally) email + (optionally) digest per the channel matrix. Per-user preferences stored as jsonb on `UserPreferences`. AAA accessibility on all in-app surfaces. Retention controlled by user preference with a security-category override floor of one year. Idempotent event insertion + DB-level uniqueness baked in from day one.

---

## Motivation

ModelRails has shipped the **identity and organizational** layer of a multi-tenant SaaS — auth, workspaces, memberships, roles, projects, account hub, real-time `Broadcastable` updates — to AAA polish. What's missing is the **work-getting-done** layer that turns "user can sign into a workspace" into "user *does their job* in a workspace and trusts the system to keep them informed without overwhelming them."

The app already produces a stream of `ActivityLog` rows via the [`Trackable`](app/models/concerns/trackable.rb) concern (system audit) and broadcasts Turbo updates via [`Broadcastable`](app/models/concerns/broadcastable.rb) (real-time UI refresh). What it doesn't have is a **per-user, persistent, addressable** notification surface — a place where "Alice was invited to the Marketing workspace" lives until Alice acknowledges it, surviving page reloads and being delivered to her email if she's not currently in the app.

Without this layer:
- Inviters never learn that an invitation was accepted (the loop doesn't close).
- Members miss role/permission changes until the next time they bump into the limit.
- Workspace owners discover capacity limits only at "you can't add another member" time.
- Security events (password change, sign-in from new device) silently happen.
- The collaboration story stops at "you can broadcast in real time," which only helps if the user is actively looking.

A panel of three perspectives — Jason Fried (notification restraint, no badge anxiety), Adam Wathan (design-system fidelity, utility-first), Steve Schoger (subtle visual hierarchy, restrained color) — converged on a design with no aggressive motion, no sound, no alarm-red badges, read-on-click semantics, and a master "do not disturb" preference. The good news for accessibility: tasteful design is also the WCAG-compliant default. The Fried/Wathan/Schoger constraints map directly to WCAG 2.2.2 (Pause, Stop, Hide), 2.3.3 (Animation from Interactions), and 1.4.13 (Content on Hover or Focus).

---

## Non-Goals

- **Web Push (browser push notifications).** Deferred to v1.1. The Notifier framework supports a future `deliver_by :web_push` line; the preference JSONB shape supports an additive `web_push: false` key per category without breaking changes. We ship v1 with three channels (in-app, email, digest) and add Web Push cleanly later. Reasoning: complexity multiplication (VAPID, service worker, browser permission UX, cross-browser quirks, Safari iOS PWA-only constraint), testing burden (mock VAPID + mock browser push), orthogonal to the core value the other channels deliver. Panel consensus (4-of-4 reviewers + concurrency-safety endorsement): defer.
- **Mention/comment notifications.** Implies @-mentions and threaded comments, neither of which exist in the resource/document surface today. Deferred until that surface ships.
- **Slack / Microsoft Teams / SMS delivery channels.** Noticed supports these as additional `deliver_by` adapters, but they're not v1 — `:database`, `:email` are the two shipping delivery methods (in-app counts as `:database` + a Turbo Stream broadcast; digest is a scheduled query against `:database` rows).
- **Notification "boost" / reactions / per-notification threading.** Each notification is a one-shot row; no threading model.
- **Per-event preference granularity.** v1 is per-category × per-channel. Per-event toggles are a future expansion that this design accommodates without breaking changes.
- **Cross-workspace notification roll-up.** Users see notifications from every workspace they're a member of in one stream; there's no per-workspace notification center.
- **Real-time UI sync of read state across browser tabs.** Turbo Stream broadcasts the *count* on arrival; if the user marks something read in one tab, the other tab's badge won't decrement until next interaction. Acceptable for v1.
- **Replay / re-send a previously-sent notification.** No admin "redeliver" action.
- **Encrypted notification content at rest.** Standard Rails encryption for tokens etc. continues to apply, but notification bodies aren't encrypted. The privacy controls live at the access-control layer.

---

## Design decisions (locked during brainstorming)

| # | Decision | Choice | Reasoning |
| - | -------- | ------ | --------- |
| 1 | Persistence + dispatch library | `noticed ~> 2.5` | Battle-tested, GoRails-authored, multi-channel out of the box. Building this layer ourselves is months of bug surface for no marginal value. |
| 2 | UI library | None — built in-house | Where standards-bar lives. Tailwind UI patterns and existing design-token system. |
| 3 | Architecture | Trackable and Notifications are **independent registries** (parallel) | Different audiences, retention, schemas, access controls. Domain code fires both explicitly. |
| 4 | Preference granularity | Master DND + per-category × per-channel | Sensible defaults today, extensible to per-event later without breaking changes. |
| 5 | Read state | Read on click only; mark-as-unread supported; no read-on-dropdown-open | Avoids badge-anxiety dynamic; explicit user intent. |
| 6 | Placement | Dropdown in user menu (last 10 unread + 5 recent read) + dedicated `/account/notifications` page | Glance vs triage; one is not a clone of the other. |
| 7 | Digest cadence | Default on, opt-out via preferences, user-pickable cadence (daily/weekly), default daily, time-zone aware, digest-eligible content only | Calm-by-default with control. |
| 8 | Real-time arrival UX | Subtle visual change, no sound, no aggressive motion, `aria-live="polite"` for screen readers, master DND respected | Fried/Wathan/Schoger × WCAG 2.2.2 / 2.3.3. |
| 9 | Cleanup retention | User-controllable (30/60/90/180/365/never), default 90 days for read & indefinite for unread, security category retention floor of 1 year | User control with safe floors. |
| 10 | Web Push | **Deferred to v1.1** | Panel consensus (4-of-4 reviewers): orthogonal to core value, complexity multiplication, additive in v1.1. Cleanly absent from v1 schema and UI; v1.1 adds as `web_push: false` JSONB key + `push_subscriptions` table + new `deliver_by :web_push` per Notifier. |
| 11 | Trackable relationship | Independent — fired separately by domain code | See decision 3. |
| 12 | Idempotency on event insertion | Dedicated `idempotency_key` string column on `noticed_events` + partial unique index `(idempotency_key) WHERE idempotency_key IS NOT NULL` + automatic key populated by `ApplicationNotifier#before_create`. `ApplicationNotifier#deliver` returns sentinel `:delivered` or `:deduplicated`. No app-level SELECT fast-path. Schema stays on `schema_format = :ruby`. Key format: `"#{notifier_class}_#{record.id}_#{Time.current.to_i / 60}"`. | **Revised after 5-reviewer panel re-evaluation** (Aaron Patterson + Chris Oliver + DHH + Dave Thomas + Sandi Metz unanimous on the revised design). Original design placed the key in `params` JSONB and indexed via `json_extract` expression — required `schema_format = :sql` and hit SQLite's NULL-in-unique-index quirk. Column-based design is plain Rails DSL, schema.rb stays canonical, partial index fires atomically under concurrent dispatch (verified via `BEGIN IMMEDIATE` lock progression), forks inherit standard Rails knowledge. Sentinel return contract honors tell-don't-ask (Dave Thomas) — callers distinguish first-send from race-suppression. DB unique constraint is the atomic source of truth; `RecordNotUnique` rescue is the real backstop (Aaron Patterson; all five reviewers concur). |
| 13 | Sign-in fingerprint heuristic | SHA-256 of `User-Agent + OS` (no IP). Stored as `User#last_known_browsers` JSONB array of `{ digest:, first_seen_at:, last_seen_at: }` | IP rotates on mobile / VPN / coffee shop, causing false positives. UA + OS catches genuinely new devices. Mobile UA changes infrequently enough to not flood. Iterate on user feedback if false-positive rate is high. |

---

## Architecture overview

Three layers, with the `noticed` gem providing the middle layer:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Domain code (controllers, model callbacks, jobs)                    │
│   - explicitly invokes a Notifier class when an event happens       │
│   - separately writes ActivityLog rows via the Trackable concern    │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Noticed (gem)                                                       │
│   - persists noticed_events + noticed_notifications                 │
│   - resolves recipients (per-Notifier `recipients` method)          │
│   - applies per-channel `if:` conditionals (preferences gate)       │
│   - dedicated idempotency_key column + partial unique index        │
│     enforces atomic dedup on noticed_events under concurrent        │
│     dispatch; ApplicationNotifier#deliver returns :delivered or    │
│     :deduplicated sentinel                                         │
│   - fans out to delivery methods:                                   │
│       :database     → noticed_notifications row created             │
│       :email        → ActionMailer dispatch (sets seen_at to        │
│                       suppress digest re-send)                      │
│       :action_cable → broadcast_refresh_to user (in-app real-time)  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Our user-facing surfaces                                            │
│   - notification center dropdown (user menu Turbo Frame)            │
│   - /account/notifications page (full triage view)                  │
│   - /account/notification_preferences (preferences UI)              │
│   - daily/weekly digest mailer (Solid Queue scheduled job;          │
│     indexed query against denormalized next_due_at)                 │
└─────────────────────────────────────────────────────────────────────┘
```

### Why parallel Trackable + Notifications, not source-of-truth

Activity log records **system facts** ("what happened, who did it, on what"). Notifications are **direct messages to specific people** ("you should see this"). Different audiences (admin vs user), different retention (audit-forever vs user-cleanable), different schemas (actor+action+target vs recipient+type+payload), different access controls (workspace-scoped audit vs user-private). The savings from coupling them ("while we're here, also dispatch") are an illusion that trades explicit-but-correct for implicit-but-tangled. Domain code creates both; they share nothing except being triggered by the same domain action.

Concretely, a `WorkspaceMember` controller's `create` action does:

```ruby
membership = workspace.memberships.create!(user: invited_user, role: role)
# Trackable concern's after_commit fires: ActivityLog row created
WorkspaceMemberAddedNotifier
  .with(membership: membership, actor: Current.user)
  .deliver(invited_user)
```

The Notifier's `recipients` method may resolve to multiple users (e.g., notify all workspace owners that capacity is approaching); ActivityLog stays single-row.

---

## Schema changes

### From `noticed` (gem-provided migration, then locally hardened)

Two tables generated by `bin/rails noticed:install:migrations`, then a follow-up migration applies our hardening (indexes + constraints):

**`noticed_events`** — one row per event occurrence:
- `id`, `type` (Notifier class name), `params` (jsonb), `created_at`, `updated_at`
- `record_id`, `record_type` (polymorphic, nullable — the source record)
- `idempotency_key` (string, nullable) — added by our hardening migration. First-class column, not buried in `params` JSONB. Backfill block in the migration populates the column from `params['idempotency_key']` for any pre-existing rows so forks pulling this PR don't lose dedup history.

**Hardening:**
- **Add idempotency_key column**: `add_column :noticed_events, :idempotency_key, :string`
- **Partial unique index** (atomic dedup; fires under concurrent dispatch via SQLite `BEGIN IMMEDIATE` lock progression):
  `add_index :noticed_events, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL", name: "index_noticed_events_on_idempotency_key"`
- The column is auto-populated by `ApplicationNotifier#before_create` as `"#{notifier_class}_#{record.try(:id)}_#{Time.current.to_i / 60}"` (or a domain-supplied value when provided). Retried jobs and concurrent dispatches hitting the same key in the same minute are deduped atomically at the DB level. The partial WHERE clause means events created without a key (rare; signals an opt-out) bypass the constraint.
- **Why a column instead of `json_extract(params, '$.idempotency_key')`**: a regular column + plain Rails DSL keeps `schema.rb` canonical (no `schema_format = :sql` switch), avoids SQLite's NULL-in-unique-index quirk, and presents the dedup mechanism as a first-class concept rather than buried in metadata. Forks see standard Rails — no expression-index knowledge required. See Decision #12 reasoning for the full panel re-evaluation.

**`noticed_notifications`** — one row per recipient:
- `id`, `type` (Notification class), `event_id` (FK to noticed_events with `on_delete: :cascade`)
- `recipient_id`, `recipient_type` (polymorphic; v1 always `User`)
- `read_at`, `seen_at` (nullable)
- `created_at`, `updated_at`

**Hardening:**
- **Partial index on unread queries** (the hot path):
  `add_index :noticed_notifications, [:recipient_type, :recipient_id], where: "read_at IS NULL", name: "index_noticed_notifications_unread"`
- **Cascade FK** on `event_id` (backstops gem-provided FK, ensures cleanup):
  `add_foreign_key :noticed_notifications, :noticed_events, column: :event_id, on_delete: :cascade`
- **Check constraint enforcing seen-before-read ordering** (logical invariant — if a notification was emailed, then the user reads it, `read_at >= seen_at`):
  `add_check_constraint :noticed_notifications, "seen_at IS NULL OR read_at IS NULL OR read_at >= seen_at", name: "seen_before_read"`
- **Check constraint enforcing v1 polymorphic scope** (documents the User-only-in-v1 commitment, prevents accidental polymorphic inserts; dropped when v1 expands):
  `add_check_constraint :noticed_notifications, "recipient_type = 'User'", name: "recipient_type_user_only_v1"`

### Modified: `user_preferences`

Add two columns:

**`notification_preferences` jsonb** with default:

```ruby
{
  "do_not_disturb": false,
  "digest": { "enabled": true, "cadence": "daily", "hour_local": 8 },
  "categories": {
    "security":           { "in_app": true,  "email": true,  "digest": false },
    "account_access":     { "in_app": true,  "email": true,  "digest": false },
    "workspace_activity": { "in_app": true,  "email": false, "digest": true  },
    "project_activity":   { "in_app": true,  "email": false, "digest": true  },
    "billing":            { "in_app": true,  "email": true,  "digest": false }
  },
  "retention_days": 90
}
```

`do_not_disturb: true` suspends all delivery *except* the `security` category. Cadence options: `daily`, `weekly`. Retention options: `30 / 60 / 90 / 180 / 365 / null` (null = never auto-delete). Note: `web_push` keys are deliberately absent from v1; v1.1 adds them as a non-breaking additive change (existing rows resolve missing key to `false` via `.dig` defaults handled by the value object).

**`digest_next_due_at` timestamp** (denormalized for efficient digest job querying — Aaron's hardening). Maintained by the digest job: when a digest sends, `digest_next_due_at` is bumped to the next scheduled time per cadence + IANA timezone. The job query becomes a single indexed range scan rather than per-user polling:

```ruby
add_index :user_preferences, :digest_next_due_at, where: "digest_next_due_at IS NOT NULL"
```

### Strongly-typed wrapper: `NotificationPreferences` value object

Wraps the `notification_preferences` jsonb column. Resolves missing keys to defaults safely (handles forward/back-compat as categories or channels are added). Centralizes the DND-vs-security rule. Single point of truth for the `DIGEST_ELIGIBLE_CATEGORIES` constant.

```ruby
class NotificationPreferences
  CATEGORIES = %w[security account_access workspace_activity project_activity billing].freeze
  CHANNELS = %w[in_app email digest].freeze
  SECURITY_CATEGORY = "security"
  DIGEST_ELIGIBLE_CATEGORIES = %w[workspace_activity project_activity].freeze
  RETENTION_FLOORS = { security: 365.days }.freeze

  def initialize(jsonb_hash)
    @data = jsonb_hash || {}
  end

  def allow?(category:, channel:)
    return false unless valid?(category, channel)
    return true if category == SECURITY_CATEGORY  # security bypasses DND
    return false if do_not_disturb?
    @data.dig("categories", category, channel) == true
  end

  def do_not_disturb?  = @data["do_not_disturb"] == true
  def digest_enabled?  = @data.dig("digest", "enabled") != false
  def digest_cadence   = @data.dig("digest", "cadence") || "daily"
  def retention_days   = @data["retention_days"]
  # ...
end
```

This is the wrapper Chris O. flagged as needed: callers never reach into raw jsonb, missing keys never produce nil-related footguns.

---

## v1 event catalog

Ten Notifier classes, named by domain event. Channel routing column shows defaults; users override per-category in preferences.

| # | Notifier | Trigger | Recipients | Category | In-app | Email | Digest |
|---|---|---|---|---|---|---|---|
| 1 | `WorkspaceInvitationReceivedNotifier` | `Invitation` created targeting workspace | invitee | account_access | ✓ | ✓ | — |
| 2 | `WorkspaceInvitationAcceptedNotifier` | invitee accepts | inviter | workspace_activity | ✓ | — | ✓ |
| 3 | `WorkspaceInvitationDeclinedNotifier` | invitee declines | inviter | workspace_activity | ✓ | — | ✓ |
| 4 | `WorkspaceInvitationExpiringSoonNotifier` | scheduled job (≤24h to expiry) | invitee | account_access | ✓ | ✓ | — |
| 5 | `WorkspaceMemberAddedNotifier` | membership created (non-invitation path) | added user, all owners | workspace_activity (added) / digest (owners) | ✓ | ✓ added / — owners | ✓ owners |
| 6 | `WorkspaceRoleChangedNotifier` | membership.role changed | the user whose role changed | account_access | ✓ | ✓ | — |
| 7 | `ProjectMembershipChangedNotifier` | project_membership created/role-changed | added/changed user | project_activity | ✓ | — | ✓ |
| 8 | `WorkspaceCapacityApproachingNotifier` | scheduled job (≥80% of `max_members` or `max_projects`) | all owners | billing | ✓ | ✓ | — |
| 9 | `SignInFromNewDeviceNotifier` | session created from new device fingerprint (UA+OS hash not in `User#last_known_browsers`) | the user signing in | security | ✓ | ✓ | — |
| 10 | `PasswordChangedNotifier` | `User#update` succeeds with `password_digest_changed?` | the user | security | ✓ | ✓ | — |

**Deliberately deferred** (mentioned because they came up; out of v1 scope):
- Account suspended / restored — implies admin/staff back-office surface, separate spec.
- Plan / billing change — implies billing integration, separate spec.
- OAuth verification pending reminder — small enough to fold in once the email schedule is settled, but explicitly *not v1* to keep the deliverable scoped.
- Email change confirmed (to old address) — covered by existing `email_change_notification` mailer; will fold into Notifier framework when we touch that mailer next.

---

## Notifier class pattern

Each Notifier inherits from `ApplicationNotifier` (which we add). Common pattern:

```ruby
class WorkspaceInvitationReceivedNotifier < ApplicationNotifier
  category :account_access

  deliver_by :database
  deliver_by :action_cable, format: :badge_update_payload,
                            if: -> { recipient_pref(:in_app) }
  deliver_by :email, mailer: "NotificationMailer",
                     method: :workspace_invitation_received,
                     if: -> { recipient_pref(:email) },
                     after_deliver: :mark_seen!  # suppresses digest re-send

  required_param :invitation

  def url
    invitation_path(token: params[:invitation].token)
  end

  def message
    I18n.t("notifications.workspace_invitation_received.message",
           locale: recipient_locale,
           inviter: params[:invitation].invited_by.first_name,
           workspace: params[:invitation].invitable.name)
  end
end
```

`ApplicationNotifier` adds:

- **Automatic idempotency key in dedicated column**. On `before_create` of the underlying `noticed_events` row, populates the `idempotency_key` *column* (not `params` JSONB) as `"#{self.class.name}_#{record.try(:id) || record.try(:to_gid_param)}_#{Time.current.to_i / 60}"` (one-minute bucket) unless a domain-supplied key is already set on the column. If neither record nor explicit key is present, raise `ArgumentError` (loud failure beats silent dedup-collapse across distinct events). Combined with the partial unique index `(idempotency_key) WHERE idempotency_key IS NOT NULL`, retried jobs and concurrent dispatches hitting the same key in the same minute dedupe atomically at the DB level via SQLite's `BEGIN IMMEDIATE` lock progression.
- **Sentinel return contract on `deliver`**. `ApplicationNotifier#deliver` returns `:delivered` on first-send (the row inserted) and `:deduplicated` on `RecordNotUnique` rescue (a concurrent or retried call won the race). Callers can distinguish the two outcomes without re-querying. No silent self-return. No app-level SELECT-then-INSERT fast-path: the DB constraint is the atomic source of truth, the rescue is the real backstop.
- `category(name)` — class macro that registers the category. Resolution centralizes in `NotificationPreferences#allow?(category:, channel:)`, which handles the DND-vs-security rule.
- `recipient_pref(channel)` — instance method that delegates to `recipient.user_preferences.notification_preferences_object.allow?(category: self.class.category_name, channel: channel)`. No raw jsonb access in callers.
- `recipient_locale` — instance method returning `recipient.locale || I18n.default_locale`. Used in `message` and `url` rendering so digest mailers send in the user's language.
- `mark_seen!` — `after_deliver` hook for the email channel. Sets `seen_at: Time.current` on the underlying `noticed_notifications` row so the digest job's `where(seen_at: nil)` filter excludes it (no double-delivery via email + digest).
- Default `deliver_by :database` always (in-app baseline; not gated by per-channel preferences — DND is the master kill-switch and is handled at `recipient_pref(:in_app)` for the `:action_cable` broadcast).
- Throttle gate: each `deliver_by :email` runs through `EmailRecipientThrottle` (re-using existing `app/lib/email_recipient_throttle.rb`) keyed on `kind: "notification_#{notifier_class.name.underscore}"`. Caps at 3/hour per recipient per Notifier-class — same default as auth verification mails.

### Notifier render-safe pattern (deleted notifiables)

When a notification's `notifiable` (the source record — invitation, project, workspace) is destroyed, the notification cascades-deletes via `dependent: :destroy` on the polymorphic association. But during the small window between record deletion and `after_destroy_commit` cascade, the notification's render path may attempt to dereference a missing record. `ApplicationNotifier` exposes:

```ruby
def render_safe_or_placeholder(&block)
  yield
rescue ActiveRecord::RecordNotFound, NoMethodError
  Rails.logger.info("Notification #{id} references deleted record; rendering placeholder")
  I18n.t("notifications.placeholder")
end
```

Used in views: `<%= notification.render_safe_or_placeholder { notification.message } %>`. Test case in the integration suite verifies that a notification whose notifiable is destroyed mid-request renders the placeholder rather than raising.

---

## User-facing surfaces

### Notification center dropdown

Location: existing user-menu `Turbo::Frame` in [app/views/shared/_user_menu.html.erb](app/views/shared/_user_menu.html.erb). Add a new sibling frame `notifications_dropdown` containing:

- **Trigger button** in the header rail: bell icon, with a small unread badge (no count if 0; "1"–"9"; "10+" for any count ≥10). Badge color: `--color-info` (existing token), never `--color-danger` for routine notifications. Security-category notifications when present nudge the badge to `--color-warning`.
- **Panel** on click: `role="region"` (not `role="menu"` — it's a content panel, not an action menu — this is Léonie W.'s call), aria-labelled by the panel heading. Width 384px desktop, full-width mobile sheet pattern.
- **Heading**: "Notifications" + small "See all →" link (right-aligned). Below: a stack of last 10 unread + 5 most recent read, in chronological order newest first.
- **Each item**: icon (category-themed), title (1 line, truncated), preview (1 line, muted), relative timestamp, unread dot indicator. Clicking the item marks it read AND navigates to its URL.
- **Empty state**: "You're all caught up." with the muted accent color; no other CTA.
- **Keyboard**: `Cmd/Ctrl + Shift + N` toggles open/close. When open: `Tab` moves into the panel, arrow keys navigate items, `Enter` activates, `Escape` closes and returns focus to the trigger.

Real-time arrival: a Turbo Stream broadcasts to `[user, :notifications]` on each new `noticed_notifications` row; the dropdown frame morph-refreshes. Badge count updates automatically. A hidden `aria-live="polite"` region in the layout announces "1 new notification" (or "3 new notifications" on a burst).

### Dedicated `/account/notifications` page

Routes:

```
resources :notifications, only: [:index, :update, :destroy], controller: "account/notifications"
post   "notifications/mark_all_read"  => "account/notifications#mark_all_read"
delete "notifications/destroy_all_read" => "account/notifications#destroy_all_read"
```

View:
- Filter chips at top: All / Unread / by category (Security / Access / Workspace / Project / Billing).
- List with pagy pagination (already in Gemfile).
- Each row: same layout as dropdown but with full preview (3 lines) and explicit per-row "Mark unread" / "Delete" controls.
- Bulk actions: "Mark all as read" and "Delete all read" (each gated by confirmation modal — uses existing modal system).
- Empty state per filter (different copy for "All caught up" vs "No security notifications"). Schoger: empty states matter, design them deliberately.

### Preferences UI

New panel on `account/profiles#edit` (or a sibling page if we want it dedicated — TBD during implementation, leaning sibling page for clarity). UI structure:

- **Master controls** (top):
  - Toggle: "Pause non-essential notifications (Do Not Disturb)" — single switch, with help text "Security alerts always go through."
  - When DND is on and unread notifications exist, the bell badge tooltip reads "X unread (Y hidden by Do Not Disturb)" — Chris O.'s recommended UX hint so users don't lose track of suppressed activity.

- **Category × channel matrix**: 5 categories × 3 channels = 15 toggles in a grid. Headers: In-app / Email / Daily digest. Rows are categories. Each cell is a small toggle with a label-for relationship to a hidden checkbox for screen-reader accessibility. Saving uses Turbo Stream auto-save on each change (no Submit button — feels modern and matches Basecamp's pattern). v1.1 will add a fourth "Browser" column when Web Push ships; the matrix layout is designed to accommodate the addition cleanly.

- **Digest controls**: cadence picker (daily / weekly), time-of-day picker (defaults to 8am). All times displayed and stored in the user's IANA timezone (already on `User`).

- **Retention**: dropdown "Auto-delete read notifications after [30 / 60 / 90 / 180 / 365 / Never]". Below in muted text: "Security alerts are kept for at least 1 year regardless of this setting."

### Daily / weekly digest mailer

Solid Queue scheduled job: `DigestMailerJob`. Runs every 15 minutes (via `recurring.yml`). Aaron P.'s hardening: **single indexed query, not per-user polling.**

```ruby
# Single range scan against the indexed digest_next_due_at column;
# zero N+1 risk regardless of user count.
User.joins(:user_preferences)
    .where("user_preferences.digest_next_due_at <= ?", Time.current)
    .find_each do |user|
  prefs = user.user_preferences.notification_preferences_object
  next if prefs.do_not_disturb?
  next unless prefs.digest_enabled?

  scope = Noticed::Notification
    .where(recipient: user, seen_at: nil)
    .joins(:event)
    .where(noticed_events: {
      type: NotificationPreferences::DIGEST_ELIGIBLE_CATEGORIES.flat_map { |c| Notifier.classes_in_category(c) }
    })
    .where("noticed_notifications.created_at >= ?", user.user_preferences.digest_last_sent_at || 24.hours.ago)

  next if scope.none?

  NotificationMailer.digest(user, scope.to_a).deliver_later
  user.user_preferences.update!(
    digest_last_sent_at: Time.current,
    digest_next_due_at: prefs.next_due_at_in(user.timezone)
  )
end
```

Notes:

- Mailer dispatch sets `seen_at` on each included notification (via `after_deliver` callback on the Noticed event), suppressing the notification from a future digest. Closes Chris O.'s digest-dedupe gap.
- Empty windows skip silently — no empty digests sent.
- DND enabled → no digest sends.
- The `digest_last_sent_at` and `digest_next_due_at` columns on `user_preferences` are maintained by this job; they replace per-user polling with an indexed range scan.

---

## Accessibility patterns

Per Léonie W. + Fried/Wathan/Schoger convergence:

- **Live region**: hidden `<div id="notifications-live" aria-live="polite" aria-atomic="true"></div>` in the application layout. On Turbo Stream broadcast, the morph updates this region's text to e.g. "1 new notification" — screen readers announce it without interrupting current speech.
- **Focus management**: dropdown open moves focus to the panel heading; `Escape` returns focus to the trigger. Panel uses focus-trap pattern only when the content is scrolled past the trigger; otherwise focus simply moves naturally.
- **Reduced motion**: respect `prefers-reduced-motion: reduce` — no fade animations on badge change, no slide-in on dropdown open. Just appears.
- **High contrast**: badge color uses existing AAA-contrast tokens. `--color-info` and `--color-warning` are both AAA-passed in light and dark per the v1.4.0 contrast pass.
- **Keyboard parity**: every action available via mouse is available via keyboard. No hover-only affordances.
- **Touch targets**: 44×44 minimum on every interactive control (existing `.btn-touch-target` utility).
- **Screen reader narrative**: each notification item reads as "Unread. [type]. [message]. [time]." — verb labels included so the SR user gets context.

---

## Retention and cleanup

User preference column `retention_days` controls auto-deletion of *read* notifications. Default 90 days — covers one billing cycle plus a buffer for follow-ups; documented as the rationale so forks can adjust deliberately. A daily Solid Queue job `NotificationCleanupJob`:

```ruby
def perform
  User.find_each do |user|
    prefs = user.user_preferences.notification_preferences_object
    days = prefs.retention_days
    next if days.nil?  # "never" — skip

    # Aaron's hardening: grace period (days + 2) gives the UI a buffer
    # so paginated reads don't race with cleanup deletions. Batched in
    # chunks of 100 so each transaction holds the SQLite write lock for
    # ~10ms instead of multi-second blocks against incoming notifications.
    Noticed::Notification
      .where(recipient: user)
      .where.not(read_at: nil)
      .where("read_at < ?", (days + 2).days.ago)
      .where.not(type: NotificationPreferences::SECURITY_NOTIFIER_TYPES)
      .in_batches(of: 100) { |batch| batch.destroy_all }
  end
end
```

Security floor: types in the `security` category (`SignInFromNewDeviceNotifier`, `PasswordChangedNotifier`, plus future security additions) are kept at least 365 days regardless of user preference. Justification surfaced in the preferences UI ("Security alerts kept for at least 1 year").

Unread notifications never auto-delete (preserves the "I was supposed to do something" semantic).

### Bulk operations on `/account/notifications` page

"Mark all as read" and "Delete all read" controls. Both batched in chunks of 100, each chunk in its own transaction, releasing the SQLite write lock between batches. The user-facing trade-off (the action takes a few hundred ms instead of 50ms for a 500-row case) is preferable to multi-second lock holds blocking concurrent notification creation, sign-ins, and other writes:

```ruby
def mark_all_read
  Current.user.notifications
    .where(read_at: nil)
    .in_batches(of: 100) { |batch| batch.update_all(read_at: Time.current) }
  redirect_to account_notifications_path, notice: t(".success")
end
```

Same pattern for `destroy_all_read`.

When a notifiable record is destroyed (workspace deleted, project deleted, etc.), notifications referencing it cascade-delete via `dependent: :destroy` declared on the polymorphic `notifiable` reverse association. We accept that "Alice mentioned you in [deleted]" disappears from history — preferable to retaining stale links.

When a `User` is destroyed:
- Notifications *to* that user are cascade-deleted.
- Notifications generated *by* that user's actions to other recipients are anonymized — the actor reference is nulled, copy renders as "Someone" instead of the user's name. The notification's underlying record (e.g., the `Membership` row) was already cleaned up by separate cascade rules.

---

## Security and privacy

- **No free-form user content in notification params.** Store IDs and re-fetch on render. Rendering goes through normal Rails autoescape; XSS surface is the same as anywhere else.
- **Authorization on click.** Clicking a notification navigates to the source URL, which performs its own Pundit check. A user removed from a workspace before clicking an old workspace notification gets a redirect, not a 200.
- **Cross-tenant leakage**: notifications include `notifiable_type` + `notifiable_id` but never copy fields from the notifiable into the notification's `params`. If access changes, the notification's render path either re-fetches (and authorizes) or shows a placeholder.
- **PII in payloads**: the actor's name and the workspace name are stored in `params` as denormalized strings (so the notification renders correctly even if the user changes their name later). This is a deliberate trade-off — the alternative is re-fetching every name on every render. Anonymization on user-deletion (above) covers the residual privacy concern.
- **Email throttle**: every `deliver_by :email` runs through `EmailRecipientThrottle` keyed by Notifier class, capped at 3/hour per recipient per type. Closes the "attacker triggers a notification flood" surface.
- **GDPR data export** must include the user's notifications. GDPR right-to-erasure: account deletion purges (above).
- **Audit trail consideration**: `ActivityLog` continues to be the audit-of-record for "what happened" — notifications are user-facing-deletable, ActivityLog rows persist. Investigators look at ActivityLog.

---

## Test strategy

**Unit specs:**

- `NotificationPreferences` value object (`spec/lib/notification_preferences_spec.rb`): `allow?` resolution under default state, missing-key fallback, DND-suppresses-non-security, DND-bypasses-security, malformed jsonb tolerance.
- `ApplicationNotifier` (`spec/notifiers/application_notifier_spec.rb`): category macro, `recipient_pref` resolution, DND override semantics, security-category bypass, automatic idempotency-key population, `recipient_locale` selection, `mark_seen!` after-deliver hook, `render_safe_or_placeholder` swallows `RecordNotFound`.
- Each Notifier class: recipient resolution, channel routing (which `deliver_by` fires under which preference state), URL/message rendering across locales.
- `NotificationMailer#digest` (`spec/mailers/notification_mailer_spec.rb`): empty-window no-send, multi-category grouping, time-zone-aware window resolution, locale matches recipient.
- `NotificationCleanupJob` (`spec/jobs/notification_cleanup_job_spec.rb`): retention enforcement per user, grace-period (`days + 2`) honored, security-category floor, unread preservation, "never" preference no-op, batched in chunks of 100.
- `DigestMailerJob` (`spec/jobs/digest_mailer_job_spec.rb`): single indexed query (no per-user `find_each` polling), DND suppression, empty-window skip, dedupe via `seen_at` (notifications already emailed are excluded), `digest_next_due_at` correctly bumped post-send.

**Integration specs:**

- For each v1 event: trigger the domain action, assert correct Notifier(s) fired, correct recipients, correct channels enabled per default preference, correct copy in resulting `noticed_notifications` rows.
- Notification center dropdown: arrival broadcasts, mark-read on click, mark-unread, "See all" navigation.
- Preferences page: each toggle persists, DND suppresses correct categories, retention dropdown updates the column, DND tooltip displays "X unread (Y hidden)" count.
- Bulk operations: "Mark all as read" with 250+ notifications batches in chunks of 100; "Delete all read" same.

**Error-handling and concurrency specs** (the hardening cases the panel flagged):

- **Idempotent event insertion under retry (sentinel contract)**: same Notifier called twice in the same minute returns `:delivered` on the first call and `:deduplicated` on the second. Exactly one `noticed_events` row exists post-test. DB-level partial unique index on `idempotency_key` backs the test — the second insert raises `RecordNotUnique` which `ApplicationNotifier` rescues to `:deduplicated`. (Note: previous spec language said "swallowed silently"; the revised contract returns the explicit sentinel, callers can branch on the outcome.)
- **Concurrent dispatch + recipient fan-out resolution** (Chris Oliver edge case): two dispatches for the same `(notifier_class, record, minute-bucket)` race; one wins the INSERT, the other rescues `RecordNotUnique`. Assert: both calls' recipients receive their `noticed_notifications` rows linked to the **single** event row that won (no orphan event_ids, no nil-FK fan-out). Verify Noticed v2's behavior here directly — if it doesn't natively resolve to the existing event, `ApplicationNotifier` re-queries by `idempotency_key` and uses that row for fan-out.
- **Mid-fan-out failure**: simulate `noticed_notifications` insertion failing for recipient #4 of 10 (e.g., recipient destroyed mid-transaction). Assert: event row + completed notifications either commit atomically or roll back atomically — no poisoned partial state.
- **Recipient deleted between event and delivery**: invitation Notifier fires; user account deleted before the digest job runs the next morning. Assert: digest query skips the orphaned notification (or render-safe placeholder applies) without raising.
- **Notifiable deleted during render**: notification references a workspace that gets destroyed mid-request. Assert: `render_safe_or_placeholder` swallows the `RecordNotFound`, renders the placeholder copy, logs at info level.
- **Throttle fail-open under cache miss**: `Rails.cache.increment` returns `nil`; assert email delivery proceeds (fail-open is the documented choice; degraded throttle > dropped mail).
- **Concurrent `mark_all_read` and incoming notification**: bulk update doesn't lose newly-arrived unread notifications mid-batch.

**System specs (Capybara + Playwright):**

- Happy path: receive an invitation → see badge appear → click bell → see notification → click → land on invitation page.
- Accessibility audit: dropdown with notifications open passes axe-core at `wcag2aaa`. Live-region announcements verified via Playwright.
- Reduced-motion: `prefers-reduced-motion: reduce` set, animations don't fire.
- Keyboard-only: full notification center flow without mouse.

---

## Locale keys

New top-level namespace `notifications` in `config/locales/en/notifications.en.yml`:

```yaml
en:
  notifications:
    bell:
      label: "Notifications"
      unread_count: "%{count} unread"
      unread_with_dnd: "%{count} unread (%{hidden} hidden by Do Not Disturb)"
      see_all: "See all notifications"
      empty: "You're all caught up."
    placeholder: "This notification refers to something that no longer exists."
    workspace_invitation_received:
      title: "%{inviter} invited you to %{workspace}"
      preview: "Click to review the invitation."
    workspace_invitation_accepted: …
    # ... one block per Notifier
    digest:
      subject: "Your %{cadence} ModelRails digest"
      preheader: "%{count} updates from your workspaces."
      empty: ""  # never sent if empty
    preferences:
      heading: "Notification preferences"
      do_not_disturb: "Pause non-essential notifications"
      do_not_disturb_help: "Security alerts always go through."
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
      retention_help: "Security alerts kept for at least 1 year."
```

Other languages added later use the same key structure. Web Push is intentionally absent from v1 keys; v1.1 adds the `channels.web_push: "Browser"` key as an additive change.

---

## Extending notification categories (for forks)

ModelRails is a *starter kit* — downstream forks will add events and may want to add or rename categories. The design supports this without breaking changes if you follow this contract:

**Add a new category**:

1. Append the category name to `NotificationPreferences::CATEGORIES`.
2. Add a default-row migration that updates existing `user_preferences.notification_preferences` jsonb to include the new category with sensible defaults. Use `update_all` with a jsonb `||` merge in Postgres or a Ruby-side iteration in SQLite.
3. Add the locale key under `notifications.preferences.categories.<your_category>`.
4. Set `category :your_category` on Notifier classes that belong to it.
5. If digest-eligible, add it to `NotificationPreferences::DIGEST_ELIGIBLE_CATEGORIES`.
6. If security-relevant, add corresponding Notifier types to `NotificationPreferences::SECURITY_NOTIFIER_TYPES` so the retention floor applies.

**Rename a category** (rare, expensive — avoid if possible):

1. Add the new category alongside the old.
2. Backfill existing user prefs from old → new.
3. Update Notifier `category :foo` references.
4. Remove the old category in a follow-up migration after one release cycle of dual-presence.

**Don't rename categories casually**. Existing forks have user data keyed by your category names; renames cascade through their migrations, locale files, and UX copy. Pick well, then leave them alone.

---

## Files touched (preview)

**New:**

- `app/notifiers/application_notifier.rb` (idempotency-key auto-population, `recipient_pref` delegation, `mark_seen!` hook, `render_safe_or_placeholder` helper)
- `app/notifiers/workspace_invitation_received_notifier.rb` (and 9 siblings — one per v1 event)
- `app/lib/notification_preferences.rb` (value object wrapping the jsonb column; `DIGEST_ELIGIBLE_CATEGORIES`, `SECURITY_NOTIFIER_TYPES`, `RETENTION_FLOORS` constants live here)
- `app/mailers/notification_mailer.rb` + `app/views/notification_mailer/*.{html,text}.erb` (transactional + digest templates)
- `app/controllers/account/notifications_controller.rb` (index, show/redirect, mark-read, mark-unread, destroy, mark_all_read, destroy_all_read)
- `app/controllers/account/notification_preferences_controller.rb` (edit, update — Turbo Stream auto-save per toggle)
- `app/views/account/notifications/{index,_item}.html.erb`
- `app/views/account/notification_preferences/edit.html.erb`
- `app/views/shared/_notifications_dropdown.html.erb`
- `app/javascript/controllers/notification_dropdown_controller.js`
- `app/jobs/notification_cleanup_job.rb` (grace-period + batched-in-100s)
- `app/jobs/digest_mailer_job.rb` (single indexed query against `digest_next_due_at`)
- `config/recurring.yml` (Solid Queue scheduled jobs — annotated with the *why* per Aaron's note)
- `config/locales/en/notifications.en.yml`
- `db/migrate/{ts}_install_noticed.rb` (gem-generated)
- `db/migrate/{ts}_harden_noticed_tables.rb` (our additions: unique idempotency index, partial unread index, cascade FK, check constraints)
- `db/migrate/{ts}_add_notification_preferences_to_user_preferences.rb` (jsonb column + `digest_next_due_at` + `digest_last_sent_at` columns + index)
- `db/migrate/{ts}_add_last_known_browsers_to_users.rb` (jsonb column for sign-in fingerprint heuristic)
- Specs for each of the above.

**Modified:**

- `Gemfile` — add `noticed ~> 2.5` (~1 line; no `webpush` until v1.1).
- `app/views/shared/_user_menu.html.erb` — embed the bell + dropdown.
- `app/models/user.rb` — `has_many :notifications, as: :recipient, class_name: "Noticed::Notification"`. Add `last_known_browsers` jsonb accessor + `seen_browser?(user_agent)` instance method.
- `app/models/user_preferences.rb` — typed accessor `notification_preferences_object` returning `NotificationPreferences` value object instance.
- `app/controllers/concerns/authentication.rb` — after a successful sign-in, hash `User-Agent + OS`, check `User#seen_browser?`, fire `SignInFromNewDeviceNotifier` if not seen, append to `last_known_browsers` either way.
- `app/models/concerns/trackable.rb` — no changes (parallel architecture).
- `config/routes.rb` — add the new routes.
- `app/views/account/_navigation.html.erb` (or equivalent) — add link to notification preferences.
- `CHANGELOG.md` under Unreleased.

**Estimated total**: ~1100 LOC of application code (down from ~1500 after Web Push descope), ~1100 LOC of specs (the hardening test cases offset some of the Web Push spec savings), ~250 LOC of locale + migration + config. Sizable but each Notifier is repetitive after the first; the marginal cost of event 11+ is low.

---

## Out of scope (explicitly deferred)

These came up during brainstorming and are *not* in v1 but the architecture supports them:

- **Web Push** (browser push notifications). Deferred to v1.1; preference JSONB shape supports clean additive upgrade.
- Per-event preference granularity (v1 is per-category × per-channel).
- @-mentions and comment-thread notifications.
- Slack / Microsoft Teams / SMS delivery channels.
- Cross-tab read-state real-time sync (badge count only updates on next interaction in unfocused tabs).
- Admin / staff notification dashboard.
- Notification "boost" / reactions.
- Locale-aware digest send times beyond user-IANA-timezone.

---

## Implementation choices answered (formerly "open questions")

The following implementation-level decisions are answered here so the plan stage doesn't re-litigate them:

1. **Preferences page placement**: **sibling page** `account/notification_preferences#edit`. Parity with the dedicated `/account/notifications` triage page; preferences are a discrete surface, not a profile section.
2. **Bell icon trigger**: **render in user menu strip** (left of the avatar). User-menu dropdown stays focused on account actions; the bell is its own affordance with its own dropdown.
3. **Stimulus controller for notification dropdown**: **separate controller** `notification_dropdown_controller.js`. Extending the user-menu controller would couple two unrelated UI concerns; the dropdowns are sibling features that share keyboard-shortcut conventions but don't share state.
4. **`SignInFromNewDeviceNotifier` fingerprint heuristic**: locked in Decision #13 — SHA-256 of `User-Agent + OS`, no IP. `User#last_known_browsers` JSONB array.
5. **Concurrent notification creation idempotency**: locked in Decision #12 (revised) — dedicated `idempotency_key` column on `noticed_events` + partial unique index `WHERE idempotency_key IS NOT NULL` + automatic key population in `ApplicationNotifier#before_create`. `ApplicationNotifier#deliver` returns sentinel `:delivered` or `:deduplicated`. Schema stays on `schema_format = :ruby` (no structure.sql switch — that was an Option A artifact, ruled out by 5-reviewer panel).

---

## Genuinely open for the plan

One implementation-level question remains for the plan to answer while sequencing tasks:

1. **Default `digest_next_due_at` backfill strategy** for existing users at the time the migration runs: set to `nil` and let the first digest job populate, or set to a randomized window in the next 24 hours to spread load across the digest job's polling cadence? The latter is safer at scale; the former is simpler. Either works; the plan should pick one and justify briefly.

---

*Plan to follow once spec is approved.*
