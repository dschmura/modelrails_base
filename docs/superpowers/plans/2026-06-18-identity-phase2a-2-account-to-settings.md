# Identity Phase 2a-2 — `/account → /settings` namespace rename (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Rename the identity-settings surface from `account` → `settings` everywhere: routes (`/account/* → /settings/*`), the `Account::` controller + policy modules, the view directory, the `en.account.*` i18n keys, the four mailer URL helpers, and all path-helper references across app + specs. **Pure mechanical rename — zero behavior change.** Spec: `docs/superpowers/specs/2026-06-18-identity-phase2a-me-home-and-settings-design.md`. Execute **after** 2a-1 (the `/me` home).

**Architecture:** A single coordinated rename. Because renaming the route namespace makes every `*_account_*` path helper undefined at once, **the suite is red until the whole sweep is complete** — there is no incrementally-green path. The safety net is a *bulletproof verification gate* (grep-for-zero-stragglers in every category + the full suite + i18n). `PersonalWorkspaceContext` and `layout "settings"` are unchanged (the research confirmed the concern is `:none`-safe and workspace-agnostic). No `/account/*` redirects (clean move — pre-launch; a production fork adds temporary cutover redirects per the spec).

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (`mise exec --`), Zeitwerk (file path must match the constant — move files *and* rename the module together), RSpec, i18n (test env raises on missing translations → the suite catches i18n misses). TDD-style isn't applicable to a rename; commit but **DO NOT push**; never bypass Lefthook.

---

## ⚠️ The sweep trap (read first)

The namespace token `account` collides with the `connected_accounts` resource and with model/variable names (`connected_account_id`). **Never** blanket-replace `account_ → settings_`. Rename only the **explicit helper names** listed in Step 6, and verify with a grep-for-zero of the OLD names. Apply replacements file-scoped to `.rb`/`.erb`, and **diff-verify, never trust a match count** ([[bulk-replace-verify]]).

## File moves (use `git mv` to preserve history)

| From | To |
|---|---|
| `app/controllers/account/` (9 files, incl. `preferences/timezones_controller.rb`) | `app/controllers/settings/` |
| `app/policies/account/` (5 files) | `app/policies/settings/` |
| `app/views/account/` (18 files, preserve subdirs) | `app/views/settings/` |
| `spec/requests/account/` (9 files) | `spec/requests/settings/` |
| `spec/system/account/` (5 files) | `spec/system/settings/` |
| `spec/policies/account/` (4 files) | `spec/policies/settings/` |

---

## Task 1 — the coordinated rename

- [ ] **Step 1: Routes.** `config/routes.rb:21` — `namespace :account do` → `namespace :settings do`. (The inner block — `profile`, `password`, `avatar`+`hub`, `theme_preference`, `notification_preferences`+`dismiss_banner`, `preferences/timezone`, `connected_accounts`+`verify`, `email_confirmation`, `notifications` — is unchanged.)

- [ ] **Step 2: Controllers — move + rename module.** `git mv app/controllers/account app/controllers/settings`. In each of the 9 files, `module Account` → `module Settings`. Update the `authorize @user, policy_class: Account::*Policy` calls → `Settings::*Policy` (every controller references its policy this way). Keep `include PersonalWorkspaceContext` and `layout "settings"` unchanged. (Nested: `settings/preferences/timezones_controller.rb` → `module Settings; module Preferences`.)

- [ ] **Step 3: Policies — move + rename class.** `git mv app/policies/account app/policies/settings`. In each of the 5 files, `class Account::XPolicy` → `class Settings::XPolicy` (`AvatarPolicy`, `NotificationPreferencesPolicy`, `ProfilePolicy`, `ThemePreferencesPolicy`, `TimezonePolicy`).

- [ ] **Step 4: Views — move.** `git mv app/views/account app/views/settings` (preserve the subdir tree). Update any `render "account/..."` / `render partial: "account/..."` references found by `grep -rn '"account/' app/views`.

