# Notifications Preferences Redesign — Design Spec

**Goal:** Redesign `/account/notification_preferences/edit` from the v1 5×3 matrix (categories × channels) to a parallel-list IA that scales on mobile, communicates a clearer mental model, and absorbs the digest system as a sub-mode of the Email channel. Add Quiet Hours v1 (single start/end time, wraps midnight). Reshape the `notification_preferences` JSONB column to match. Capture browser timezone automatically and surface it on the preferences page. Visual treatment follows the "Lumina" sample: rounded-2xl white cards with icon-tile rows, single-column max-w-3xl shell.

**Scope:** Three sub-phases, single feature track:
- **Phase 0** — Visual foundation. Reusable `_preferences_card` + `_preferences_row` partials with the new card aesthetic. OKLCH AAA mappings for the slate/gray/blue palette. No behavior changes.
- **Phase 0.5** — Timezone beacon. Stimulus controller reads `Intl.DateTimeFormat().resolvedOptions().timeZone` on layout connect; POSTs to a new endpoint that writes to `user_preferences.timezone` only when nil. Preferences page surfaces detected timezone with a Change action.
- **Phase 1** — JSONB reshape + IA shift + Quiet Hours + view replacement. Drives off the new shape; backfills existing user data deterministically; lands the new card layout end-to-end.

Push notifications, Sounds, and Desktop Notifications are explicitly out of scope (see Non-Goals).

This SPEC was produced via `/gsd-spec-phase` after locked-decision conversation 2026-05-10. Ambiguity score on completion: **0.103** (gate ≤ 0.20). All four dimension minimums met.

---

## Motivation

The v1 notifications track shipped a working preferences page but with a 5×3 matrix as its central control (5 categories × 3 channels — `in_app`, `email`, `digest`). Two failure modes surfaced in real use:

1. **Mobile collapse.** A 5×3 grid has no good responsive behavior. Horizontal scroll hides half the controls below the fold; column-stacking reduces it to two parallel lists pretending to be a matrix. Once you accept "this must stack on mobile," the matrix was load-bearing on desktop only.
2. **Granularity nobody uses.** The matrix optimizes for a power user who wants different channel routing per category ("yes email security, no email workspace"). In practice, users either *care about a category* or *don't*, and separately *receive email* or *don't*. Slack, Linear, Gmail all converged on parallel-list IA for the same reason: the per-cell matrix is theoretical granularity that doesn't match how users tune notifications.

The parallel-list IA — **Notification Types** (5 categories) + **Delivery Method** (2 channels) + **Quiet Hours** + **Advanced** — also opens space for two features the v1 design couldn't cleanly accommodate:

