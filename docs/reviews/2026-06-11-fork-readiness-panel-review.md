# Review Panel Results — Fork-Readiness Audit

**Scope:** Full-repo audit of `modelrails_base` (main @ `1681118`, 2026-06-11) as an upstream template for downstream forks.
**Panel:** All 10 reviewers + an 11th seat for upstream-template maintainability, synthesized through the Sandi Metz (cost of change) and Jim Weirich (clarity/joy) lenses.
**Special focus:** merge hazards for downstream forks, kruft/legacy, modelrails_ui adoption gaps.

## Verification evidence (we ran the actual code)

| Check | Result |
|---|---|
| Full RSpec suite | **3,044 examples, 0 failures** (3m 35s) |
| Coverage | 94.77% line / 76.2% branch |
| Production Docker build | **Success** (image `4283a95a4ec4`) |
| Dev server smoke | `/up`, `/`, `/session/new`, `/docs` → 200; `/lookbook` → 302 to landing (by design); no errors in dev log |
| Git hygiene probes | Credentials never committed; one **empty** `db/development.sqlite3` blob committed in history (`5d311ef`, removed in `3843700`) |

Four reviewer claims were **refuted by evidence** before making this report (see final section) — the remaining items below were all verified against the actual code.

## Consensus: NOT YET — 6 blockers before declaring the template fork-ready

---

## Blockers (must fix before first fork)

1. **modelrails_ui pinned to a moving git branch** — `Gemfile:140` pins `branch: "modelrails/harden"`. Every fork inherits a pin that breaks the moment the branch is deleted or force-pushed. The Gemfile's own comment says "Re-pin to a stable tag after the next gem release." Do that release and pin to a version/tag. *(DHH; confirmed by reading Gemfile)*

2. **`.gitignore` gaps — secrets and databases unprotected.**
   - `config/credentials/development.key` and `production.key` exist on disk and are **not ignored** (only `/config/*.key` is covered, not `config/credentials/*.key`). One `git add .` away from pushing decryption keys.
   - No `*.sqlite3` rule anywhere. The orphan `db/development.sqlite3` (real DB lives at `storage/development.sqlite3` per `database.yml`) was already committed once in history — empty that time; a fork won't be so lucky.
   - Fix: add `/config/credentials/*.key` and `*.sqlite3` ignore rules; delete the orphan `db/development.sqlite3`. *(Main-loop finding, verified via git)*

3. **Fork-rename path is undocumented and identity is hardcoded in 5+ places.** `module ModelrailsBase` (`config/application.rb:20`), `service:`/`image:`/storage-volume names in `config/deploy.yml` (lines 2, 14, 62), `package.json`/`package-lock.json` name. Kamal collisions and module confusion await any fork that misses one. Fix: add a README "Forking this template" section with the complete must-change checklist (drafted in Appendix A); optionally extract a `config/app_identity.rb` single source of truth. *(Chris Oliver + 11th seat)*

4. **Migration `20260325135142` is a known-broken landmine forks inherit.** The SQLite `remove_column` silently fails under `db:migrate` (documented project bug; workaround is `db:schema:load`). Fresh forks are safe because `bin/setup` uses `db:prepare`, but any fork that runs the migration path hits it. Repair the migration or add a loud comment + docs note before forks exist — fixing it after divergence means N forks patch it independently. *(11th seat)*

5. **108 `focus:ring-*` instances across 54 view files violate the design system's own focus rule.** `.modelrails_ui/agent-rules.md` mandates the offset-outline `focus-ring` utility; box-shadow rings clip under `overflow:hidden` and vanish in forced-colors mode (WCAG 2.4.7 failure that axe cannot detect — which is why CI is green anyway). Mechanical sweep (`focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-…` → `focus-ring`), then verify per the bulk-replace-needs-diff-verification rule, both themes. *(Adam Wathan; count re-verified: 108/54)*

6. **Sortable table headers don't announce sortability or unsorted state** — `app/views/shared/_sortable_header.html.erb:13-17` only adds sr-only state text on the *active* column; inactive columns give a screen-reader user no clue they sort. Fix with `aria-sort="none|ascending|descending"` on the `<th>` (replaces the sr-only approach wholesale). *(Léonie Watson)*

---

## Should fix

### Design-system adoption (the "UI not using modelrails_ui" inventory)

7. **~38 hand-rolled button utility stacks → `ui :button` / `.btn-*`.** Worst offenders (full sweep recommended):
   - `account/notifications/_item.html.erb:30,37,44` (mark read/unread/delete)
   - `account/notifications/_bulk_actions.html.erb:5,21` (modal triggers)
   - `pages/home.html.erb:35-37` (hero CTA)
   - `workspaces/members/index.html.erb:8-12` ("Invite member" — line 150 of the *same file* correctly uses `.btn-primary`)
   - `workspaces/projects/index.html.erb:7-10` and `projects/memberships/index.html.erb:8-12` ("New X" buttons)
   - `sessions/new.html.erb`, `registrations/new.html.erb`, `passwords/new.html.erb` submit buttons
