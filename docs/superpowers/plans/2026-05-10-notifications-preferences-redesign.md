# Notifications Preferences Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks ship across **three sequential PRs**; do not collapse them. Each PR ends with a merge checklist; do not skip the Lefthook pre-push gate.

**Goal:** Redesign `/account/notification_preferences/edit` from a 5×3 matrix to a parallel-list IA with Quiet Hours, sample-faithful visual treatment, browser-detected timezone capture, and a JSONB schema reshape that folds the digest system into the Email channel as a frequency selector. Phase 3 (Sounds + Desktop Notifications) is a separate future spec.

**Architecture:** Three layers:
- **Phase 0 — Visual foundation**: reusable `shared/_preferences_card` and `shared/_preferences_row` partials with the new card aesthetic. OKLCH AAA token audit (reuse existing semantic tokens; add only if no equivalent exists). `edit.html.erb` refactored to use the partials while preserving v1 5×3 matrix content — pure visual swap, no behavior change.
- **Phase 0.5 — Timezone beacon**: `timezone_beacon_controller` Stimulus controller reads `Intl.DateTimeFormat().resolvedOptions().timeZone` on `<body>` connect; POSTs to `POST /account/preferences/timezone` which writes to `user_preferences.timezone` only when nil. Preferences page surfaces the detected zone with a Change action over a native `<select>` (regional optgroups + 10 US zones at top).
- **Phase 1 — IA + JSONB reshape + Quiet Hours**: data migration reshapes the JSONB to `notification_types` + `delivery_methods` + `quiet_hours`. `NotificationPreferences#allow?` rewritten to drive off the new shape. `quiet_hours_active?(now:)` added with modular interval check. `DigestMailerJob` driven off `delivery_methods.email.frequency`. Edit view rewritten as four cards. Migration banner partial + dismiss endpoint.

**Tech Stack:** Rails 8.1, Ruby 3.3+, SQLite, Solid Queue, TailwindCSS 4 + OKLCH design tokens, Pundit, Turbo + Stimulus, RSpec (request/model/system + new `spec/lib/notification_preferences_spec.rb` additions for the shape change), Playwright system specs at 375×667 viewport for mobile coverage.

**Spec:** [docs/superpowers/specs/2026-05-10-notifications-preferences-redesign-design.md](../specs/2026-05-10-notifications-preferences-redesign-design.md)

**Important:** All shell commands use `mise exec --` prefix (per `.tool-versions`). Pre-push runs the full RSpec + Rubocop + Brakeman + tailwind_build pipeline via Lefthook — never bypass with `LEFTHOOK=0`. Push small, complete PRs to `feat/preferences-*` or `chore/preferences-*` branches; let CI validate the merge bar.

**Discipline:** Every task follows strict Red-Green TDD. The first numbered step in each task writes a failing spec that probes the contract the task delivers. Implementation only begins after the spec is observed failing for the right reason. Migration tasks are no exception — the data migration's spec probes the post-migration JSONB shape against representative legacy fixtures.

---

## Resolved open questions (from spec-phase Q1–Q4)

### Q1 — Quiet hours: drop vs defer

**Decision: Drop.** When `quiet_hours_active? && category != "security"`, the email is not sent. The in-app `Noticed::Notification` row is still persisted, so the user sees what they missed when they open the app. No scheduler state required.

Rationale: deferring creates a 7am email flood, which is *worse* UX than dropping. The whole point of quiet hours is "don't pester me at all." The email frequency selector (`Daily` / `Weekly`) already handles the "batch this stuff up for me" need. Matches Slack's Push-during-DND behavior.

Implementation: in `ApplicationNotifier`'s `deliver_by :email` `if:` conditional, gate on `!user.preferences.notification_preferences_object.quiet_hours_active?` for non-security categories.

### Q2 — Migration banner placement

**Decision: Preferences-page banner + account-menu unread-dot indicator.** The banner itself only renders on `/account/notification_preferences/edit`. A small 4px cyan dot is appended via Tailwind `after:` pseudo-element on the user-menu "Preferences" link, conditional on `dismissed_notifications_redesign_banner_at IS NULL`.

Rationale: surfaces the change passively without nagging on unrelated pages. The dot is just CSS — no Stimulus or JS state.

Implementation: `app/views/account/notification_preferences/_migration_banner.html.erb` + dismiss endpoint `POST /account/notification_preferences/dismiss_banner` + `dismissed_notifications_redesign_banner_at:datetime` column. User-menu dot lives in `_user_menu.html.erb` as a one-line conditional `after:` class.

### Q3 — Timezone picker UI

**Decision: native `<select>` with regional optgroups + 10 US zones at the top as an unlabeled first optgroup.** Zero JS. Browser provides type-to-jump. AAA-accessible by default via optgroup announcements.

Rationale: covers 90% of users (US-based) with the common-first list; 100% of users via the regional optgroups. No Stimulus controller for the picker itself (the beacon controller is unrelated).

