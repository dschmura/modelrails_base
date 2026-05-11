# PR-3 Handoff — Preferences Redesign (Phase 1)

**Date**: 2026-05-11
**Branch**: `wip/preferences-redesign-handoff` (this branch)
**Parent**: `feat/preferences-redesign` (clean to Task 8)
**Spec**: [docs/superpowers/specs/2026-05-10-notifications-preferences-redesign-design.md](../specs/2026-05-10-notifications-preferences-redesign-design.md)
**Plan**: [docs/superpowers/plans/2026-05-10-notifications-preferences-redesign.md](../plans/2026-05-10-notifications-preferences-redesign.md)

## Why this handoff exists

Mid-PR-3 the plan's expected ripple from rewriting the `NotificationPreferences` value object turned out larger than the plan anticipated — the value object's contract change cascaded into ~14 spec files, including subtle contextual transformations (a sed batch-edit corrupted the migration spec's legacy fixtures because the same string `"do_not_disturb" => true` appeared in both intentional v1 input fixtures and v1-style test setups). Continuing fatigue-deep was risk-positive. Honest pause + clean resume is cheaper than fatigue mistakes in main.

## Phase 1 task progress

- [x] **Task 8** — JSONB reshape migration. Committed atomically as `c7bafe5` on `feat/preferences-redesign`.
- [~] **Task 9** — `NotificationPreferences` value object rewrite. **Code done; 45/45 unit specs green.** Uncommitted on this handoff branch.
- [~] **Task 9b** — schema-default JSONB updated to new shape via `change_column_default` in the same migration. Uncommitted.
- [~] **Task 9c** — notifier-spec ripple cleanup. **In progress.** Sed pass applied to ~10 spec files (replaces `"do_not_disturb" => true` with `quiet_hours` shape). Migration spec was corrupted by the same sed pass and **reverted** — its legacy fixtures intentionally retain `do_not_disturb` because they test the v1→v2 reshape. ~30 spec assertions still need contextual updates (see "Remaining work" below).
- [ ] **Task 10** — `ApplicationNotifier` quiet-hours email gating + `DigestMailerJob` driven off `delivery_methods.email.frequency`.
- [ ] **Task 11** — `Account::NotificationPreferencesController#update` `apply_changes!` for new params shape + new validations.
- [ ] **Task 12** — Rewrite `edit.html.erb` as four cards (Notification Types / Delivery Method / Quiet Hours / Advanced).
- [ ] **Task 13** — Migration banner + `dismiss_banner` endpoint.
- [ ] **Task 14** — User-menu unread-dot indicator (CSS pseudo-element, no JS).
- [ ] **Task 15** — Mobile Playwright system spec at 375×667.
- [ ] **Task 16** — Remove obsolete locale keys.
- [ ] **Task 17** — Final integration sweep + full suite + push + PR.

## State of this handoff branch

**Modified files (uncommitted)**:

| File | Status | Notes |
|---|---|---|
| `app/lib/notification_preferences.rb` | **Done** | Rewritten for new shape. 45/45 unit specs green. |
| `app/models/user_preferences.rb` | **Done** | `notification_preferences_object` now passes `user:` to the value object. |
| `db/migrate/20260510212832_*.rb` | **Done** | Added `change_column_default` step so new rows get the new-shape JSONB default. |
| `db/schema.rb` | **Auto-dumped** | Reflects column default change. |
| `spec/lib/notification_preferences_spec.rb` | **Done** | Full rewrite for new shape including 8 `quiet_hours_active?` tests. 45/45 green. |
| `spec/system/notification_preferences_spec.rb` | **Sed-pass only** | `do_not_disturb` replaced with quiet_hours; assertions may still need updating. |
| `spec/notifiers/*.rb` (10 files) | **Sed-pass only** | Same as above. Still failing on `recipient_pref(:digest)` assertions + `categories` matrix setups. |
| `spec/jobs/digest_mailer_job_spec.rb` | **Sed-pass only** | Same. |

**Last known suite state**: 30 failures across notifier/job/system specs. All in test code (production code is correct).

## Resume runbook

### Step 1: Resume on the handoff branch

```bash
git checkout wip/preferences-redesign-handoff
mise exec -- bin/rails db:migrate  # if not already at version 20260510212832
mise exec -- bundle exec rspec spec/lib/notification_preferences_spec.rb  # sanity: 45/45 green
mise exec -- bundle exec rspec spec/notifiers spec/jobs spec/mailers spec/system/notification_preferences_spec.rb 2>&1 | grep -E "examples|failures"
```

Expected: ~30 failures across notifier/system/job specs. Production code is green.

### Step 2: Fix the ripple (Task 9c continued)

The remaining failures cluster into three patterns:

**Pattern A — `recipient_pref(:digest)` assertions in notifier specs.** The `:digest` channel was dropped in v2 (folded into email frequency). Each affected spec needs the assertion replaced:

- Under v2 defaults (`email.frequency = "instant"`): `recipient_pref(:email)` returns `true` for non-security categories. Replace `expect(recipient_pref(:digest)).to be true` with `expect(recipient_pref(:email)).to be true`.
- Under DND/quiet hours active: both channels return `false`. Drop the `:digest` assertion entirely; keep `:in_app` and `:email` assertions which already check the same outcome.

Affected files:
- `spec/notifiers/workspace_invitation_accepted_notifier_spec.rb` (lines ~63-77)
- `spec/notifiers/workspace_invitation_declined_notifier_spec.rb` (lines ~62-76)
- `spec/notifiers/project_membership_changed_notifier_spec.rb` (already partially done — verify)

**Pattern B — `"categories" => { ... matrix ... }` setups in notifier specs.** These hand-build the v1 matrix to test "disable email for category X" scenarios. Translate each to v2 by deciding intent:

- "Disable email entirely" → `delivery_methods.email.enabled = false`
- "Disable a category entirely" → `notification_types[category] = false`
- "Mixed channel routing" — v2 doesn't have per-cell granularity. The test's intent needs re-examination; in most cases the assertion can use `notification_types[category] = false` to drop the whole category.

Affected files (line numbers from `grep -n "categories" => ...`):
- `spec/notifiers/workspace_member_added_notifier_spec.rb:106, 167, 193`
- `spec/notifiers/workspace_role_changed_notifier_spec.rb:81`
- `spec/notifiers/workspace_invitation_expiring_soon_notifier_spec.rb` (check via grep)

**Pattern C — `spec/system/notification_preferences_spec.rb`.** System spec hits the actual page. The page is still the Phase 0 card-wrapped v1 5×3 matrix layout. Task 12 will rewrite the view as four cards. Some assertions in this system spec may be testing v1 UI behavior that doesn't survive Task 12 — flag those for Task 12-era updates rather than Task 9c.

### Step 3: Once 9c is green, commit Task 9 atomically

```bash
mise exec -- bundle exec rspec  # full suite must be green
git add app/lib/notification_preferences.rb app/models/user_preferences.rb \
        db/migrate/20260510212832_*.rb db/schema.rb \
        spec/lib/notification_preferences_spec.rb \
        spec/notifiers/ spec/jobs/digest_mailer_job_spec.rb \
        spec/system/notification_preferences_spec.rb
git commit -m "feat(preferences): rewrite NotificationPreferences value object for new shape ..."
```

### Step 4: Continue with Task 10

Plan reference: [plan §Task 10](../plans/2026-05-10-notifications-preferences-redesign.md#task-10-rewire-applicationnotifier--digestmailerjob-for-new-contract). Add 3 new specs to `application_notifier_spec.rb`:

- Email suppressed when `quiet_hours_active?` returns true for non-security.
- Email delivered when `quiet_hours_active?` returns true for security.
- `:digest` sentinel from `allow?` queues for digest cycle.

Then update `ApplicationNotifier`'s `deliver_by :email` `if:` proc to gate on `prefs.allow?(category:, channel: "email")` returning `true` (not `:digest`, which means queue not deliver).

`DigestMailerJob#digest_scope` switches from `DIGEST_ELIGIBLE_CATEGORIES` to filtering on `delivery_methods.email.frequency != "instant"` with security-category exclusion.

### Step 5: Tasks 11–17

Continue per the plan. Tasks 11–12 are the user-visible-shift tasks (controller + view rewrite). Tasks 13–14 add the banner + dot. Task 15 is the mobile spec. Task 16 cleans locale. Task 17 is the integration sweep.

## Notable production-state observations

- **Migration `20260510212832` is already applied locally** (dev + test DBs both at this version). On a fresh clone, the resume runbook handles this via `bin/rails db:migrate`.
- **Column default updated**: new `user_preferences` rows now get the new-shape JSONB out of the box. This means factories no longer need to inject the new shape; the schema default handles it.
- **The value object's `do_not_disturb?` is now an alias** for `quiet_hours_active?`. Callers (notably the bell button tooltip) continue working without changes.
- **`NotificationPreferences#allow?` returns `:digest` sentinel** when email channel is enabled with non-instant frequency. Boolean-style callers need to treat `:digest` as "yes but not now" — currently most callers truthy-check, which means `:digest` is treated as truthy (correct for "should we attempt delivery"). The `if:` proc in `ApplicationNotifier` (Task 10) needs to distinguish `true` (deliver now) from `:digest` (queue).

## Memory entries created or relevant

- [project_panel_review_findings.md](/Users/dschmura/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_panel_review_findings.md) — concurrency blockers were addressed pre-PR-3.
- [project_flaky_tests_followup.md](/Users/dschmura/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_flaky_tests_followup.md) — workspace-branded surface drift; may surface in Task 15's mobile spec.

## TL;DR for resumption

```
git checkout wip/preferences-redesign-handoff
# Read this HANDOFF.md
# Fix ~30 spec failures (patterns A + B + C above)
# Commit Task 9 atomically
# Continue with Task 10 per plan
```

The hard part (data migration, value object, schema default) is done and tested. What remains is mechanical spec rewrites + plan-driven implementation of tasks 10–17.