8. **Filter chips are a hand-rolled badge** — `account/notifications/_filter_chips.html.erb:12` builds its own pill classes; use the badge primitive (`variant: :soft/:outline` + href) or codify the active=solid/inactive=outline two-state as a documented pattern.
9. **Notifications index deviates from the list-page pattern on five axes** — plain-text empty state instead of `shared/_empty_state`, `text-2xl font-semibold` h1 vs `text-3xl font-bold`, `py-8` vs `py-16`, `max-w-3xl` vs `max-w-4xl`, responsive `sm:px-6 lg:px-8` padding nowhere else used. One page, one consolidated fix. *(Steve Schoger)*
10. **Project memberships table is a naked `<table>`** — `workspaces/projects/memberships/index.html.erb:16` lacks the `bg-surface-raised rounded-lg border shadow-sm overflow-hidden` card wrapper its sibling members table has.
11. **Members page header hand-builds what `shared/_settings_page_header` provides** — `workspaces/members/index.html.erb:3-6`.
12. **Mailer templates hardcode 16 hex colors** (`authentication_mailer/*`, `notification_mailer/digest`) — inline styles are necessary for email, but extract to a `<style>` block with token-derived values and a `prefers-color-scheme: dark` variant.
13. **Member-row action buttons lack `min-h-[44px]` touch targets** — `workspaces/members/_member_row.html.erb:21-54` (the notifications equivalents have them).

### Template/fork ergonomics

14. **`.env.example` documents 2 of ~17 ENV vars the code reads** — missing `TENANCY_*` (5 vars), `APP_HOST`, `RAILS_HOST`, `TENANCY_ONBOARDING`, `SIGNUP_PERMITTED_JOIN_STRATEGIES`. A fork dev rediscovers these by reading source.
15. **Credentials bootstrap for forks is undocumented** — nothing under `config/credentials/` is committed (correct call for a public template), but a fork's day-one experience is "mailer/OAuth silently unconfigured." Document `bin/rails credentials:edit --environment …` setup in the README forking section; decide whether to commit the `.yml.enc` files (keys stay out either way once Blocker 2 lands).
16. **CI installs unpinned npm globals** — `lint_docs` job does `npm install -g @herb-tools/linter` / `markdownlint-cli` with no version pins; forks inherit drift-by-default (this bit the repo before — bundler-audit CI/Lefthook drift). Pin versions.
17. **Stimulus controller ownership is undocumented** — 48 controllers mix gem-vendored copies and app-owned code with no marker saying which the planned SP4 update-engine will regenerate. Forks will edit a vendored copy and collide on refresh. Add an ownership note (README or `controllers/index.js` comment) now; SP4 formalizes it.
18. **`docs/component-standards/` is uncommitted work product** sitting untracked in the working tree (protocol, checklists, ADRs, component inventory). Decide: commit it (it documents the hardening groove forks benefit from) or move it out of the repo. Untracked-forever is the one wrong answer.
19. **Dead commented PWA routes** — `config/routes.rb` ~149-151. Delete (or implement); commented code conflicts like real code.

### Code quality

20. **`allow_any_instance_of` in 7 spec files** (mostly Pundit policy stubs; full list in panel detail) — replace with `instance_double` + constructor stubbing; fork-hostile when policy names change. *(Joël)*
21. **`is_a?` type dispatch in two policies** — `project_membership_policy.rb:25`, `resource_policy.rb:29`; replace with `record.respond_to?(:project) ? record.project : Current.project`. *(Dave Thomas)*
22. **Bare `rescue => e` in `Authenticatable#detect_and_record_new_device`** (`app/controllers/concerns/authenticatable.rb:80`) — intent ("must never break sign-in") is right; narrow to the expected error classes so real bugs surface.
23. **`Trackable#create_activity` failure log lacks context** (`trackable.rb:36`) — include model class/id so a fork debugging silent activity loss has a thread to pull.
24. **Quiet-hours zero-days warning isn't announced** — `account/notification_preferences/edit.html.erb:141-154`: initially-hidden `aria-describedby` target revealed by Stimulus is never announced; wrap in `role="status" aria-live="polite"`. *(Léonie)*
25. **Invitation rows lack "pending invitation" SR context** — `workspaces/members/_invitation_row.html.erb:7-11`; cheapest fix is sr-only prefix text on the first cell.
26. **Verify WAL + busy_timeout pragmas in production** — `database.yml` sets `timeout: 5000` but no explicit `journal_mode: WAL`. Rails 8.1's sqlite3 adapter defaults to WAL, but verify on the deployed box (`PRAGMA journal_mode;`) and make it explicit so forks can't regress it. *(Nate)*