Implementation: `app/helpers/timezones_helper.rb` exposes `timezone_options_for_select` which builds the structured optgroup list. The 10 common zones come from a static array (manually curated, not derived from `ActiveSupport::TimeZone.us_zones` since that returns 8 + we want exactly 10 including Alaska + Hawaii).

### Q4 — Mobile testing strategy

**Decision: one Playwright system spec at 375×667 (iPhone SE viewport)** asserting (1) axe-core passes with no AAA violations, (2) `document.documentElement.scrollWidth <= clientWidth` (no horizontal scroll), (3) all four cards are stacked vertically and visible without horizontal pan.

Rationale: catches the matrix-collapse regression that motivated this whole redesign. Single spec, ~30 lines.

Implementation: `spec/system/account/notification_preferences_mobile_spec.rb`. Uses existing Playwright driver setup.

---

## PR sequence (3 PRs)

1. **PR-1 — Phase 0: Visual foundation** (Tasks 1–4): Reusable `_preferences_card` + `_preferences_row` partials. OKLCH token audit. Refactor `edit.html.erb` to render the existing v1 5×3 matrix through the new partials — no behavior change. Component-level partial specs. AAA contrast verified for new layout. **Merge gate:** existing 11 request specs still pass; visual swap complete; partials documented.

2. **PR-2 — Phase 0.5: Timezone beacon** (Tasks 5–7): `POST /account/preferences/timezone` endpoint with idempotent write semantics. `timezone_beacon_controller.js` Stimulus controller. "Detected timezone" surface on preferences page with native `<select>` Change action. Timezones helper for the optgroup-structured option list. **Merge gate:** beacon idempotency + auth contract verified; system spec for round-trip; preferences page shows detected zone.

3. **PR-3 — Phase 1: JSONB reshape + IA + Quiet Hours** (Tasks 8–17): Data migration reshapes existing JSONB rows per the spec's backfill rules. `NotificationPreferences` value object rewritten for new shape. `quiet_hours_active?` with all 8 test cases. `Account::NotificationPreferencesController#update` rewired for new params shape. Edit view rewritten as four cards. Migration banner + dismiss endpoint + user-menu dot. `DigestMailerJob` driven off new frequency selector. Mobile Playwright spec. Locale keys. **Merge gate:** all spec acceptance criteria pass; full suite green; mobile spec green at 375×667.

---

## File Map

| Path | Action | PR |
| ---- | ------ | -- |
| `app/views/shared/_preferences_card.html.erb` | Create | 1 |
| `app/views/shared/_preferences_row.html.erb` | Create | 1 |
| `spec/views/shared/preferences_card_spec.rb` | Create | 1 |
| `spec/views/shared/preferences_row_spec.rb` | Create | 1 |
| `app/views/account/notification_preferences/edit.html.erb` | Modify (P0: refactor to partials; P1: rewrite to cards) | 1, 3 |
| `app/assets/tailwind/application.css` | Modify (token audit; add missing tokens if any) | 1 |
| `spec/system/account/notification_preferences_aaa_spec.rb` | Create | 1 |
| `config/routes.rb` | Modify (timezone endpoint + dismiss banner endpoint) | 2, 3 |
| `app/controllers/account/preferences_controller.rb` | Create (timezone endpoint host) | 2 |
| `spec/requests/account/preferences/timezone_spec.rb` | Create | 2 |
| `app/javascript/controllers/timezone_beacon_controller.js` | Create | 2 |
| `app/javascript/controllers/index.js` | Verify (auto-loads — no change needed) | 2 |
| `app/views/layouts/application.html.erb` | Modify (add `data-controller="timezone-beacon"` on body) | 2 |
| `app/helpers/timezones_helper.rb` | Create (`timezone_options_for_select`) | 2 |
| `spec/helpers/timezones_helper_spec.rb` | Create | 2 |
| `spec/system/account/timezone_beacon_spec.rb` | Create | 2 |
| `db/migrate/<ts>_reshape_notification_preferences_jsonb.rb` | Create | 3 |
| `db/migrate/<ts>_add_dismissed_notifications_redesign_banner_at.rb` | Create (or merge into reshape migration) | 3 |
| `db/schema.rb` | Modify (auto-dump) | 3 |
| `spec/migrations/reshape_notification_preferences_jsonb_spec.rb` | Create | 3 |
| `app/lib/notification_preferences.rb` | Rewrite (new shape, `quiet_hours_active?`, `allow?` against new keys) | 3 |
| `spec/lib/notification_preferences_spec.rb` | Modify (new shape) + add 8 quiet-hours tests | 3 |
| `app/controllers/account/notification_preferences_controller.rb` | Rewrite (`apply_changes!` for new shape, `valid_quiet_hours?` etc.) | 3 |
| `spec/requests/account/notification_preferences_spec.rb` | Modify (new params shape) | 3 |
| `app/views/account/notification_preferences/edit.html.erb` | Rewrite (four cards) | 3 |
| `app/views/account/notification_preferences/_migration_banner.html.erb` | Create | 3 |
| `app/controllers/account/notification_preferences_controller.rb` | Modify (add `dismiss_banner` action) | 3 |
| `app/views/shared/_user_menu.html.erb` | Modify (add unread-dot pseudo-element conditional) | 3 |
| `app/notifiers/application_notifier.rb` | Modify (gate `deliver_by :email` on quiet hours for non-security) | 3 |
| `spec/notifiers/application_notifier_spec.rb` | Modify (3+ new specs for quiet-hours email gating) | 3 |
| `app/jobs/digest_mailer_job.rb` | Modify (drive off `delivery_methods.email.frequency`) | 3 |
| `spec/jobs/digest_mailer_job_spec.rb` | Modify (frequency-driven scoping) | 3 |
| `config/locales/en/notifications.en.yml` | Modify (new keys; remove obsolete ones) | 3 |
| `spec/system/account/notification_preferences_mobile_spec.rb` | Create | 3 |
| `spec/system/account/notification_preferences_aaa_spec.rb` | Modify (assert new layout AAA) | 3 |

