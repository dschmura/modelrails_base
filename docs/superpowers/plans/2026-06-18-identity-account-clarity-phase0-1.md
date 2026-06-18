# Identity & Account Clarity — Phase 0 + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the cheapest, well-defined slices of the identity/account-clarity spec (`docs/superpowers/specs/2026-06-18-identity-account-model-clarity-design.md`): **Phase 0** — document the already-built three-tier model; **Phase 1** — the honest-naming wins: rename the misleading `TENANCY_ONBOARDING` env var to `WORKSPACE_ON_SIGNUP`, and retire "personal workspace" copy for "your workspace". No data-model changes, no route moves, no UI builds.

**Architecture:** Three surgical slices plus one new doc. The data model is unchanged (verified sound by the review panel). The env rename touches exactly **one code read** (`config/application.rb`), the boot validator's error strings, and one spec assertion — the internal symbol value (`:personal`/`:shared`/`:none`) and accessor (`TenancyConfig.onboarding`, which reads `Rails.configuration.x.tenancy.onboarding`, **not** the ENV name) are untouched. The new doc is registered in the markdowndocs index (the `index_coverage_spec` gate that bit PR #347). Copy changes are limited to two durable user-facing strings.

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (run everything via `mise exec --`), RSpec, FactoryBot, SQLite, markdowndocs (the in-app `/docs` index). TDD; full suite green before every commit; commit but **DO NOT push**; never bypass Lefthook.

---

## Scope notes — deviations from the spec's "Phase 1" (surfaced at planning)

- **`/me` identity home is NOT in this plan.** Research confirms the template has **no `/me`** today (no `MeController`, route, or views — the fork owns it). Building it is a from-scratch UI that interlocks with the Phase 2 switcher; re-sequenced to Phase 2.
- **"Never 'account' for a tenant" is already satisfied.** The i18n cleanly separates `account.*` (identity) from `workspaces.*` (tenant). The only residue is "personal workspace" (5 strings); 3 live in the settings sidebar that Phase 2 restructures, so Phase 1 copy = the **2 durable strings**.
- **Only the misleading var renames.** `TENANCY_ONBOARDING → WORKSPACE_ON_SIGNUP`; the `TENANCY_WORKSPACE_CREATION` / `TENANCY_SHARED_WORKSPACE_*` family stays (those names aren't misleading). One var leaving the `TENANCY_` cluster is an accepted, deliberate wart.
- **Clean rename, no compatibility fallback** (per the `/account` decision): `config/application.rb` reads only the new name; the fork updates its `.env`/deploy as a coordinator follow-up (see "Cross-repo" below).

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `app/docs/accounts-and-identity.md` | **Create** | The three-tier model doc — Identity / your workspace / organization workspace; canonical vocabulary; identity-vs-tenant split. |
| `config/initializers/markdowndocs.rb` | Modify (the `"Features"` array) | Register `accounts-and-identity` so `index_coverage_spec` passes. |
| `config/application.rb` | Modify (L54) | `ENV.fetch("TENANCY_ONBOARDING", "personal")` → `ENV.fetch("WORKSPACE_ON_SIGNUP", "personal")`. |
| `config/initializers/tenancy.rb` | Modify (L7, L19) | Error-message strings cite the new var name. |
| `spec/initializers/tenancy_spec.rb` | Modify (L26) | Assertion expects the new error string. |
| `.env.example` | Modify (L70, L76, L80) | Document `WORKSPACE_ON_SIGNUP`; the shared-seed comments reference the new name. |
| `app/docs/presets.md`, `presets-single-tenant.md`, `presets-none.md`, `forking.md` | Modify | Replace `TENANCY_ONBOARDING` → `WORKSPACE_ON_SIGNUP` (6 references). |
| `CHANGELOG.md` | Modify | New `[Unreleased]` entry for the rename; fix the 2 existing entries that cite the old name (L34, L53). |
| `config/locales/en/pages.en.yml` | Modify (L18) | "Personal workspace on sign-up." → "Your workspace on sign-up." |
| `config/locales/en/workspaces.en.yml` | Modify (L124) | "…your personal workspace." → "…your workspace." |

---

## Task 1 — Phase 0: the `accounts-and-identity` doc + index registration

**Files:**
- Create: `app/docs/accounts-and-identity.md`
- Modify: `config/initializers/markdowndocs.rb` (the `"Features"` category array)
- Gate: `spec/docs/index_coverage_spec.rb` (existing — must stay green)

- [ ] **Step 1: Write the doc.** Create `app/docs/accounts-and-identity.md`. Match the frontmatter shape of a sibling (e.g. `app/docs/accounts.md` — `title` / `description` / `keywords` / `audience`). Required sections, drawn from the spec's canonical tables (do not invent new structure — lift the spec's three-tier table and vocabulary table):
  1. **The three tiers** — Identity (`User`), your workspace (auto-created, growable tenant), organization workspace (shared tenant). Reuse the spec's §2 table.
  2. **Identity vs. tenancy** — identity is account-independent (avatar, prefs, linked logins live on `User`, reachable from any context); tenant data is workspace-scoped via `Current.workspace` + `Tenanted`.
  3. **One `Workspace` entity, two flavors** — the `owner_created`/`personal` flag marks the auto-created one; both are the same model, differing only in membership count.
  4. **Canonical vocabulary** — reuse the spec's §4 table (workspace = tenant; settings/profile = identity; never "account" for a tenant).
  5. **For forks** — link to `forking.md` and the four presets; note `WORKSPACE_ON_SIGNUP` controls which workspace (if any) a new user lands in.
  State plainly that **this documents the model that already exists** (its correctness was previously invisible). Keep AAA-doc tone consistent with siblings.

