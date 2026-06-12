# Fork seams + forking workflow documentation — design

**Date:** 2026-06-12
**Status:** Approved design, pending implementation plan
**Context:** First downstream fork (sonicpics) is imminent. The fork-readiness audit
(docs/reviews/2026-06-11-fork-readiness-panel-review.md) closed all 6 blockers
(PRs #291–#293, #307, #309). What remains: disentanglement seams so downstream
edits don't conflict with upstream merges, and the JumpstartPro-style workflow
documentation.

## Goal

Downstream apps clone modelrails_base with full git history, rename their identity,
build their product in **fork-owned files**, and periodically run
`git merge upstream/main` with minimal conflicts. Upstream improvements flow down;
fork customization never collides with them — by construction, not discipline.

## Decisions made

| Decision | Choice |
| --- | --- |
| Doc location | In-app docs page `app/docs/forking.md` (forks inherit it; update instructions travel with each downstream) |
| Rename method | Documented manual checklist now; `bin/rename-app` script deferred (trigger: second fork) |
| Update flow | `git merge upstream/main` on a sync branch (JumpstartPro-style); no tagged releases for now |
| Scope | Two PRs — seams first, then docs; creating sonicpics is the follow-up task that validates the docs |
| Seam scope | All four seams (brand locale, routes draw, fork-owned contract, docs-categories overlay) |

The unifying pattern: **convert shared-file edits into fork-created files** using
Rails' native overlay points (i18n file merging, `draw(:name)` route files, optional
local config files) plus git's per-path merge drivers.

## PR A — fork seams (`feat/fork-seams`)

### Seam 1: Brand locale file

`config/locales/en/brand.en.yml` becomes the single home for identity strings.

- **Move** the `application.name` definition out of `application.en.yml` into
  `brand.en.yml` (Rails merges locale files — zero call-site churn for existing
  `t("application.name")` references).
- **Add** keys for the other scattered identity strings and convert their call
  sites to `t()`: support email (pages/contact), copyright owner (footer), and the
  layout's hardcoded `<meta name="description">` line
  (`app/views/layouts/application.html.erb:4`).
- Exact key inventory happens at planning time via `grep -ri modelrails app/ config/locales/`.
  Marketing *copy* in `pages.en.yml` stays put — those pages are fork-owned wholesale
  (Seam 3); only cross-app identity strings move.
- Invariant: add a `template_invariants_spec` example asserting `brand.en.yml`
  exists (forks customize it; upstream never edits it after this PR).

### Seam 2: Routes seam

- Add `draw(:app)` to `config/routes.rb` (native Rails ≥6.1 feature, loads
  `config/routes/app.rb`).
- Move the product routes there: `root "pages#home"`, about, privacy, contact —
  with a header comment declaring the file fork-owned.
- This is deliberately the minimal subset of the panel's deferred "split routes.rb
  into per-area draw files" (trigger for the full split remains: first real routes
  conflict / second fork).

### Seam 3: Fork-owned file contract

A declared list of files upstream **freezes** after this PR and forks rewrite freely:

- `app/views/pages/**` and `app/controllers/pages_controller.rb`
- `config/locales/en/pages.en.yml` (the marketing copy for those pages — house rules
  keep all UI text in locales, so rewriting the pages means rewriting this file)
- `README.md`
- `config/locales/en/brand.en.yml`
- `config/routes/app.rb`
- `config/markdowndocs_categories.local.yml` (Seam 4; absent upstream)
- `db/seeds.rb` below the preset section (already structured for extension)

Mechanism:

- `.gitattributes` entries marking these paths `merge=ours`. The driver is inert
  until a clone runs `git config merge.ours.driver true` (one-time, documented in
  forking.md) — then upstream syncs auto-resolve these paths in the fork's favor.
- The canonical list lives in `app/docs/forking.md` (PR B); `.gitattributes` is the
  enforcement.

Known accepted risk: the panel's pending button-sweep (should-fix item 7) touches
`app/views/pages/home.html.erb`. Freezing now means that sweep either lands first
upstream or forks absorb one conflict (or miss the restyle — acceptable, the page
is theirs). We are NOT folding the sweep into this PR (scope discipline); the risk
is recorded here.

### Seam 4: Docs-categories overlay

`config/initializers/markdowndocs.rb` hardcodes the category map and
`spec/docs/index_coverage_spec.rb` enforces every `app/docs/*.md` file appears in
exactly one category — so a fork adding any docs page must edit two template-owned
files today.