- **Quiet Hours**: time-based suppression (don't notify me 22:00–07:00) which is closer to how humans think about being-bothered than category-based suppression.
- **Email as frequency**: rather than a separate Digest section, Email becomes a frequency selector (`Instant` / `Daily digest` / `Weekly digest`). The DigestMailerJob infrastructure from v1 stays; only the framing changes.

A four-question design conversation (Jason Fried on backfill, panel of 5 on security bypass, two-question pass on remaining schema details) locked all major decisions before this spec was written.

---

## Non-Goals

- **Push notifications of any kind.** Real Web Push (VAPID + service worker + subscription endpoints) is deferred indefinitely. Browser Notification API (in-tab only) is deferred to a separate Phase 3. The current preferences UI explicitly omits a Push toggle. Rationale: scope expansion risk — the v1 notifications track already explicitly deferred Web Push (see `2026-04-30-notifications-design.md` decision #10).
- **Sounds.** Audio playback on broadcast arrival is deferred to Phase 3 (separate spec). Requires audio asset selection, autoplay-restriction handling, and a Stimulus controller; orthogonal to the IA shift this spec covers.
- **Desktop Notifications.** `Notification.requestPermission()` flow + permission-state UI deferred to Phase 3. Same reasoning.
- **Per-weekday Quiet Hours schedule.** The Lumina sample shows an MTWTFSS day picker. v1 ships single start/end same-every-day. The schema is shaped so per-weekday is an additive future change, not a breaking one.
- **Ad-hoc DND override.** Slack-style "Pause notifications for 1h / 4h / until tomorrow" buttons are not in v1. The recurring quiet-hours schedule is the only DND mechanism.
- **Per-category-per-channel granularity.** The matrix is gone. A type that's enabled goes to all enabled channels. A user who wanted "email for security, not for workspace activity" loses that exact control — the email frequency selector (Instant vs Daily) handles the "don't flood my inbox" concern instead.
- **`allow_urgent` toggle in v1 UI.** Panel verdict: a toggle that has no runtime effect (because security is structurally always-on regardless) is deceptive UI. Store `allow_urgent: true` as default in JSONB for future-proofing; do not render the control. Surface a fixed-text reassurance instead: *"Security alerts will always come through."*
- **Sidebar layout.** Single-column max-w-3xl shell only. Sidebar deferred until there are 3+ user-preference sections to navigate between.
- **Migration to a new preferences engine / gem.** Stay on the existing JSONB-on-UserPreferences pattern. This is a column-reshape, not an infrastructure change.

---

## Design decisions (locked during brainstorming)

| # | Decision | Choice | Reasoning |
| - | -------- | ------ | --------- |
| 1 | Visual language | Sample-matching: `rounded-2xl` white cards, icon-tile rows, `divide-y` between rows, slate-900/gray-500 mapped to existing OKLCH AAA tokens, single-column `max-w-3xl` | Sample-faithful. Mobile-friendly card stack. Existing AAA palette reused; no new tokens required (see Phase 0). |
| 2 | Information architecture | Parallel lists (Types card + Delivery Method card) rather than 5×3 matrix | Real-world IA. Mobile-friendly by structure, not by responsive trick. Matches Slack/Linear/Gmail conventions. |
| 3 | Digest fate | Folded into Email channel as `frequency: instant / daily / weekly` selector. DigestMailerJob infrastructure unchanged; drives off `delivery_methods.email.frequency` | Honors shipped work from PR-5 (~600 lines stays); aligns IA with mental model ("Email" is one place with a delivery cadence, not two unrelated controls). |
| 4 | Quiet Hours v1 | Single `start`/`end` time pair, wraps midnight via modular interval check, suppresses all non-security notifications when active | Simplest-and-extendable. Per-weekday + ad-hoc DND are additive future changes (schema shape supports without migration). |
| 5 | Quiet Hours timezone | Reads `user.preferences.timezone`. Captured automatically via JS `Intl.DateTimeFormat().resolvedOptions().timeZone` on layout connect (Phase 0.5). User can override via Change action. | Browser-detected timezone is reliable (reads OS clock, VPN-immune). Surfacing the detected value gives users transparency + control. |
| 6 | Security bypass | Security category ALWAYS bypasses Quiet Hours regardless of `allow_urgent` value. Do not render the `allow_urgent` toggle in v1 UI. Store `allow_urgent: true` as default for future-proofing. | Panel verdict (DHH, Léonie, Dave T., Chris Oliver, Aaron Patterson). Toggle without runtime effect is deceptive UI. Fixed-text reassurance "Security alerts will always come through" instead. |
| 7 | Security email frequency | Security emails ALWAYS send instantly regardless of `delivery_methods.email.frequency`. Mirror of decision #6 — security is structurally always-on at every layer. | A "your password changed" email sitting in a 24-hour digest queue is a security failure. Always instant. |
| 8 | Retention placement | `retention_days` moves into the new "Advanced" card in v1. Phase 3 will add Sounds + Desktop Notifications to the same card. | Advanced card becomes real in Phase 1 rather than being a Phase 3 placeholder. Single configure-once setting; doesn't warrant prime real estate. |
| 9 | Backfill mapping | Jason-Fried-flavored OR collapse: `notification_types[c]` = OR across old row; `delivery_methods.{in_app,email}.enabled` = OR down old columns; `email.frequency` = `"daily"` if ANY old category had `digest: true`, else `"instant"` | Most generous reading of user intent. Four lines of logic. No "we migrated your settings" modal. Some users lose per-cell granularity; that's the accepted cost of the IA shift. |
| 10 | Migration banner | One-line, dismissable, per-user. Copy: "We simplified notifications — take a moment to review your preferences." Stored as `user_preferences.dismissed_notifications_redesign_banner_at` timestamp. Never re-shown once dismissed. | Gentle signal that things changed without making migration a ritual. |
| 11 | Push/Sounds/Desktop in v1 | Not rendered in the UI at all. Schema does not allocate keys for them. Phase 3 (future spec) adds them additively. | Honest absence > toggles for non-existent features. |
| 12 | Granularity loss mitigation | The email frequency selector (`Daily` / `Weekly`) covers the most common "don't flood my inbox" need without per-cell granularity. No matrix expander. | Accept the trade-off explicitly. If a real user complaint emerges post-ship, an additive future feature can re-introduce granularity. |

---

## Architecture

### Target JSONB shape

```json
{
  "notification_types": {
    "security":            true,
    "account_access":      true,
    "workspace_activity":  true,
    "project_activity":    true,
    "billing":             true
  },
  "delivery_methods": {
    "in_app": { "enabled": true },
    "email":  { "enabled": true, "frequency": "instant" }
  },
  "quiet_hours": {
    "enabled":      false,
    "start":        "22:00",
    "end":          "07:00",
    "allow_urgent": true
  },
  "retention_days": 90
}
```

**Allowed values:**
- `notification_types.*` — boolean. Five fixed keys (no other category names accepted by the controller).
- `delivery_methods.in_app.enabled` — boolean.
- `delivery_methods.email.enabled` — boolean.
- `delivery_methods.email.frequency` — one of `"instant"`, `"daily"`, `"weekly"` (string).
- `quiet_hours.enabled` — boolean.
- `quiet_hours.start`, `quiet_hours.end` — `"HH:MM"` 24-hour string. Validated against `\A([01]\d|2[0-3]):([0-5]\d)\z`.
- `quiet_hours.allow_urgent` — boolean (currently inert; never read by v1 code).
- `retention_days` — integer (one of 30/60/90/180/365) or null (means "never auto-delete").

**Removed keys (compared to v1):**
- `do_not_disturb` — replaced by `quiet_hours.enabled` + schedule. NOTE: this means master DND is gone in v1 as a separate concept; quiet hours IS the DND mechanism. To replicate "DND right now," the user enables quiet hours with a current-time window. (Ad-hoc "DND for 1h" is deferred — see Non-Goals.)
- `categories` (the 5×3 matrix) — replaced by `notification_types` + `delivery_methods`.
- `digest` (the separate digest section: cadence, hour_local) — folded into `delivery_methods.email.frequency`.

### Decision tree: should a notification deliver?

For a notification with category C, channel CH, current time T:

```
1. Is C == "security"? → YES → always deliver, ignore all preferences below.
2. Is notification_types[C] == true? → NO → drop.
3. Is delivery_methods[CH].enabled == true? → NO → drop.
4. If CH == "email" and delivery_methods.email.frequency != "instant":
     queue for next digest cycle (existing DigestMailerJob infrastructure).
   Else: deliver now (with quiet-hours gate below).
5. Is quiet_hours.enabled == true AND quiet_hours_active?(now: T) == true?
   → YES AND C != "security" → drop (or defer to "after quiet hours end" — see open question Q1).
   → NO → deliver.
```

### `quiet_hours_active?` contract

```ruby
def quiet_hours_active?(now: Time.current)
  return false unless quiet_hours[:enabled]
  zone = ActiveSupport::TimeZone[user.preferences.timezone] || Time.zone
  cur  = zone.now.strftime("%H:%M")
  s, e = quiet_hours[:start], quiet_hours[:end]
  s <= e ? (cur >= s && cur < e) : (cur >= s || cur < e)
end
```

Required tests (TDD red-then-green):
1. **In-window same-day**: `start=09:00, end=17:00, now=13:00 → true`.
2. **In-window overnight (after start)**: `start=22:00, end=07:00, now=23:30 → true`.
3. **In-window overnight (before end)**: `start=22:00, end=07:00, now=06:00 → true`.
4. **Out-of-window same-day**: `start=09:00, end=17:00, now=20:00 → false`.
5. **Out-of-window overnight**: `start=22:00, end=07:00, now=10:00 → false`.
6. **Disabled**: `enabled=false → false regardless of times`.
7. **Boundary**: `start=09:00, end=17:00, now=17:00 → false` (end is exclusive).
8. **Missing timezone**: `user.preferences.timezone=nil → falls back to Time.zone, does not raise`.

### Timezone beacon endpoint contract

- **Endpoint**: `POST /account/preferences/timezone`
- **Params**: `{ timezone: "America/New_York" }`
- **Auth**: requires authenticated session.
- **Validation**: timezone must be in `ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name)` (IANA identifiers).
- **Behavior**:
  - If `user.preferences.timezone.blank?` → write the provided value.
  - If `user.preferences.timezone.present?` → no-op (preserves explicit user choice).
- **Response**:
  - `204 No Content` on success (write or no-op).
  - `422 Unprocessable Entity` on invalid timezone identifier.
- **Pundit**: scoped via `Current.user.preferences` — no policy class needed (operates on `current_user`'s own row).
- **Triggered by**: Stimulus `timezone_beacon_controller` connected to `<body>` in the layout. Fires once per page load. Idempotent at server-side; no harm in repeated calls.

### Migration shape

1. **Schema change**: add `dismissed_notifications_redesign_banner_at` column (`datetime`, nullable) to `user_preferences`.
2. **Data migration** (one-time, in same migration via `up`):
   - For each existing `user_preferences` row, read the v1 JSONB, compute the new shape via the backfill rules, write it back.
   - Backfill the security floor: ensure `notification_types.security = true` regardless of legacy input.
3. **Removed keys** are dropped in the data migration. Going backward (rollback) is best-effort — `down` restores the v1 schema-default JSONB; user-specific v1 settings are lost on rollback.

### Card structure (Phase 0 partials)

`app/views/shared/_preferences_card.html.erb` — strict locals: `title:`, `description: nil`, `block`. Renders the rounded-2xl card shell with a title row + optional description + the block content. Block content is typically an unordered list of `_preferences_row` partials.

`app/views/shared/_preferences_row.html.erb` — strict locals: `icon_name:`, `icon_color:`, `title:`, `description:`, `control:`. Renders one row: icon tile (left), title + description (middle), control (right — toggle / select / time input passed as block or partial). Uses `divide-y` semantics via wrapping `<li>` element.

Both partials are reusable for future user-preferences sections (theme, language, profile-visibility, etc.) — that's the Phase 0 value beyond just notifications.

---

## Phase boundaries & acceptance criteria

### Phase 0 — Visual foundation

**In scope:**
- New partials: `shared/_preferences_card.html.erb`, `shared/_preferences_row.html.erb` with strict locals.
- OKLCH semantic-token mapping for the slate-900 / gray-50 / gray-100 / gray-300 / gray-400 / gray-500 / blue-50 / blue-600 palette where existing tokens don't already cover (audit first; reuse rather than add when possible).
- Refactor existing `edit.html.erb` to use the new partials, preserving the current 5×3 matrix as content. **No behavior change.** Pure visual swap.
- Component-level specs for the partials (locals contract, accessibility roles).

**Out of scope:**
- IA changes (still the matrix).
- JSONB reshape.
- Quiet Hours.
- Timezone beacon.

**Acceptance criteria (pass/fail):**
- [ ] `shared/_preferences_card.html.erb` exists and renders with strict locals `title:`, `description: nil`, and a block.
- [ ] `shared/_preferences_row.html.erb` exists and renders with strict locals `icon_name:`, `icon_color:`, `title:`, `description:`, `control:`.
- [ ] `app/views/account/notification_preferences/edit.html.erb` uses the new partials.
- [ ] WCAG 2.2 AAA contrast verified for every visible text/background combination in the new layout (verified via axe-core in a system spec).
- [ ] Existing 11 request specs in `spec/requests/account/notification_preferences_spec.rb` pass unchanged.
- [ ] No new tokens added if an existing OKLCH AAA token already covers the role (audit report referenced in commit message).
- [ ] Lefthook pre-push passes (RSpec + brakeman + rubocop + tailwind_build).

### Phase 0.5 — Timezone beacon

**In scope:**
- `POST /account/preferences/timezone` endpoint (see contract above).
- `timezone_beacon_controller.js` Stimulus controller, registered on `<body>` in `application.html.erb`.
- "Detected timezone" surface on `/account/notification_preferences/edit` with a Change action that opens a typeahead picker over `ActiveSupport::TimeZone.all` results.
- Request specs for the endpoint (auth, validation, idempotency, no-overwrite-of-explicit-value).
- System spec for the JS detection round-trip (sign-in → beacon fires → user_preferences.timezone populated).

**Out of scope:**
- Migrating users who already have a timezone (no-op).
- Per-page timezone overrides.
- Cross-tab timezone sync.

**Acceptance criteria (pass/fail):**
- [ ] `POST /account/preferences/timezone` writes when `user.preferences.timezone` is nil.
- [ ] `POST /account/preferences/timezone` is a no-op when `user.preferences.timezone` is present.
- [ ] `POST /account/preferences/timezone` returns 422 for invalid IANA identifiers.
- [ ] `POST /account/preferences/timezone` requires authenticated session (redirects to sign-in otherwise).
- [ ] Stimulus controller fires once per page load and posts the detected zone.
- [ ] Preferences page renders the detected timezone with a visible Change action.
- [ ] All UI text uses I18n keys.
- [ ] Lefthook pre-push passes.

### Phase 1 — JSONB reshape + IA + Quiet Hours + view replacement

**In scope:**
- Migration: data-only reshape of `user_preferences.notification_preferences` to the target JSONB shape (backfill rules above). Adds `dismissed_notifications_redesign_banner_at` column.
- `NotificationPreferences` value object: rewrite `allow?` to drive off `notification_types` + `delivery_methods` + `quiet_hours`. Add `quiet_hours_active?(now:)`. Remove `do_not_disturb?`; replace usages with `quiet_hours_active?`.
- Controller: `Account::NotificationPreferencesController#update` validates and accepts the new params shape. Update `apply_changes!` for the new keys. Retention validation logic from PR #73 kept.
- View: `edit.html.erb` rewritten to render four cards — Notification Types, Delivery Method, Quiet Hours, Advanced — using the Phase 0 partials.
- Migration banner partial + dismiss endpoint (`POST /account/notification_preferences/dismiss_banner` → writes `dismissed_notifications_redesign_banner_at: Time.current`).
- `DigestMailerJob` driven off `delivery_methods.email.frequency` instead of legacy `digest.cadence`. Security always-instant short-circuit added if not already present.
- New `_navigation` link / no-op (preferences page already linked).

**Out of scope:**
- Push notifications (any form).
- Sounds.
- Desktop Notifications.
- Per-weekday quiet hours.
- Ad-hoc DND override.
- Allow-urgent toggle UI.
- Sidebar layout.

**Acceptance criteria (pass/fail):**
- [ ] Migration reshapes every existing `user_preferences.notification_preferences` row deterministically per the backfill rules. Test: spec that seeds 4 representative legacy shapes and asserts the post-migration shape on each.
- [ ] `dismissed_notifications_redesign_banner_at` column added; nullable; no default.
- [ ] `NotificationPreferences#allow?(category:, channel:)` returns the correct boolean for every (category, channel) combination per the decision tree above.
- [ ] `NotificationPreferences#quiet_hours_active?(now:)` satisfies all 8 test cases in the spec above.
- [ ] Security category bypasses `quiet_hours_active?` regardless of return value (decision tree step 1).
- [ ] `delivery_methods.email.frequency: "daily"` queues security emails as **instant** anyway (decision #7).
- [ ] `Account::NotificationPreferencesController#update` rejects invalid `quiet_hours.start` / `quiet_hours.end` formats with 422.
- [ ] `Account::NotificationPreferencesController#update` rejects invalid `email.frequency` values with 422 (allowed: instant/daily/weekly).
- [ ] `Account::NotificationPreferencesController#update` rejects unknown `notification_types` keys with 422.
- [ ] `DigestMailerJob` skips users whose `delivery_methods.email.frequency` is `"instant"`.
- [ ] `DigestMailerJob` runs at the user's configured cadence for `"daily"` / `"weekly"`.
- [ ] Migration banner renders when `dismissed_notifications_redesign_banner_at` is nil; vanishes after `POST .../dismiss_banner`.
- [ ] All 11 existing `notification_preferences_spec.rb` request specs are updated to the new params shape and pass.
- [ ] At least 8 new specs for `quiet_hours_active?` (3 in-window + 2 out-of-window + 1 disabled + 1 boundary + 1 missing-timezone).
- [ ] At least 4 new specs for the backfill migration (4 representative legacy shapes).
- [ ] WCAG 2.2 AAA contrast verified for the full new view (axe-core system spec).
- [ ] Pundit authorization on the controller (unchanged).
- [ ] All UI text uses I18n keys; locale file additions follow `notifications.preferences.*` namespace.
- [ ] Lefthook pre-push passes.
- [ ] Full suite ≥ 1601 examples (current count post-PR-#74) + new spec count, 0 failures.

---

## Constraints

- **TDD discipline**: failing spec first on every change, including the migration. The migration's backfill rules are the most failure-prone surface; tests must cover every documented legacy → new mapping rule. (Per `feedback_strict_tdd_no_exceptions.md` memory.)
- **WCAG 2.2 Level AAA**: every text/background contrast meets 7:1; interactive targets ≥ 44×44px; focus rings visible at 3:1 against adjacent colors; aria-labels on all interactive elements; live-region announcements preserved from PR #74.
- **Conventional Commits**: `feat(notifications):`, `chore(a11y):`, `fix(security):` etc. Atomic commits per phase boundary at minimum.
- **No `LEFTHOOK=0`**: per `feedback_never_skip_lefthook.md`.
- **No service objects**: per `feedback_agent_os_overengineered.md` — the migration, controller, value object, view, and partials handle this without orchestrating 3+ operations.
- **No ViewComponents**: partials with strict locals only — the new card/row partials are reused across views (preferences sections beyond notifications) so they're real candidates, but the project convention is partials-first.
- **I18n for all UI text**: no hardcoded strings in views.
- **Pundit authorization**: existing `account_notification_preferences_path` already gated by authenticated session; no new policy class needed.
- **Mailer `deliver_later` outside transactions**: existing `DigestMailerJob` already conforms; preserve when refactoring.
- **No framework documentation in code comments**: per `feedback_no_framework_docs_in_code.md` — comments explain project decisions only.

---

## Open questions (flagged for plan-phase)

These were considered during spec-phase but deliberately left for plan-phase to answer because they're "how" questions:

**Q1 — Quiet hours: drop or defer?** When `quiet_hours_active?` returns true, do we *drop* the non-security notification entirely, or *defer* it to deliver immediately after the window ends? Drop is simpler (no scheduler state). Defer matches user expectation but requires Solid Queue scheduling of "deliver this notification at quiet_hours.end." Plan-phase decision; spec-phase locks both as acceptable. Recommendation: **drop in v1** (user can check the in-app list when they wake up; missed real-time push is what quiet hours are *for*).

**Q2 — Migration banner location.** Top of the preferences page, or a global flash-style banner on every page until dismissed? Spec-phase suggests preferences-page-only — the message is to "review your preferences," and global noise on every page would dilute that ask.

**Q3 — Timezone picker UI library.** `ActiveSupport::TimeZone.all` returns 400+ zones. A naive `<select>` is overwhelming. Plan-phase needs to decide: typeahead (Stimulus + filter), grouped optgroups by region, or limited starter list with "show more." Spec-phase prefers typeahead for UX but doesn't lock the implementation.

**Q4 — Mobile testing strategy.** This redesign is partly motivated by mobile collapse of the matrix. Plan-phase should specify whether we want explicit mobile-viewport system specs (Playwright `setViewportSize`) or trust the visual design + responsive CSS. Spec-phase asks for at minimum one mobile-viewport spec on the new view.

---

## Out-of-band: relationship to existing memory entries

- **`project_panel_review_findings.md`** — this work indirectly addresses panel item "Modal/theme/identity-picker Stimulus simplification" (deferred, triggered when controllers gain new responsibilities) for the timezone beacon controller. New controller is intentionally tiny (~10 lines), not a violation.
- **`project_flaky_tests_followup.md`** — the workspace-branded surface AAA debt is unrelated to this work but may surface again when system specs hit the new view. Pre-existing `DEFERRED_AAA_EXCLUDES` selectors apply.
- **`project_oauth_linking_followups.md`** — unrelated; preserved as historical reference per its frontmatter.
- **`feedback_default_workflow.md`** — this spec was produced via the project's spec-first convention (`docs/superpowers/specs/`) rather than the GSD skill's `.planning/` scaffolding. Both honor "spec-first."

---

## Ambiguity Report

| Dimension | Score | Min | Status |
| --------- | ----- | --- | ------ |
| Goal Clarity | 0.92 | 0.75 | ✓ |
| Boundary Clarity | 0.90 | 0.70 | ✓ |
| Constraint Clarity | 0.90 | 0.65 | ✓ |
| Acceptance Criteria | 0.85 | 0.70 | ✓ |
| **Composite ambiguity** | **0.103** | ≤ 0.20 | ✓ |

All four dimensions exceed their minimums. Composite ambiguity is well below the gate. No dimensions flagged as below-minimum; planner does not need to treat any decision as an assumption.

---

## Next step

```
/gsd-plan-phase  (or the project's plan equivalent at docs/superpowers/plans/)
```

Plan-phase should:
1. Resolve Q1–Q4 (the open "how" questions).
2. Produce per-phase task lists with goal-backward verification.
3. Identify any threat-model concerns for the timezone-beacon endpoint (auth-spoofing? CSRF? — Rails defaults likely sufficient).
4. Map each acceptance criterion above to a specific test file and assertion.
5. Estimate effort per phase (Phase 0: ~half-day, Phase 0.5: ~1 day, Phase 1: ~3 days).