- [ ] **Step 2: Run the coverage spec to verify it fails (orphan).**

  Run: `mise exec -- bundle exec rspec spec/docs/index_coverage_spec.rb`
  Expected: **FAIL** — `Uncategorized docs (add to config/initializers/markdowndocs.rb): accounts-and-identity`.

- [ ] **Step 3: Register the doc.** In `config/initializers/markdowndocs.rb`, add `accounts-and-identity` to the `"Features"` array (it sits alongside `accounts`):

  ```ruby
  "Features" => %w[accounts accounts-and-identity workspaces projects identity-system emails notifications notifications-technical],
  ```

- [ ] **Step 4: Run the coverage spec to verify it passes.**

  Run: `mise exec -- bundle exec rspec spec/docs/index_coverage_spec.rb`
  Expected: **PASS** (0 failures).

- [ ] **Step 5: Run the markdown linter.**

  Run: `mise exec -- bundle exec rake markdown:check`
  Expected: clean (no output). Fix any MD032/blank-line nits.

- [ ] **Step 6: Full suite, then commit.**

  ```bash
  mise exec -- bundle exec rspec
  git add app/docs/accounts-and-identity.md config/initializers/markdowndocs.rb
  git commit -m "docs: add accounts-and-identity (names the three-tier identity/account model)"
  ```
  Expected: suite green before commit.

---

## Task 2 — Phase 1a: rename `TENANCY_ONBOARDING` → `WORKSPACE_ON_SIGNUP`

**Files:**
- Modify: `config/application.rb` (L54), `config/initializers/tenancy.rb` (L7, L19), `.env.example` (L70/76/80)
- Modify (docs): `app/docs/presets.md`, `presets-single-tenant.md`, `presets-none.md`, `forking.md`, `CHANGELOG.md`
- Test: `spec/initializers/tenancy_spec.rb` (L26)

> The symbol values (`:personal`/`:shared`/`:none`) and `TenancyConfig` are unchanged — only the ENV var *name* moves.

- [ ] **Step 1: Update the spec to expect the new error string (RED first).** In `spec/initializers/tenancy_spec.rb` around L26, change the expected boot-error substring from `Invalid TENANCY_ONBOARDING` to `Invalid WORKSPACE_ON_SIGNUP`.

- [ ] **Step 2: Run it to verify it fails.**

  Run: `mise exec -- bundle exec rspec spec/initializers/tenancy_spec.rb`
  Expected: **FAIL** — the initializer still raises with the old `TENANCY_ONBOARDING` string.

- [ ] **Step 3: Rename the ENV read.** `config/application.rb:54`:

  ```ruby
  config.x.tenancy.onboarding = ENV.fetch("WORKSPACE_ON_SIGNUP", "personal").to_sym
  ```

