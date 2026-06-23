# Docs reorg (user/developer audiences) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the flat `app/docs/` (30 docs, 5 categories) to markdowndocs 0.7.0+ path-based audience routing — `app/docs/user/` + `app/docs/developer/` subdirectories plus shared root — with per-mode categories, retiring the deprecated `audience:` frontmatter and the `-technical` filename suffix, and carving two new `user/` docs.

**Architecture:** markdowndocs treats a first-level subdirectory matching a `config.modes` entry as an audience scope (files in `app/docs/developer/` show only in `developer` mode; root files are shared). `config.categories` slugs become path-prefixed (`developer/architecture`). The reorg is mostly `git mv` + a `config/initializers/markdowndocs.rb` rewrite + spec/cross-link updates; two `user/` docs (`authentication`, `invitations`) are carved from existing scattered content.

**Tech Stack:** Rails 8.1, markdowndocs `~> 0.9` (already pinned via Phase C), RSpec.

## Global Constraints

- **Prerequisite:** Phase C (#379) is merged; this branch is rebased onto post-#379 main BEFORE any file moves (carve `user/authentication` from the merged, corrected auth content). Run `git rebase origin/main` first.
- **Modes:** `config.modes = %w[user developer]`, `config.default_mode = "user"`.
- **Single-home:** each doc lives in exactly one of `user/`, `developer/`, or root. No doc duplicated across modes.
- **Audience mapping is the spec's Section 1** (verbatim): root = `getting-started`, `troubleshooting`; user (11); developer (19). See spec `docs/superpowers/specs/2026-06-23-docs-reorg-user-developer-design.md`.
- **`index_coverage_spec` must stay green after every task** — it is the canary that a moved doc kept its category home.
- **`working_files/` must be gitignored** — the reference copy never commits.
- All commands via `mise exec -- bundle exec …`. Markdown only; no I18n keys in docs.

---

### Task 1: Prep — reference copy + make the index spec subdirectory-aware

**Files:**
- Create: `working_files/docs-reference/` (untracked copy)
- Modify: `spec/docs/index_coverage_spec.rb`
- Modify: `spec/docs/application_flows_svg_spec.rb`

**Interfaces:**
- Produces: an `index_coverage_spec` whose `doc_slugs` are path-relative (`developer/architecture`, `user/accounts`, `getting-started`) so it matches path-prefixed `config.categories` slugs after moves.

- [ ] **Step 1: Confirm `working_files/` is gitignored**

Run: `git check-ignore working_files/x` — Expected: prints `working_files/x` (ignored). If not, add `/working_files/` to `.gitignore` and commit that line.

- [ ] **Step 2: Reference copy (untracked)**

```bash
mkdir -p working_files/docs-reference
cp -R app/docs/. working_files/docs-reference/
```

- [ ] **Step 3: Update `index_coverage_spec` to recursive, path-relative slugs**

Replace the `doc_slugs` let with:

```ruby
  let(:doc_slugs) do
    base = Rails.root.join("app/docs")
    Dir[base.join("**/*.md")].map { |f| Pathname(f).relative_path_from(base).to_s.delete_suffix(".md") }
  end
```

(The two `it` blocks are unchanged — they already diff `doc_slugs` against `Markdowndocs.configuration.categories.values.flatten`.)

- [ ] **Step 4: Make the flows svg spec recursive**

In `spec/docs/application_flows_svg_spec.rb`, change the glob:

```ruby
  pages = Dir[Rails.root.join("app/docs/**/application-flows*.md")].sort
```

- [ ] **Step 5: Verify green with the CURRENT flat layout** (relative path of a root file is just its basename, so nothing breaks yet)

Run: `mise exec -- bundle exec rspec spec/docs/`
Expected: all examples pass.

- [ ] **Step 6: Commit**

```bash
git add spec/docs/index_coverage_spec.rb spec/docs/application_flows_svg_spec.rb
git commit -m "test(docs): make index + flows specs subdirectory-aware (path-relative slugs)"
```

---

### Task 2: Move developer docs + set modes + rewrite config

**Files:**
- Move (git mv): the 19 developer docs → `app/docs/developer/`
- Modify: `config/initializers/markdowndocs.rb`
- Modify: `spec/docs/auth_docs_accuracy_spec.rb` (path for `security`, `qa-flows` if it reads them)

**Interfaces:**
- Consumes: the subdirectory-aware `index_coverage_spec` from Task 1.
- Produces: `config.modes = %w[user developer]`, `config.default_mode = "user"`; developer docs at `app/docs/developer/<slug>.md`; `config.categories` developer entries path-prefixed.

- [ ] **Step 1: `git mv` the developer docs**

```bash
cd app/docs && mkdir -p developer
for d in architecture extending forking components ui-patterns accessibility \
         background-jobs deployment security qa-flows identity-system accounts-and-identity \
         passkeys presets presets-solo presets-single-tenant presets-open-saas presets-none; do
  git mv "$d.md" "developer/$d.md"
done
git mv notifications-technical.md developer/notifications.md
cd -
```

- [ ] **Step 2: Drop deprecated `audience:` frontmatter from the moved developer docs**

For each `app/docs/developer/*.md`, remove any `audience:` line from the YAML front matter (the directory now scopes them). Verify none remain: `grep -rl "^audience:" app/docs/developer/` → expect no output.

- [ ] **Step 3: Set modes + rewrite `config.categories` (developer section path-prefixed)**

In `config/initializers/markdowndocs.rb`: uncomment/add `config.modes = %w[user developer]` and `config.default_mode = "user"`. Rewrite `template_categories` to the spec's Section 2 — at this task, developer slugs are path-prefixed (`developer/architecture`, …) and user slugs remain bare (still flat); root slugs bare. (Full final map is in Task 3 Step 3; here just the developer entries are prefixed.)

- [ ] **Step 4: Fix any spec that reads a moved developer doc by path**

In `spec/docs/auth_docs_accuracy_spec.rb`, update the path for `security` (now `app/docs/developer/security.md`) and any other moved doc it reads. (If it globs `app/docs/**/*.md`, no change needed — verify.)

- [ ] **Step 5: Verify green**

Run: `mise exec -- bundle exec rspec spec/docs/ && mise exec -- bundle exec rake markdown:check`
Expected: index_coverage green (developer slugs match `developer/<slug>` files), markdown clean.

- [ ] **Step 6: Commit**

```bash
git add -A app/docs config/initializers/markdowndocs.rb spec/docs
git commit -m "docs(reorg): move developer docs to app/docs/developer/; modes=user,developer"
```

---

### Task 3: Move user docs + notifications split + finalize config

**Files:**
- Move (git mv): the 9 existing user docs → `app/docs/user/`
- Modify: `config/initializers/markdowndocs.rb` (user section path-prefixed)
- Modify: `spec/docs/auth_docs_accuracy_spec.rb`, `spec/docs/application_flows_svg_spec.rb` (paths for `emails`, `accounts`, `application-flows`)

**Interfaces:**
- Consumes: Task 2's modes + developer layout.
- Produces: user docs at `app/docs/user/<slug>.md`; `config.categories` fully path-prefixed (final form below).

- [ ] **Step 1: `git mv` the user docs**

```bash
cd app/docs && mkdir -p user
for d in accounts workspaces projects onboarding clientside project-tools emails application-flows; do
  git mv "$d.md" "user/$d.md"
done
git mv notifications.md user/notifications.md
cd -
```

- [ ] **Step 2: Drop `audience:` frontmatter from the moved user docs** (`grep -rl "^audience:" app/docs/user/` → no output).

- [ ] **Step 3: Finalize `config.categories`** to the complete path-prefixed map:

```ruby
  template_categories = {
    "Getting Started"            => %w[getting-started],
    # NOTE: user/authentication + user/invitations are ADDED in Task 4 (with their
    # files), so the "no stale slugs" check stays green here. Do NOT list them yet.
    "Accounts & Authentication"  => %w[user/accounts],
    "Workspaces & Collaboration" => %w[user/workspaces user/projects user/onboarding user/clientside],
    "Features"                   => %w[user/notifications user/emails user/project-tools user/application-flows],
    "Presets (Tenancy)"          => %w[developer/presets developer/presets-solo developer/presets-single-tenant developer/presets-open-saas developer/presets-none],
    "Architecture & Data Model"  => %w[developer/architecture developer/accounts-and-identity developer/identity-system],
    "Building & Extending"       => %w[developer/extending developer/forking developer/components developer/ui-patterns],
    "Operations"                 => %w[developer/deployment developer/background-jobs developer/security],
    "Quality & Testing"          => %w[developer/accessibility developer/qa-flows],
    "Auth & Notifications (internals)" => %w[developer/passkeys developer/notifications],
    "Troubleshooting"            => %w[troubleshooting],
  }
```

(`user/authentication` + `user/invitations` are referenced here but created in Task 4 — index_coverage will be RED between this task and Task 4 for exactly those two slugs. Acceptable within the task pair; Step 5 below notes the expected partial state, and Task 4 closes it. If you prefer each task green, defer adding those two slug entries until Task 4.)

- [ ] **Step 4: Fix specs that read moved user docs by path** — `auth_docs_accuracy_spec` (`emails` → `app/docs/user/emails.md`, `accounts` → `app/docs/user/accounts.md`) and confirm `application_flows_svg_spec` finds `app/docs/user/application-flows.md` via its recursive glob.

- [ ] **Step 5: Verify** (to keep this task self-green, add the `user/authentication` + `user/invitations` slugs to config in Task 4, not here — so run with them omitted)

Run: `mise exec -- bundle exec rspec spec/docs/`
Expected: green (every file categorized, no stale slugs).

- [ ] **Step 6: Commit**

```bash
git add -A app/docs config/initializers/markdowndocs.rb spec/docs
git commit -m "docs(reorg): move user docs to app/docs/user/; notifications -> user/+developer/"
```

---

### Task 4: Carve `user/authentication` + `user/invitations`

**Files:**
- Create: `app/docs/user/authentication.md`
- Create: `app/docs/user/invitations.md`
- Modify: `config/initializers/markdowndocs.rb` (the two slugs are already in the map from Task 3)

**Interfaces:**
- Consumes: the merged Phase C auth content (`user/emails`, `developer/passkeys`, `user/accounts`) as source material.

- [ ] **Step 1: Write `app/docs/user/authentication.md`** — front matter (`title: Authentication`, a `description`, `keywords`), then sections assembled (not invented) from existing docs: how signing in works from the user's side — magic-link (passwordless-first, from `user/emails`), passkeys (the user-facing summary, link to `developer/passkeys` for config), OAuth (Google/GitHub), "forgot password" → magic-link recovery, and what happens on first sign-in (name capture, the passkey enrollment banner). Cross-link `/docs/user/emails`, `/docs/user/invitations`, `/docs/developer/passkeys`.

- [ ] **Step 2: Write `app/docs/user/invitations.md`** — front matter, then: receiving a workspace/project/client invitation email, accepting (signed-in vs new user → magic-link registration → claimed on email verification), declining, the email-match guard, and the clientside variant. Assemble from `user/emails` (Invitation Acceptance flow) + `user/clientside`. Cross-link `/docs/user/workspaces`, `/docs/user/clientside`.

- [ ] **Step 3: Confirm both slugs are in `config.categories`** (added in Task 3 Step 3 under "Accounts & Authentication" / "Workspaces & Collaboration").

- [ ] **Step 4: Verify green**

Run: `mise exec -- bundle exec rspec spec/docs/ && mise exec -- bundle exec rake markdown:check`
Expected: index_coverage green (no orphans, no stale slugs — the two carved files now back their slugs).

- [ ] **Step 5: Commit**

```bash
git add app/docs/user/authentication.md app/docs/user/invitations.md
git commit -m "docs(user): carve authentication + invitations from existing auth content"
```

---

### Task 5: Cross-link sweep + old-URL redirects

**Files:**
- Modify: `app/docs/**/*.md` (internal `/docs/<slug>` links → `/docs/<mode>/<slug>`)
- Modify: `config/routes/app.rb` (redirects for moved root slugs) + Test: `spec/requests/docs_redirects_spec.rb`

**Interfaces:**
- Consumes: the final file layout + the audience mapping (to know each slug's new mode path).

- [ ] **Step 1: Sweep internal cross-links.** For every `(/docs/<slug>)` in `app/docs/**/*.md`, rewrite to its new path: developer docs → `/docs/developer/<slug>`, user docs → `/docs/user/<slug>`, root (`getting-started`, `troubleshooting`) unchanged. Special: `/docs/notifications` → `/docs/user/notifications`; `/docs/notifications-technical` → `/docs/developer/notifications`. Verify none stale: `grep -rohE "\(/docs/[a-z0-9-]+\)" app/docs` should only show `/docs/getting-started` and `/docs/troubleshooting`.

- [ ] **Step 2: Write the redirect spec (failing)**

```ruby
# spec/requests/docs_redirects_spec.rb
require "rails_helper"
RSpec.describe "Docs old-URL redirects", type: :request do
  { "architecture" => "developer/architecture", "accounts" => "user/accounts" }.each do |old, new|
    it "redirects /docs/#{old} to /docs/#{new}" do
      get "/docs/#{old}"
      expect(response).to redirect_to("/docs/#{new}")
    end
  end
end
```

- [ ] **Step 3: Run it — Expected: FAIL** (`/docs/architecture` 404s or renders nothing).

- [ ] **Step 4: Add redirects** in `config/routes/app.rb` (before/around the engine mount), generated from the mapping — one `get "/docs/<old>", to: redirect("/docs/<mode>/<old>")` per moved doc (all 28 non-root slugs, plus `/docs/notifications-technical` → `/docs/developer/notifications`).

- [ ] **Step 5: Run the redirect spec — Expected: PASS.**

- [ ] **Step 6: Commit**

```bash
git add app/docs config/routes/app.rb spec/requests/docs_redirects_spec.rb
git commit -m "docs(reorg): update cross-links + add old-URL redirects to mode paths"
```

---

### Task 6: Full verification + finish

- [ ] **Step 1: Full suite** — `mise exec -- bundle exec rspec` → 0 failures.
- [ ] **Step 2: `mise exec -- bundle exec rake markdown:check`** → clean; `mise exec -- bundle exec rake erb:check` → exit 0.
- [ ] **Step 3: Manual render check** — `bin/dev`, visit `/docs` (user mode default), toggle to developer, confirm both indexes group correctly and a mode-scoped doc serves at `/docs/developer/architecture`; an old URL `/docs/architecture` redirects.
- [ ] **Step 4: Finish** — Use superpowers:finishing-a-development-branch (push + PR).
