# PR-3 Handoff — Preferences Redesign (Phase 1)

**Date**: 2026-05-11
**Branch**: `wip/preferences-redesign-handoff` (this branch)
**Parent**: `feat/preferences-redesign` (clean to Task 8)
**Spec**: [docs/superpowers/specs/2026-05-10-notifications-preferences-redesign-design.md](../specs/2026-05-10-notifications-preferences-redesign-design.md)
**Plan**: [docs/superpowers/plans/2026-05-10-notifications-preferences-redesign.md](../plans/2026-05-10-notifications-preferences-redesign.md)

## Why this handoff exists

Mid-PR-3 the plan's expected ripple from rewriting the `NotificationPreferences` value object turned out larger than the plan anticipated — the value object's contract change cascaded into ~14 spec files, including subtle contextual transformations (a sed batch-edit corrupted the migration spec's legacy fixtures because the same string `"do_not_disturb" => true` appeared in both intentional v1 input fixtures and v1-style test setups). Continuing fatigue-deep was risk-positive. Honest pause + clean resume is cheaper than fatigue mistakes in main.

## Split decision (post-pause review panel)

Before resuming, the work was reviewed by a three-reviewer panel (DHH on scope, Dave Thomas on design-intent, Chris Oliver on resumability) synthesized through Sandi Metz + Jim Weirich facilitator lenses. All three independently flagged the same structural issue: **the spec is well-scoped, but PR-3's plan boundary lumped a data-shape refactor (Tasks 8–12) with chrome/polish (Tasks 13–17) into one ship gate.** Splitting at the Task 12 boundary keeps the data shape and UI shipping together while letting banner / dot / mobile / locale cleanup land as a separate, smaller PR.

**The split (now reflected in the plan):**

- **PR-3a** = Tasks 8–12 on branch `feat/preferences-redesign`. Ships "the redesign works end-to-end."
- **PR-3b** = Tasks 13–17 on branch `feat/preferences-redesign-polish` (cut from `main` after PR-3a merges). Ships "the redesign is polished."

**What this changes for the resume runbook below:**

- Steps 1–4 still apply, but the **finish line moves to Task 12**, not Task 17.
- After Task 12 ships as PR-3a, this handoff ends. PR-3b is a clean new session on a clean new branch — no handoff doc needed.
- The PR-3a merge gate adds a "migration round-trip against mixed v1/v2 data" check (panel finding); the PR-3b merge gate is unchanged in substance but separately gated.

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
| --- | --- | --- |
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

### Step 2: Fix the ripple (Task 9c continued) — per-file, no sed

> **Tooling rule (panel finding):** Do not run another sed batch over these spec files. The previous sed pass corrupted `spec/migrations/reshape_notification_preferences_jsonb_spec.rb` because `"do_not_disturb" => true` appears both as intentional v1 input fixture (for testing the v1→v2 reshape) and as v1-style test setup (which needs translation). Sed cannot distinguish. Open each spec file, read the surrounding `let`/`before`/`context`, and translate intent — not strings.

The remaining failures cluster into three patterns. For each pattern, the runbook below gives a concrete before/after pulled from a real spec file in this branch.

---

**Pattern A — `recipient_pref(:digest)` assertions in notifier specs.** The `:digest` channel was dropped in v2 (folded into email frequency). The new contract: `recipient_pref(:email)` returns `true` when email is enabled at any frequency (instant/daily/weekly).

**Concrete before/after** (from [spec/notifiers/workspace_invitation_accepted_notifier_spec.rb:71-77](spec/notifiers/workspace_invitation_accepted_notifier_spec.rb#L71-L77)):

```ruby
# BEFORE (v1 — what's currently failing):
it "permits in-app + digest under default preferences (workspace_activity)" do
  described_class.with(record: invitation).deliver(inviter)
  notification = inviter.notifications.last
  expect(notification.recipient_pref(:in_app)).to be true
  expect(notification.recipient_pref(:digest)).to be true
  expect(notification.recipient_pref(:email)).to be false
end

# AFTER (v2 — drops the :digest assertion; v2 defaults email.frequency = "daily"
# for workspace_activity, so :email is now the relevant assertion):
it "permits in-app under default preferences (workspace_activity)" do
  described_class.with(record: invitation).deliver(inviter)
  notification = inviter.notifications.last
  expect(notification.recipient_pref(:in_app)).to be true
  expect(notification.recipient_pref(:email)).to be true  # was :digest in v1
end
```

**Translation rules:**

- Under v2 defaults with `email.frequency = "instant"`: replace `expect(recipient_pref(:digest)).to be true` with `expect(recipient_pref(:email)).to be true`.
- Under quiet hours active (the test at [workspace_invitation_accepted_notifier_spec.rb:62-69](spec/notifiers/workspace_invitation_accepted_notifier_spec.rb#L62-L69)): both `:in_app` and `:email` already return `false` — the `:digest` assertion can simply be deleted; the surrounding two assertions already prove the right outcome.

**Affected files** (run `grep -n "recipient_pref(:digest)" spec/notifiers spec/system` to enumerate):

- `spec/notifiers/workspace_invitation_accepted_notifier_spec.rb` (lines ~63–77 — example shown above)
- `spec/notifiers/workspace_invitation_declined_notifier_spec.rb` (lines ~62–76 — mirror of accepted)
- `spec/notifiers/project_membership_changed_notifier_spec.rb` (already partially done — verify with grep)

---

**Pattern B — `"categories" => { ... matrix ... }` setups in notifier specs.** These hand-build the v1 5×3 matrix to test "disable email for category X" scenarios. Translate by *intent*, not by mechanical string swap.

**Concrete before/after** (from [spec/notifiers/workspace_member_added_notifier_spec.rb:105-109](spec/notifiers/workspace_member_added_notifier_spec.rb#L105-L109)):

```ruby
# BEFORE (v1 — flipping workspace_activity.email = true in the matrix):
prefs = create(:user_preferences, user: added_user)
categories = prefs.notification_preferences["categories"].deep_dup
categories["workspace_activity"]["email"] = true
prefs.update!(notification_preferences:
  prefs.notification_preferences.merge("categories" => categories))

# AFTER (v2 — intent was "user opts INTO email for workspace_activity";
# in v2 that means notification_types[workspace_activity] = true AND
# delivery_methods.email.enabled = true. Both default true post-migration,
# so the explicit setup is now a no-op — DELETE it. If the test needs
# a non-default state, build it with the v2 shape directly):
prefs = create(:user_preferences, user: added_user)
# (no override needed — v2 defaults are: workspace_activity on, email on @ "daily")
```

**Translation rules by original intent:**

- "Disable email entirely" → `delivery_methods` ⇒ `{ "email" => { "enabled" => false, "frequency" => "instant" }, "in_app" => { "enabled" => true } }`
- "Disable a category entirely" → `notification_types[category] = false`
- "Enable email for category X" → in v2 this is *two* axes (category enabled AND email channel enabled). Both default true post-migration; the explicit setup may be a no-op.
- "Mixed channel routing" — v2 doesn't have per-cell granularity. Re-read the test's behavioral intent (look at the assertion, not the setup); in most cases dropping the category via `notification_types[category] = false` matches the intent.

**Affected files** (run `grep -rn '"categories" =>' spec/notifiers spec/system` to enumerate):

- `spec/notifiers/workspace_member_added_notifier_spec.rb:106, 167, 193`
- `spec/notifiers/workspace_role_changed_notifier_spec.rb:81`
- `spec/notifiers/workspace_invitation_expiring_soon_notifier_spec.rb` (verify with grep)

---

**Pattern C — `spec/system/notification_preferences_spec.rb`.** System spec hits the actual page. At the end of Task 9c the page is still the Phase 0 card-wrapped v1 5×3 matrix layout. Task 12 (in PR-3a) will rewrite the view as four cards. Some assertions in this system spec test v1 UI behavior that does not survive Task 12.

**Decision rule for Task 9c (now):**

1. **Fix in 9c** — any assertion that tests *backend behavior visible through the page* (form submits, persistence, redirect targets, flash messages). These are layout-agnostic; the new four-card layout still surfaces the same form behavior.
2. **Skip in 9c, fix in Task 12** — any assertion that asserts DOM structure of the v1 matrix (e.g., `expect(page).to have_css("table.preferences-matrix")`, `within("tr.security-row")`, references to the v1 digest section). Mark these with a pending tag tied to Task 12:

```ruby
it "renders v1 matrix structure", pending: "rewritten by Task 12 (four-card layout)" do
  expect(page).to have_css("table.preferences-matrix")  # v1-only DOM
end
```

To enumerate, run from the spec file:

```bash
grep -n -E "preferences-matrix|matrix_heading|tr\.|digest-section|master-dnd" spec/system/notification_preferences_spec.rb
```

Any line that matches → skip-with-pending. Any line that doesn't → fix now if failing.

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

### Step 5: Tasks 11–12 (the PR-3a finish line)

Continue per the plan. **The PR-3a finish line is the end of Task 12, not Task 17.** Tasks 13–17 are now PR-3b, a separate PR cut from `main` after PR-3a merges.

- **Task 11** — `Account::NotificationPreferencesController#update`: rewrite `apply_changes!` for the new params shape. Adds validations for `quiet_hours.start` / `quiet_hours.end` (HH:MM regex), `delivery_methods.email.frequency` (one of `instant|daily|weekly`), and `notification_types` keys (must be in `NotificationPreferences::CATEGORIES`).
- **Task 12** — Rewrite `app/views/account/notification_preferences/edit.html.erb` as four cards (Notification Types / Delivery Method / Quiet Hours / Advanced) using the Phase 0 partials. Update the AAA system spec to assert the new structure. This is when Pattern C's pending-tagged assertions get rewritten for the four-card DOM.

### Step 6: Land PR-3a

After Task 12 passes:

```bash
mise exec -- bundle exec rspec  # full suite must be green
mise exec -- bin/rails db:rollback STEP=1 && mise exec -- bin/rails db:migrate  # round-trip check
# Mixed v1/v2 fixture check (panel finding — added to PR-3a merge gate):
# Seed a few legacy rows manually in console, rollback, re-migrate, verify reshape is idempotent.
git checkout feat/preferences-redesign
git merge wip/preferences-redesign-handoff  # or rebase, depending on house style
git push -u origin feat/preferences-redesign
gh pr create  # title: feat(preferences): JSONB reshape + IA + quiet hours + view (PR-3a)
```

This handoff document ends here. PR-3b (Tasks 13–17) is a clean new session — no handoff context needed because PR-3a will have shipped a stable foundation.

## Notable production-state observations

- **Migration `20260510212832` is already applied locally** (dev + test DBs both at this version). On a fresh clone, the resume runbook handles this via `bin/rails db:migrate`.
- **Column default updated**: new `user_preferences` rows now get the new-shape JSONB out of the box. This means factories no longer need to inject the new shape; the schema default handles it.
- **The value object's `do_not_disturb?` is now an alias** for `quiet_hours_active?`. Callers (notably the bell button tooltip) continue working without changes.
- **`NotificationPreferences#allow?` returns `:digest` sentinel** when email channel is enabled with non-instant frequency. Boolean-style callers need to treat `:digest` as "yes but not now" — currently most callers truthy-check, which means `:digest` is treated as truthy (correct for "should we attempt delivery"). The `if:` proc in `ApplicationNotifier` (Task 10) needs to distinguish `true` (deliver now) from `:digest` (queue).

## Memory entries created or relevant

- [project_panel_review_findings.md](/Users/dschmura/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_panel_review_findings.md) — concurrency blockers were addressed pre-PR-3.
- [project_flaky_tests_followup.md](/Users/dschmura/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_flaky_tests_followup.md) — workspace-branded surface drift; may surface in Task 15's mobile spec.

## TL;DR for resumption

```text
git checkout wip/preferences-redesign-handoff
# Read this HANDOFF.md
# Fix ~30 spec failures per-file (NO sed) using Pattern A/B/C examples above
# Commit Task 9 atomically
# Continue Task 10 (note the :digest sentinel contract — plan §Task 10 has the guard)
# Tasks 11–12 finish PR-3a
# Open PR-3a; do NOT continue into Tasks 13–17 in the same PR
```

The hard part (data migration, value object, schema default) is done and tested. What remains in PR-3a is:

1. **~30 spec assertions** to translate per-file using the concrete before/after patterns in Step 2 above (Patterns A / B / C). Estimate: 2–3 hours focused work.
2. **Task 10** — notifier + digest job rewiring. Estimate: 0.5–1 day. The `:digest` sentinel contract is now called out at the top of plan §Task 10.
3. **Task 11** — controller `apply_changes!` rewrite. Estimate: 0.5 day.
4. **Task 12** — four-card view rewrite + Pattern C pending-assertions rewritten. Estimate: 1 day.

**Estimated PR-3a remaining effort: 3–5 days** (revised from the plan's original 3-day estimate for all 10 tasks — see the panel finding in the Split decision section).

PR-3b (Tasks 13–17) is a separate session, separate branch, separate PR, and is not blocking. Estimated effort there: 1–2 days.