- [ ] **Step 4: Update the boot-validator error strings.** `config/initializers/tenancy.rb`:
  - L7: `raise "Invalid WORKSPACE_ON_SIGNUP: #{Rails.configuration.x.tenancy.onboarding.inspect}. " \`
  - L19: `raise "TENANCY_SHARED_WORKSPACE_SLUG is required when WORKSPACE_ON_SIGNUP=shared"`

- [ ] **Step 5: Run the initializer spec to verify it passes.**

  Run: `mise exec -- bundle exec rspec spec/initializers/tenancy_spec.rb`
  Expected: **PASS**.

- [ ] **Step 6: Update `.env.example`.** Replace the three references (L70/76/80) so the var reads `WORKSPACE_ON_SIGNUP` and the shared-seed comments say `WORKSPACE_ON_SIGNUP=shared`. Refresh the docstring so it reads honestly, e.g.:

  ```
  # Which workspace (if any) a new user lands in on signup.
  # Valid values: personal (auto-create their own), shared (join the one shared
  # workspace), none (no workspace — identity-only; see app/docs/presets-none.md).
  # WORKSPACE_ON_SIGNUP=personal
  ```

- [ ] **Step 7: Verify the env-documentation invariant.** The template invariant (added in #298) greps the code for `ENV.fetch`/`ENV[...]` and fails if a var is undocumented in `.env.example`.

  Run: `mise exec -- bundle exec rspec spec/code_smells/` (or the specific env-coverage spec)
  Expected: **PASS** — `WORKSPACE_ON_SIGNUP` is now documented; no orphaned `TENANCY_ONBOARDING` read remains.

- [ ] **Step 8: Sweep the docs.** Replace `TENANCY_ONBOARDING` → `WORKSPACE_ON_SIGNUP` in the 6 references: `app/docs/presets.md:38`, `presets-single-tenant.md:75`, `presets-none.md:71,80,146`, `forking.md:145`. **Verify with a diff, not a count** (per the bulk-replace lesson):

  Run: `git diff -- app/docs && grep -rn "TENANCY_ONBOARDING" app/docs` (expect: no remaining hits in `app/docs`).

- [ ] **Step 9: CHANGELOG.** Add an `[Unreleased]` entry — "Renamed `TENANCY_ONBOARDING` → `WORKSPACE_ON_SIGNUP` so the var names the question it answers (which workspace a new user lands in); `none` now reads honestly." Also fix the two existing entries that cite the old name (CHANGELOG L34, L53).

- [ ] **Step 10: Markdown lint + full suite, then commit.**

  ```bash
  mise exec -- bundle exec rake markdown:check
  mise exec -- bundle exec rspec
  git add config/application.rb config/initializers/tenancy.rb spec/initializers/tenancy_spec.rb .env.example app/docs CHANGELOG.md
  git commit -m "rename: TENANCY_ONBOARDING -> WORKSPACE_ON_SIGNUP (honest var name; none stops reading as 'no tenancy')"
  ```
  Expected: suite green before commit.

---

## Task 3 — Phase 1b: retire "personal workspace" in the durable copy

**Files:**
- Modify: `config/locales/en/pages.en.yml` (L18), `config/locales/en/workspaces.en.yml` (L124)

> Scope: only the **2 durable** strings. The 3 settings-sidebar strings (`settings.sidebar.*personal`) are **deferred to Phase 2** (the sidebar/polymorphic-Profile surface is restructured there — changing their copy now is wasted churn).

- [ ] **Step 1: Find any spec asserting the old copy (RED guard).**

  Run: `grep -rn "personal workspace" spec/ config/locales`
  If a request/system spec asserts the literal "personal workspace" for these two strings, update its expectation to "your workspace" first (so the change is test-driven). If none asserts them, note that and proceed — Step 4's suite run is the safety net.

- [ ] **Step 2: Update `pages.en.yml:18`.** `features.workspaces.description`: change the trailing sentence "Personal workspace on sign-up." → "Your workspace on sign-up."

- [ ] **Step 3: Update `workspaces.en.yml:124`.** `workspaces.index.cannot_leave_personal`: "You can't leave your personal workspace." → "You can't leave your workspace."

- [ ] **Step 4: Full suite, then commit.**

  ```bash
  mise exec -- bundle exec rspec
  git add config/locales/en/pages.en.yml config/locales/en/workspaces.en.yml
  git commit -m "copy: 'personal workspace' -> 'your workspace' in durable user-facing strings"
  ```
  Expected: suite green (any copy-asserting spec updated in Step 1).

---

## Cross-repo follow-up (coordinator step, NOT in this plan's commits)

After Task 2 merges to `modelrails_base` main, the fork (hallwaytrack) must, on its next template sync: set `WORKSPACE_ON_SIGNUP=none` in its `.env` / deploy config (it currently sets `TENANCY_ONBOARDING=none`), since the inherited `config/application.rb` now reads the new name. No fork code change beyond config.

## Self-review (run before handoff)

- **Spec coverage:** Phase 0 (doc) = Task 1; Phase 1a (env rename) = Task 2; Phase 1b (copy) = Task 3. The spec's Phase-1 `/me` item is deliberately deferred (see Scope notes) — flagged, not dropped.
- **No placeholders:** every step names exact files/lines/commands.
- **Naming consistency:** `WORKSPACE_ON_SIGNUP` used everywhere; symbol values (`:personal`/`:shared`/`:none`) untouched; `TenancyConfig.onboarding` untouched.
- **Gotchas encoded:** the `index_coverage_spec` gate (Task 1), the `.env.example` env-doc invariant (Task 2 Step 7), diff-not-count verification (Task 2 Step 8).

## Execution handoff

Two execution options:
1. **Subagent-Driven (recommended)** — fresh subagent per task, spec + code-quality review between tasks.
2. **Inline Execution** — batch with checkpoints (`superpowers:executing-plans`).