---

## PR-1: Phase 0 — Visual foundation

**Branch:** `feat/preferences-visual-foundation`
**Goal:** Land the reusable `_preferences_card` + `_preferences_row` partials and refactor `edit.html.erb` to use them while preserving the existing 5×3 matrix content. **Behavior unchanged.** This PR is the visual swap; Phase 1 (PR-3) does the IA shift.

### Task 1: OKLCH token audit

- [ ] **Spec first.** Add `spec/system/account/notification_preferences_aaa_spec.rb` covering the existing view at desktop (1280px) and asserting axe-core returns zero AAA violations. This is the baseline; PR-1 must not regress it.
- [ ] Run the spec — should pass on the current view (current view is already AAA-compliant per PR #74 work).
- [ ] Audit `app/assets/tailwind/application.css` for OKLCH semantic tokens covering the sample's palette roles: `slate-900` (primary text), `gray-50` (subtle hairline), `gray-100` (card border), `gray-300` (inactive), `gray-400` (overline), `gray-500` (secondary text), `blue-50` (icon tile bg), `blue-600` (icon tile fg), `#FAFAFA` (page bg).
- [ ] Map each role to an existing semantic token (`text-text-heading`, `text-text-body`, `text-text-muted`, `bg-surface`, `bg-surface-raised`, `border-border`, etc.). Most will already exist.
- [ ] If any role has no existing token AND no acceptable substitute, add ONE new token to the OKLCH palette with both light + dark mode values. Document in commit message.
- [ ] **Acceptance:** All sample palette roles map to existing tokens, OR commit message documents each new token with its OKLCH lightness/chroma/hue values AND its AAA-pair contrast ratios.

### Task 2: `_preferences_card` partial

- [ ] **Spec first.** `spec/views/shared/preferences_card_spec.rb` with three test cases: (1) renders title + block content; (2) renders optional description when local provided; (3) emits the new card classes (`rounded-2xl bg-surface border border-border divide-y divide-border-subtle shadow-sm`).
- [ ] Run — fail because partial doesn't exist.
- [ ] Create `app/views/shared/_preferences_card.html.erb` with strict locals: `title:`, `description: nil`, and a yielded block. Renders `<section aria-labelledby="...">` semantics with `<h2>` for the title.
- [ ] Implementation matches the sample's card visual: 24px padding, rounded-2xl corners, white surface, gray-100 border. Map to OKLCH tokens audited in Task 1.
- [ ] Run — pass.
- [ ] **Acceptance:** Partial renders with strict locals contract; all three test cases pass; visual matches sample at desktop and at 375×667.

### Task 3: `_preferences_row` partial

- [ ] **Spec first.** `spec/views/shared/preferences_row_spec.rb` with four test cases: (1) renders icon tile + title + description + control; (2) icon tile uses provided `icon_name` and `icon_color`; (3) row is keyboard-navigable (the control receives focus); (4) row meets AAA contrast for default icon color.
- [ ] Run — fail because partial doesn't exist.
- [ ] Create `app/views/shared/_preferences_row.html.erb` with strict locals: `icon_name:`, `icon_color:`, `title:`, `description:`, `control:` (control passed as `capture do ... end` from the caller, or as a partial path). Renders `<li class="flex items-start gap-4 p-6">` with the icon tile on the left, title+description in the middle, control on the right.
- [ ] Icon tile: `w-10 h-10 rounded-xl bg-<icon_color>-50 text-<icon_color>-600 flex items-center justify-center`. SVG icon resolved via `icon_name` against `app/assets/icons/`.
- [ ] Run — pass.
- [ ] **Acceptance:** Partial renders with strict locals contract; all four test cases pass; AAA contrast verified for `icon_color` ∈ {blue, green, amber, red, slate}.

### Task 4: Refactor `edit.html.erb` to use new partials (preserving v1 matrix)

- [ ] **Spec first.** Modify the existing AAA system spec to assert the page renders inside `<section>` elements with the `rounded-2xl` card class. This locks the structural change without locking behavior.
- [ ] Run — fail because view still uses the v1 layout.
- [ ] Rewrite `app/views/account/notification_preferences/edit.html.erb` to wrap the existing master-DND form, 5×3 matrix, digest section, and retention section each in a `_preferences_card` partial. **Content unchanged; only the wrapping changes.** No IA shift in this PR.
- [ ] Run the existing 11 request specs in `notification_preferences_spec.rb` — all must pass unchanged.
- [ ] Run the AAA system spec — must pass.
- [ ] **Acceptance:** All 11 existing request specs pass; AAA system spec passes; visual diff: page now uses rounded-2xl cards instead of the v1 plain layout.

### PR-1 merge checklist

- [ ] All four tasks committed atomically per Conventional Commits.
- [ ] Branch is `feat/preferences-visual-foundation`.
- [ ] Lefthook pre-push passes (RSpec + Rubocop + Brakeman + tailwind_build).
- [ ] PR description references the spec doc + this plan.
- [ ] CI green.
- [ ] No new gems added.
- [ ] No service objects added.

---

## PR-2: Phase 0.5 — Timezone beacon

**Branch:** `feat/preferences-timezone-beacon`
**Goal:** Capture browser-detected timezone on layout connect via `Intl.DateTimeFormat`. Surface detected zone on preferences page with a Change action over a native `<select>` (regional optgroups + 10 US zones at top).

### Task 5: `POST /account/preferences/timezone` endpoint

- [ ] **Spec first.** `spec/requests/account/preferences/timezone_spec.rb` with five test cases: (1) writes when `timezone IS NULL`; (2) no-op when timezone already set; (3) rejects invalid IANA identifier with 422; (4) requires authenticated session (302 redirect when anonymous); (5) returns 204 on success (write or no-op).
- [ ] Run — fail because endpoint doesn't exist.
- [ ] Add route: `resource :preferences, only: [], controller: "preferences" do; resource :timezone, only: [:update], controller: "preferences/timezone"; end` (or simpler: `patch "/account/preferences/timezone", to: "account/preferences#update_timezone"`).
- [ ] Create `app/controllers/account/preferences_controller.rb` with `#update_timezone` action. Validates the param against `ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name)`. Writes via `Current.user.preferences.update(timezone: tz)` only when current value is blank.
- [ ] No Pundit policy class needed (the action operates on `current_user.preferences` and there's no other actor; the authenticated-session check is sufficient authorization).
- [ ] Run — pass.
- [ ] **Acceptance:** All five test cases pass; endpoint is idempotent; auth gate is enforced; validation rejects malformed IANA identifiers.

### Task 6: `timezone_beacon_controller.js` Stimulus controller

- [ ] **Spec first.** `spec/system/account/timezone_beacon_spec.rb` with two test cases: (1) round-trip — a freshly-signed-in user with `timezone IS NULL` visits any page; after page load, `user.preferences.reload.timezone` is populated with a valid IANA zone; (2) idempotency — a user with `timezone = "Europe/London"` (set explicitly) visits any page; their timezone is NOT overwritten by the beacon.
- [ ] Run — fail because beacon controller doesn't exist.
- [ ] Create `app/javascript/controllers/timezone_beacon_controller.js`:
  ```javascript
  import { Controller } from "@hotwired/stimulus"
  export default class extends Controller {
    static values = { url: String, token: String }
    async connect() {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (!tz) return
      try {
        await fetch(this.urlValue, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": this.tokenValue,
            "Accept": "application/json"
          },
          body: JSON.stringify({ timezone: tz })
        })
      } catch (e) {
        // Best-effort beacon; failures are silent.
      }
    }
  }
  ```
- [ ] Add `data-controller="timezone-beacon"`, `data-timezone-beacon-url-value=...`, `data-timezone-beacon-token-value="<%= form_authenticity_token %>"` to `<body>` in `app/views/layouts/application.html.erb` — but only for authenticated users (gate via `<% if authenticated? %>`).
- [ ] Run — both test cases pass.
- [ ] **Acceptance:** Round-trip beacon writes a valid IANA zone; idempotency preserved; no errors logged in console for normal operation.

### Task 7: Detected-timezone surface on preferences page

- [ ] **Spec first.** Add to existing `notification_preferences_spec.rb`: a test that asserts when `user.preferences.timezone = "America/Chicago"`, the edit page renders text containing "America/Chicago" inside a `<form>` that POSTs to the timezone endpoint, with a `<select>` containing `<optgroup>` elements for "Common", "Americas", "Europe", etc.
- [ ] Run — fail because the surface doesn't exist.
- [ ] Create `app/helpers/timezones_helper.rb` with `timezone_options_for_select(selected: nil)` that returns an array suitable for `options_for_select`:
  ```ruby
  COMMON_US_ZONES = %w[
    America/New_York America/Chicago America/Denver America/Phoenix
    America/Los_Angeles America/Anchorage Pacific/Honolulu
    America/Indiana/Indianapolis America/Detroit America/Kentucky/Louisville
  ].freeze

  REGIONAL_GROUPS = {
    "Americas" => ->(name) { name.start_with?("America/") },
    "Europe"   => ->(name) { name.start_with?("Europe/") },
    "Asia"     => ->(name) { name.start_with?("Asia/") },
    "Pacific"  => ->(name) { name.start_with?("Pacific/") || name == "Australia" },
    "Africa"   => ->(name) { name.start_with?("Africa/") },
    "Atlantic" => ->(name) { name.start_with?("Atlantic/") },
    "Indian"   => ->(name) { name.start_with?("Indian/") }
  }.freeze

  def timezone_options_for_select(selected: nil)
    grouped = REGIONAL_GROUPS.transform_values do |matcher|
      ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name)
        .uniq.sort.select(&matcher)
        .reject { |n| COMMON_US_ZONES.include?(n) }
    end
    # Returns [["Common", COMMON_US_ZONES], ["Americas", [...]], ...]
    [["Common", COMMON_US_ZONES]] + grouped.to_a
  end
  ```
- [ ] Add corresponding helper spec covering the structure.
- [ ] Update the edit view to render a "Detected timezone" line at the top of the page with the current timezone in text + a Change action that toggles a `<select>` populated via `grouped_options_for_select(timezone_options_for_select, current)`. Form POSTs to `PATCH /account/preferences/timezone` (the same endpoint).
- [ ] **NOTE — endpoint contract change:** Task 5's endpoint refuses to overwrite an existing value. For the Change action to work, the endpoint needs an `override: true` param. Update Task 5's spec + controller to accept this param and bypass the no-overwrite guard when present. The beacon does NOT send `override`, so it remains idempotent.
- [ ] Run the request and view specs — pass.
- [ ] **Acceptance:** Detected timezone is visible on the preferences page; Change action opens a select with regional optgroups; explicit-change writes through; native browser type-to-jump works in the `<select>`.

### PR-2 merge checklist

- [ ] All three tasks committed atomically per Conventional Commits.
- [ ] Branch is `feat/preferences-timezone-beacon`.
- [ ] Lefthook pre-push passes.
- [ ] PR description notes the endpoint contract change (`override: true` param) and why.
- [ ] CI green.
- [ ] Beacon does not fire for unauthenticated users (verify in spec).
- [ ] No new gems added.

---

## PR-3: Phase 1 — JSONB reshape + IA + Quiet Hours

**Branch:** `feat/preferences-redesign`
**Goal:** Reshape the JSONB column, rewrite the value object + controller + view, add Quiet Hours, fold digest into Email frequency, add migration banner. This is the large PR — split internally into 10 atomic-commit tasks.

### Task 8: Data migration — reshape notification_preferences JSONB

- [ ] **Spec first.** `spec/migrations/reshape_notification_preferences_jsonb_spec.rb` (or under `spec/lib/` as a data-reshape unit spec with the migration class loaded via `require_relative`):
  - Seed 4 representative legacy shapes (everything on; everything off; security-only email; mixed-with-digest).
  - Run the migration's reshape method.
  - Assert each legacy shape maps to the expected new shape per the backfill rules.
- [ ] Run — fail because migration doesn't exist.
- [ ] Generate migration: `bin/rails g migration ReshapeNotificationPreferencesJsonb`.
- [ ] Implement `up`:
  1. Add `dismissed_notifications_redesign_banner_at:datetime` column to `user_preferences`.
  2. Inside the migration, define a private `reshape_jsonb(legacy)` method that applies the backfill rules:
     ```ruby
     def reshape_jsonb(legacy)
       legacy ||= {}
       categories = legacy["categories"] || {}
       digest_was_on = categories.any? { |_c, channels| channels["digest"] == true }
       has_in_app = categories.any? { |_c, channels| channels["in_app"] == true }
       has_email  = categories.any? { |_c, channels| channels["email"] == true }
       {
         "notification_types" => {
           "security"            => categories.dig("security",            "in_app") || categories.dig("security",            "email") || true,
           "account_access"      => categories.dig("account_access",      "in_app") || categories.dig("account_access",      "email") || false,
           "workspace_activity"  => categories.dig("workspace_activity",  "in_app") || categories.dig("workspace_activity",  "email") || false,
           "project_activity"    => categories.dig("project_activity",    "in_app") || categories.dig("project_activity",    "email") || false,
           "billing"             => categories.dig("billing",             "in_app") || categories.dig("billing",             "email") || false
         },
         "delivery_methods" => {
           "in_app" => { "enabled" => has_in_app },
           "email"  => { "enabled" => has_email, "frequency" => digest_was_on ? "daily" : "instant" }
         },
         "quiet_hours" => {
           "enabled"      => legacy["do_not_disturb"] == true,
           "start"        => "22:00",
           "end"          => "07:00",
           "allow_urgent" => true
         },
         "retention_days" => legacy["retention_days"] || 90
       }
     end
     ```
     Note: `notification_types.security` is forced to `true` regardless of legacy input — the security floor (decision #1 in spec). Account/workspace/project/billing default to `false` if no legacy data; the OR is "any channel was on → category on."
  3. Iterate over `UserPreferences.in_batches(of: 500)` and update each row's `notification_preferences` JSONB via `update_column`. `update_column` is correct here (no validations, no `updated_at` whiplash).
- [ ] Implement `down`: restore the legacy JSONB schema-default for all rows. User-specific settings ARE lost on rollback — document in migration comment.
- [ ] Run the spec — pass.
- [ ] Run the migration locally + `db:schema:load`; verify schema.rb diff is the added column + the dropped legacy keys reflected in any column defaults.
- [ ] **Acceptance:** All 4 representative legacy shapes map correctly; `dismissed_notifications_redesign_banner_at` column added; rollback restores schema (with documented data loss).

### Task 9: Rewrite `NotificationPreferences` value object for new shape

- [ ] **Spec first.** Update `spec/lib/notification_preferences_spec.rb`:
  - Replace existing `allow?(category:, channel:)` test cases with the new decision tree (5 representative cases covering security-bypass, type-disabled, channel-disabled, frequency-non-instant, quiet-hours-active).
  - Add 8 new tests for `quiet_hours_active?(now:)`: in-window same-day, in-window overnight (after start), in-window overnight (before end), out-of-window same-day, out-of-window overnight, disabled, boundary (end is exclusive), missing-timezone fallback.
  - Update `do_not_disturb?` removal — search for any caller in the codebase and update each to `quiet_hours_active?`. Caller list: grep first.
- [ ] Run — fail (specs cover behavior that doesn't exist yet).
- [ ] Rewrite `app/lib/notification_preferences.rb`:
  - Remove `do_not_disturb?`.
  - Add `quiet_hours_active?(now: Time.current)` per the spec's contract:
    ```ruby
    def quiet_hours_active?(now: Time.current)
      qh = @prefs["quiet_hours"] || {}
      return false unless qh["enabled"]
      zone = ActiveSupport::TimeZone[@user.preferences.timezone] || Time.zone
      cur  = zone.now.strftime("%H:%M")
      s, e = qh["start"], qh["end"]
      s <= e ? (cur >= s && cur < e) : (cur >= s || cur < e)
    end
    ```
  - Rewrite `allow?(category:, channel:)` to drive off the new shape per the decision tree in the spec:
    - Step 1: security category → always true.
    - Step 2: `notification_types[category] == false` → false.
    - Step 3: `delivery_methods[channel].enabled == false` → false.
    - Step 4: if channel = "email" and frequency != "instant" → return :digest (or false-for-immediate, true-for-digest-queue).
    - Step 5: if quiet_hours_active? AND category != "security" → false.
    - Else → true.
  - **Note:** the return value gains a 4th state (`:digest`). Caller updates needed — see Task 10.
- [ ] Update constants:
  - `CATEGORIES = %w[security account_access workspace_activity project_activity billing].freeze` — unchanged.
  - `CHANNELS = %w[in_app email].freeze` — `digest` removed (now a sub-mode of email).
  - `EMAIL_FREQUENCIES = %w[instant daily weekly].freeze` — new constant.
  - `DIGEST_ELIGIBLE_CATEGORIES` — DELETE. Every email-eligible category is now digest-eligible if `frequency != "instant"`.
  - `RETENTION_FLOORS = { "security" => 365.days }.freeze` — unchanged.
- [ ] Run — pass.
- [ ] **Acceptance:** All 8 quiet-hours tests pass; security bypasses every check; frequency-non-instant returns the queue sentinel correctly; missing-timezone fallback works.

### Task 10: Rewire `ApplicationNotifier` + `DigestMailerJob` for new contract

- [ ] **Spec first.** Update `spec/notifiers/application_notifier_spec.rb`:
  - Add three new specs: (1) email is suppressed when `quiet_hours_active?` returns true for a non-security category; (2) email is delivered when `quiet_hours_active?` returns true for security; (3) `:digest` sentinel from `allow?` queues for the digest cycle (asserts the email isn't sent immediately).
  - Update `spec/jobs/digest_mailer_job_spec.rb`: replace `DIGEST_ELIGIBLE_CATEGORIES` references with `delivery_methods.email.frequency != "instant"` driven scoping; assert security emails are NEVER digested (always go instant).
- [ ] Run — fail.
- [ ] Update `app/notifiers/application_notifier.rb`:
  - `deliver_by :email` `if:` proc now reads:
    ```ruby
    if: ->(notification) {
      prefs = notification.recipient.preferences&.notification_preferences_object
      next false if prefs.nil?
      result = prefs.allow?(category: category_name, channel: "email")
      next false if result == false
      # :digest means "queue, don't send now" — DigestMailerJob picks it up
      result != :digest
    }
    ```
- [ ] Update `app/jobs/digest_mailer_job.rb`:
  - `digest_scope(user)` now selects users where `delivery_methods.email.frequency != "instant"` and security-category notifications are filtered OUT (those always went instant).
  - Drop `DIGEST_ELIGIBLE_CATEGORIES` reference.
- [ ] Run — pass.
- [ ] **Acceptance:** Quiet-hours email suppression works for non-security; security always delivers; digest queueing works per frequency.

### Task 11: Rewrite controller's `apply_changes!` for new shape

- [ ] **Spec first.** Update `spec/requests/account/notification_preferences_spec.rb` for the new params shape. Existing 11 tests get updated to the new shape; add 8 new tests covering quiet-hours validation (valid HH:MM, invalid format, missing start/end, allow_urgent ignored), email.frequency validation (instant/daily/weekly accepted, other rejected with 422), and notification_types key validation (unknown keys rejected with 422).
- [ ] Run — fail.
- [ ] Rewrite `apply_changes!` in `app/controllers/account/notification_preferences_controller.rb`:
  - Accept top-level keys: `notification_types`, `delivery_methods`, `quiet_hours`, `retention_days`.
  - Validate each. For `quiet_hours.start` / `quiet_hours.end`, use `/\A([01]\d|2[0-3]):([0-5]\d)\z/` regex.
  - For `delivery_methods.email.frequency`, accept one of `%w[instant daily weekly]`.
  - For `notification_types`, accept only keys in `NotificationPreferences::CATEGORIES`. Reject unknown keys with 422.
  - Reuse the deep-merge pattern.
- [ ] Update `valid_retention?` + `normalize_retention` from PR #73 — unchanged in shape, still works.
- [ ] Run — pass.
- [ ] **Acceptance:** All new + updated request specs pass; 422 returned for every invalid input shape.

### Task 12: Rewrite `edit.html.erb` as four cards

- [ ] **Spec first.** Update the existing AAA system spec to assert the new four-card layout:
  - Card 1: "Notification Types" — 5 rows (security row shows a lock icon and "Always on" badge).
  - Card 2: "Delivery Method" — 2 rows (in_app, email-with-frequency-select).
  - Card 3: "Quiet Hours" — toggle + start/end time inputs + fixed text "Security alerts will always come through."
  - Card 4: "Advanced" — retention dropdown.
- [ ] Run — fail.
- [ ] Rewrite `app/views/account/notification_preferences/edit.html.erb` using the Phase 0 partials. Each card renders via `_preferences_card`; each row via `_preferences_row`. The controls (toggle / select / time input) are passed as block content.
- [ ] Use the auto-submit Stimulus controller for all forms (already in PR-4 of v1).
- [ ] Update locale: add new keys under `notifications.preferences.notification_types.*`, `notifications.preferences.delivery_methods.*`, `notifications.preferences.quiet_hours.*`, `notifications.preferences.advanced.*`. Remove obsolete keys (digest section, matrix-related).
- [ ] Run — pass.
- [ ] **Acceptance:** Four cards render; security row shows always-on badge; quiet-hours card shows fixed reassurance text (not a toggle).

### Task 13: Migration banner + dismiss endpoint

- [ ] **Spec first.** Add request spec for `POST /account/notification_preferences/dismiss_banner`: writes `dismissed_notifications_redesign_banner_at: Time.current`; requires auth; idempotent. Add view spec asserting the banner renders on the preferences page when `dismissed_notifications_redesign_banner_at IS NULL` and doesn't render when present.
- [ ] Run — fail.
- [ ] Add route + controller action `Account::NotificationPreferencesController#dismiss_banner`.
- [ ] Create `app/views/account/notification_preferences/_migration_banner.html.erb` — renders a one-line banner with locale-key copy "We simplified notifications — take a moment to review your preferences." + a Dismiss button that POSTs to the endpoint via Turbo.
- [ ] Render the banner partial conditionally at the top of `edit.html.erb`.
- [ ] Run — pass.
- [ ] **Acceptance:** Banner renders for users with `dismissed_notifications_redesign_banner_at IS NULL`; dismisses via Turbo without page reload; never re-renders for that user.

### Task 14: User-menu unread-dot indicator

- [ ] **Spec first.** Update `spec/views/shared/user_menu_spec.rb` (or create) asserting: (1) when `dismissed_notifications_redesign_banner_at IS NULL`, the Preferences link has the unread-dot class; (2) when present, the link does not.
- [ ] Run — fail.
- [ ] Modify `app/views/shared/_user_menu.html.erb`: add `class="<%= 'after:bg-interactive after:content-empty after:rounded-full after:w-2 after:h-2 after:absolute' if Current.user.preferences.dismissed_notifications_redesign_banner_at.nil? %>"` (or cleaner: use a helper method).
- [ ] Run — pass.
- [ ] **Acceptance:** Dot appears next to Preferences link when banner is undismissed; vanishes after dismissal.

### Task 15: Mobile Playwright system spec at 375×667

- [ ] **Spec first.** Create `spec/system/account/notification_preferences_mobile_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe "Notification preferences (mobile viewport)", type: :system, js: true do
    before { page.driver.browser.set_viewport_size(width: 375, height: 667) }

    it "renders cards stacked vertically with no horizontal scroll" do
      sign_in_as(create(:user))
      visit edit_account_notification_preferences_path

      doc_width = page.evaluate_script("document.documentElement.scrollWidth")
      client_width = page.evaluate_script("document.documentElement.clientWidth")
      expect(doc_width).to be <= client_width
    end

    it "passes axe-core AAA at mobile viewport" do
      sign_in_as(create(:user))
      visit edit_account_notification_preferences_path
      expect(page).to be_axe_clean.for_wcag_level_aaa
    end
  end
  ```
- [ ] Run — should pass on the new view (validates Phase 1's mobile fitness).
- [ ] **Acceptance:** No horizontal scroll at 375×667; AAA-clean at mobile viewport.

### Task 16: Remove obsolete locale keys + clean up

- [ ] Audit `config/locales/en/notifications.en.yml` for keys no longer referenced:
  - `notifications.preferences.master_section`, `notifications.preferences.master_help` (the v1 DND copy)
  - `notifications.preferences.matrix_heading`, `notifications.preferences.matrix_aria`
  - `notifications.preferences.channels.digest` (digest is no longer a separate channel)
  - `notifications.preferences.digest.*` (folded into delivery_methods.email)
- [ ] Remove with explicit commit explaining what's gone.
- [ ] Add new keys per Task 12.
- [ ] Verify via `mise exec -- bin/rails runner 'puts I18n.t("notifications.preferences", default: "MISSING")'` that the namespace still resolves.
- [ ] **Acceptance:** No "translation missing" warnings on the preferences page; no orphaned keys.

### Task 17: Final integration sweep

- [ ] Run full suite: `mise exec -- bundle exec rspec`. Expect 1601 + new specs, 0 failures.
- [ ] Check `bin/rails routes -c notification_preferences` — verify all expected routes exist.
- [ ] Verify the migration is reversible: `mise exec -- bin/rails db:rollback` + `db:migrate` round-trip clean.
- [ ] Manual smoke test in browser: sign in, hit `/account/notification_preferences/edit`, toggle each preference, verify each persists, verify auto-submit announcement still fires (PR #74 work).
- [ ] **Acceptance:** Full suite green; routes complete; migration round-trips; manual smoke covers happy path.

### PR-3 merge checklist

- [ ] All ten tasks committed atomically per Conventional Commits.
- [ ] Branch is `feat/preferences-redesign`.
- [ ] Lefthook pre-push passes (RSpec + Rubocop + Brakeman + tailwind_build).
- [ ] PR description references the spec doc + this plan + the four resolved open questions.
- [ ] CI green.
- [ ] Mobile system spec passes at 375×667.
- [ ] Migration runs cleanly on a fresh DB AND round-trips via `db:rollback`.
- [ ] No new gems added.
- [ ] No service objects added.
- [ ] All UI text uses I18n keys.
- [ ] Pundit unchanged (no new policies needed).

---

## Verification (post-PR-3)

After all three PRs merge:

- [ ] Visual confirmation in browser at desktop (1280×800) and mobile (375×667).
- [ ] Verify timezone beacon writes for a fresh test user with no timezone set.
- [ ] Verify a user with an explicit timezone is not overwritten.
- [ ] Verify quiet hours: enable, set start/end straddling current time, deliver a non-security notification, assert no email; deliver a security notification, assert email arrives.
- [ ] Verify migration banner appears once, dismisses, and never re-appears.
- [ ] Verify user-menu dot appears for undismissed users, vanishes after dismissal.
- [ ] Run a panel review on the merged work to surface anything we missed (per the project's pattern with PRs #72/#73/#74).
- [ ] Update memory: mark `project_panel_review_findings.md` items if any are addressed indirectly (e.g., item 9 `normalize_retention` is in the same controller — already addressed in PR #73).

---

## Out-of-scope for this plan (future work)

- Phase 3: Sounds + Desktop Notifications (`Notification.requestPermission()` + audio playback). Separate spec + plan.
- Per-weekday Quiet Hours schedule.
- Ad-hoc DND override ("Pause for 1h").
- Real Web Push (VAPID, service worker, subscription model).
- Cross-tab read-state sync (deferred from v1).
- Push toggle in the Delivery Method card (not rendered until real push exists).