- Initializer merges an **optional** `config/markdowndocs_categories.local.yml`
  (guarded by `File.exist?`, not `rescue`). Absent upstream; a fork creates it to
  register its own docs pages/categories.
- `index_coverage_spec` updated to include local categories in its coverage union,
  so fork-added docs files satisfy the spec via the local file alone.
- Template categories stay in the initializer (they're template-owned and that's
  fine); only the *extension point* is externalized.

### Testing (PR A)

TDD per house rules — failing spec first for each seam:

1. Brand: spec asserting `t("application.name")` still resolves + brand file exists.
2. Routes: existing routing/system specs must stay green after the move (the move
   itself is behavior-neutral; the spec is the existing suite).
3. Contract: `.gitattributes` content asserted in `template_invariants_spec`.
4. Overlay: spec exercising the merge with a fixture local file (and absence = today's behavior).

Full suite + Lefthook pre-push before commit, as always.

## PR B — forking documentation (`docs/forking-guide`)

### `app/docs/forking.md` (rendered at `/docs/forking`)

Sections:

1. **The model** — upstream template, downstream clones with shared git history,
   updates by merge. Warning: GitHub's "Use this template" squashes history and
   breaks merging; also you cannot fork your own repo into the same account. The
   mechanism is clone + re-point remotes.
2. **Starting a new app** (sonicpics as the worked example):

   ```bash
   git clone git@github.com:dschmura/modelrails_base.git sonicpics
   cd sonicpics
   git remote rename origin upstream
   git remote set-url --push upstream DISABLED   # can't accidentally push to the template
   git remote add origin git@github.com:dschmura/sonicpics.git  # empty repo, no README/license
   git push -u origin main
   git config merge.ours.driver true             # activates the fork-owned merge driver
   ```

3. **Renaming the identity** — the must-change checklist (moved from README; single
   source of truth), gaining one new row: devcontainer bundle-cache volume name
   (`modelrails-bundle-cache`, asserted by `template_invariants_spec.rb:228`).
   Verification step: `grep -ri modelrails . --exclude-dir={.git,node_modules,...}`,
   full suite, CI's production-image build as backstop.
4. **Bootstrapping secrets & config** — per-env credentials, `RAILS_HOST`, tenancy
   preset, signup mode (consolidating README + `.env.example` guidance).
5. **Fork-owned files** — the Seam 3 list; what "fork-owned" means (upstream frozen,
   merge=ours, rewrite freely); how each seam works (brand locale, routes/app.rb,
   docs categories local file).
6. **Pulling upstream updates**:

   ```bash
   git fetch upstream
   git log --oneline main..upstream/main   # review what's coming
   git checkout -b chore/upstream-sync-$(date +%F)
   git merge upstream/main
   ```

   Conflict doctrine: identity/fork-owned files → keep yours (auto via merge driver);
   behavior → take theirs; `Gemfile.lock`/`package-lock.json` → regenerate
   (`bundle install` / `npm install`), never hand-merge. Then `bin/rails db:migrate`,
   full suite, PR into the downstream's main.
   Cadence: after each meaningful upstream release, or monthly.
7. **Contributing back** — template-worthy fixes get cherry-picked onto a branch off
   `upstream/main` and PR'd to modelrails_base.
8. **Staying mergeable** — additive over edits; new files over modified template
   files; brand strings only in `brand.en.yml`; product routes only in `routes/app.rb`;
   product docs registered via the local categories file.

Registered under "Guides" in the markdowndocs initializer (template-owned edit, fine).

### README slimming

"Forking this template" section keeps the clone commands (GitHub-browsing visibility)
and points to `app/docs/forking.md` / `/docs/forking` for everything else. The
checklist table moves out (single source of truth in the doc).

### Backlog issues (check open+closed for duplicates first)

| Issue | Trigger |
| --- | --- |
| `bin/rename-app` script | Second fork created |
| CSP OAuth-host extraction to config | First fork swapping OAuth providers |
| Theme/brand-color seam verification (OKLCH theming is partly runtime/DB-driven; survey agent's compile-time claim unverified) | sonicpics branding pass |

## Out of scope

- The rename script, tagged releases, CSP/theme seams (backlog with triggers above).
- The `Marketing::` namespace restructure proposed by the survey (rejected: churn
  without benefit over the freeze contract).
- Creating sonicpics — immediate follow-up task, which doubles as validation of the docs.

## Follow-up

After both PRs merge: walk through `app/docs/forking.md` literally to create
sonicpics; any friction found is a docs bug to fix upstream before fork #2.