- [ ] **Step 5: i18n keys.** In `config/locales/en/account.en.yml`, change the top-level `account:` key → `settings:` (Rails deep-merges with the existing `settings:` in `settings.en.yml` — the research confirmed **no collisions**). Leave the file's other top-level keys (`identity_picker:`, `email_verification_resends:`) untouched. Then sweep the absolute lookups: in `app/views/settings/**` and the controllers, `t("account.` → `t("settings.` and `t('account.` → `t('settings.` (the research listed `connected_accounts/index.html.erb` with ~14, `profiles/edit.html.erb`, and `avatars_controller.rb:13`). **Relative `t(".…")` lookups need no change** (they resolve by controller path, which moved).

- [ ] **Step 6: Path-helper sweep (explicit names only).** Replace these exact helper stems across `app/`, `config/`, `lib/`, `spec/` (each `_path` and `_url` variant), `.rb` + `.erb`. **Diff-verify each:**

  | Old | New |
  |---|---|
  | `edit_account_profile` | `edit_settings_profile` |
  | `new_account_password` | `new_settings_password` |
  | `account_avatar` / `hub_account_avatar` | `settings_avatar` / `hub_settings_avatar` |
  | `edit_account_theme_preference` | `edit_settings_theme_preference` |
  | `edit_account_notification_preferences` | `edit_settings_notification_preferences` |
  | `dismiss_banner_account_notification_preferences` | `dismiss_banner_settings_notification_preferences` |
  | `account_preferences_timezone` | `settings_preferences_timezone` |
  | `account_connected_account` (singular member) | `settings_connected_account` |
  | `account_connected_accounts` (plural) | `settings_connected_accounts` |
  | `verify_account_connected_accounts` | `verify_settings_connected_accounts` |
  | `resend_verification_account_connected_account` | `resend_verification_settings_connected_account` |
  | `account_email_confirmation` | `settings_email_confirmation` |
  | `account_notifications` (index/collection) | `settings_notifications` |
  | `account_notification` (member) | `settings_notification` |
  | `mark_all_read_account_notifications` | `mark_all_read_settings_notifications` |
  | `destroy_all_read_account_notifications` | `destroy_all_read_settings_notifications` |

  (Order the longer stems before their prefixes when scripting, so `account_connected_accounts` isn't half-rewritten by `account_connected_account`.)

- [ ] **Step 7: Mailers.** Update the 4 URL helpers: `app/mailers/authentication_mailer.rb:25` (`account_email_confirmation_url`), `:46` (`verify_account_connected_accounts_url`), `:67` (`account_connected_accounts_url`), `app/mailers/notification_mailer.rb:124` (`edit_account_notification_preferences_url`) — covered by Step 6 if the sweep includes `app/mailers/`. Confirm the email templates (`app/views/authentication_mailer/link_verification_email.*`) reference `@verify_url` (no hard-coded path).

- [ ] **Step 8: Move the spec directories.** `git mv spec/requests/account spec/requests/settings`; `git mv spec/system/account spec/system/settings`; `git mv spec/policies/account spec/policies/settings`. Update any `describe "Account ..."` / class references (`Account::ProfilePolicy` → `Settings::ProfilePolicy`) inside them, and the `type:`/path helpers (Step 6 already swept the helpers).

---

## Task 2 — the verification gate (the safety net) + commit

- [ ] **Step 1: Zero stragglers — old path helpers.**

  ```bash
  grep -rnE "(edit_account_profile|new_account_password|account_avatar|hub_account_avatar|account_theme_preference|account_notification|account_connected_account|verify_account_connected|resend_verification_account|account_email_confirmation|account_preferences_timezone|dismiss_banner_account|mark_all_read_account|destroy_all_read_account)" app config lib spec
  ```
  Expected: **zero hits** (the `docs/` historical plans are out of scope).

- [ ] **Step 2: Zero stragglers — module + i18n + namespace.**

  ```bash
  grep -rn "Account::" app spec                          # expect 0 (modules renamed)
  grep -rnE 't\("account\.|'"'"'account\.' app           # expect 0 (i18n lookups swept)
  grep -rn "namespace :account" config/routes.rb         # expect 0
  grep -rn '"account/' app/views                          # expect 0 (render partial paths)
  ```

- [ ] **Step 3: Boot + routes sanity.** `mise exec -- bin/rails runner 'Rails.application.reload_routes!; puts settings_profile_path rescue (puts "MISSING")'` — confirm the new helpers resolve and the app boots (Zeitwerk maps `Settings::ProfilesController` to the moved file).

- [ ] **Step 4: Full suite.** `mise exec -- bundle exec rspec` → **green**. (Test env raises on missing translations, so an unswept `account.*` key fails here; a missed path helper raises `NoMethodError`. This is the real gate.)

- [ ] **Step 5: Markdown + commit.**

  ```bash
  mise exec -- bundle exec rake markdown:check
  git add -A
  git commit -m "rename: /account -> /settings identity-settings namespace (Account:: -> Settings::, i18n, mailers, specs)"
  ```
  (`git add -A` captures the `git mv` moves + edits; verify `git status` shows only intended renames/edits.)

---

## Cross-repo + follow-ups

- **Email deep-links:** sent `/account/connected_accounts/verify/:token` emails 404 after this (no template redirects — pre-launch). A *production* fork adds temporary `/account/* → /settings/*` redirects at cutover.
- **Fork (hallwaytrack):** inherits the rename on its next template sync; any fork-owned references to `*_account_*` settings helpers update then.
- **Not in this plan:** dropping `PersonalWorkspaceContext` from the settings controllers (it sets `Current.workspace = personal_workspace` — the polymorphic-Profile machinery being superseded). That's a *behavioral* slice for when the settings sidebar restructures, not this pure rename.

## Self-review

- **Atomic rename** — suite red mid-sweep; the Task 2 gate (grep-for-zero ×5 + full suite + boot) is the safety net, not per-step green.
- **Sweep trap encoded** — explicit helper names only; `connected_accounts` resource + `connected_account_id` model refs are NOT touched; diff-verify mandated.
- **No behavior change** — `PersonalWorkspaceContext`, `layout "settings"`, policies' logic all identical; only names/paths move.
- **Zeitwerk** — file moves (`git mv`) paired with module renames so constants resolve.

## Execution handoff

1. **Subagent-Driven (recommended)** — one implementer does the coordinated rename, then the verification gate; a code-quality reviewer confirms no stray `account` references and no behavior change.
2. **Inline** — `superpowers:executing-plans`.