---

## Deferred (with documented triggers)

| Item | Source | Trigger to act |
|---|---|---|
| Split `config/routes.rb` into per-area draw files | 11th seat | First real routes merge conflict, or before the **second** fork |
| ERB-ify `config/deploy.yml` identity values | 11th seat | More than one fork actively deploying |
| Inline `CropCoordinatable` (2 controllers) | DHH | Next change to either controller |
| Move `Toastable` out of ApplicationController | DHH | An API-only fork appears |
| Fragment caching on activity feed / member rows | Nate | Measured slow render, not before |
| Per-row Pundit policy cost | Nate | Lists exceed ~100 rows per page |
| `rating`/`timezone_beacon` fetch → Turbo-stream-capable pattern | Jorge | Those endpoints ever need stream responses |
| Idempotency key on DigestMailerJob | Aaron | First observed duplicate digest |
| EmailRecipientThrottle fail-open warning metric | Aaron | First cache-backend outage |
| Email dark-mode support | Adam | First user report |
| `TODO(PR-3)` security-hub pointer in password_changed_notifier | Chris | PR-3 ships |
| Document model-architecture / which concerns are framework-mandatory | Dave T. | First fork onboarding feedback |
| Tenanted/Sluggable adoption documentation | Dave T. | Next model added to either pattern |

## Refuted by evidence (kept for the record)

| Claim | Reviewer | Why it's wrong |
|---|---|---|
| "modal_closer races toast appends — toasts silently lost" (BLOCKER) | Jorge | Toasts append to the global `toast-pills` region, not `modal-body`; closing the dialog can't orphan them. Pattern is indirect but correct and system-spec-covered. |
| "`.page-container` is an undefined phantom class" (BLOCKER) | Schoger | Defined at `app/assets/tailwind/application.css:92`. |
| "Credentials `.key` files are committed to the repo" | Chris | `git ls-files config/credentials/` is empty; nothing was ever committed. The *real* issue is the missing ignore rule (Blocker 2) and missing bootstrap docs (item 15). |
| "`accept_project_invitation!` can exceed member capacity under concurrency" (BLOCKER) | Aaron | `Membership` declares `after_create :enforce_capacity_invariant` (membership.rb:20) — fires on every creation path including this one. Optional hardening: a spec proving the project-invitation path trips it. |

## What the panel admires

- **Concurrency posture built for SQLite reality**: atomic `UPDATE … WHERE consumed_at IS NULL` token consumption, partial unique indexes, post-write invariant re-checks inside transactions, honest comments about `lock!` being a per-connection no-op.
- **Test discipline**: 3,044/0, zero pending/skipped specs, no `sleep()`, CI-gated AAA, monkey-patching disabled, randomized order.
- **Broadcast architecture**: `broadcast_update_to` discipline with the frame-stripping rationale documented at the call site.
- **Docs architecture**: in-app `/docs` (markdowndocs) means every fork auto-inherits deployment/preset/troubleshooting guidance.
- **Complete index coverage** with composite indexes matching real query patterns, plus Bullet with a reasoned safelist.
- **The two-axis component API** (variant × tone with proven-cell guards that raise in dev) — the design system enforces itself.

## Facilitator synthesis

**Sandi Metz:** The blocker list is precisely the set whose cost multiplies at fork time — every one is cheap today and compounds per-fork later. The structural refactors (routes draw-files, deploy.yml templating) are the genuine judgment calls: their cost is real *now* and their benefit only materializes at fork ≥2, so the triggers in the deferred table are the honest answer. Don't fix them before the cost hits.

**Jim Weirich:** This codebase tells the truth — the SQLite lock comments, the "this rescue is the real backstop, not dead code" annotation, even the Gemfile comment that admits its own pin needs replacing. Item 1 is just the code asking you to listen to it. The hand-rolled buttons (item 7) are the one place the code stopped being honest: a design system this rigorous, bypassed 38 times in its own reference app, teaches every fork to bypass it too.

## Appendix A — Fork must-change checklist (draft for README)

| Item | File | Severity |
|---|---|---|
| Ruby module name | `config/application.rb:20` | Required |
| Kamal service name | `config/deploy.yml:2` | Required |
| Docker image name | `config/deploy.yml:14` | Required |
| Storage volume names | `config/deploy.yml:62-63` | Required |
| Credentials (mailer from, OAuth) | `bin/rails credentials:edit` per env | Required for prod |
| `RAILS_HOST` | env / `production.rb` | Required for prod |
| Tenancy preset (`TENANCY_ONBOARDING`) | env | Choose once |
| Signup mode / join strategies | env | Optional |
| npm package name | `package.json` | Cosmetic |
| Session cookie key | optional initializer | Only if sharing a domain |
