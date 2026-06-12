# Fork Seams + Forking Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the four fork-disentanglement seams (PR A), then the JumpstartPro-style forking guide that documents them (PR B), so the first downstream app (sonicpics) can clone, rename, and merge upstream updates with minimal conflicts.

**Architecture:** Convert shared-file edits into fork-created files using Rails' native overlay points: i18n locale-file merging (brand strings), `draw(:app)` route files (product routes), an optional local YAML merged by an initializer (docs categories), and git per-path `merge=ours` drivers (fork-owned files). Docs live in the in-app markdowndocs engine so forks inherit them.

**Tech Stack:** Rails 8.1, RSpec, markdowndocs gem, git attributes/merge drivers, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-06-12-fork-seams-and-forking-docs-design.md`

**Branch state:** `feat/fork-seams` already exists with the spec committed (`c11321b`), branched from main @ `0fea487`. Tasks 1–5 happen there. Tasks 6–9 happen on `docs/forking-guide` (created in Task 6).

**House rules that apply:** TDD (failing spec first, every task). Full suite + 0 failures before every commit-to-push. Never `LEFTHOOK=0`. Conventional commits, no Co-Authored-By lines. Markdown needs blank lines around headings/code blocks/lists (markdownlint runs in CI).

**Verified facts the plan relies on (do not re-derive):**

- `app/views/layouts/application.html.erb:6,8` already use `t("application.name")` / `t("application.description")`; `app/views/shared/_footer.html.erb:59` already uses `t("footer.copyright")`. Seam 1 moves key *definitions* only — no view edits.
- `config/locales/en/application.en.yml` defines the three brand keys at lines 3, 4, and 58.
- `config/routes.rb` is 112 lines; the product routes are the 4 lines `root "pages#home"` / about / privacy / contact. `config/routes/` does not exist yet.
- Files loaded by `draw(:app)` contain the **bare** routing DSL (no `Rails.application.routes.draw do` wrapper) — Rails instance_evals them in the mapper.
- `spec/docs/index_coverage_spec.rb` reads `Markdowndocs.configuration.categories` (the booted, post-merge value) — it needs **no changes** for the overlay seam.
- The only spec asserting a brand literal is `spec/code_smells/template_invariants_spec.rb:228` (`/modelrails-bundle-cache/`). Lookbook preview fixtures mention "ModelRails" as sample copy but assert nothing.
- In-app docs need YAML frontmatter (`title`, `description`, `keywords`, `audience: [guide, technical]`) and a category entry in `config/initializers/markdowndocs.rb`, or `index_coverage_spec` fails (that failure is Task 6's red step).

---

## File map

**PR A (`feat/fork-seams`):**

| File | Action | Responsibility |
| --- | --- | --- |
| `config/locales/en/brand.en.yml` | Create | Fork-owned home of identity strings |
| `config/locales/en/application.en.yml` | Modify | Drop the 3 moved keys |
| `config/routes/app.rb` | Create | Fork-owned product routes |
| `config/routes.rb` | Modify | Replace 4 product routes with `draw(:app)` |
| `.gitattributes` | Modify | `merge=ours` markers for fork-owned paths |
| `config/initializers/markdowndocs.rb` | Modify | Merge optional local categories file |
| `spec/docs/markdowndocs_local_categories_spec.rb` | Create | Behavior spec for the overlay merge |
| `spec/code_smells/template_invariants_spec.rb` | Modify | New "Fork seams" describe + brand-agnostic volume regex |
| `CHANGELOG.md` | Modify | One-line entry under [Unreleased] |

**PR B (`docs/forking-guide`):**

| File | Action | Responsibility |
| --- | --- | --- |
| `app/docs/forking.md` | Create | The full forking guide (rendered at `/docs/forking`) |
| `config/initializers/markdowndocs.rb` | Modify | Register `forking` under Guides |
| `README.md` | Modify | Slim the forking section to clone commands + pointer |
| `CHANGELOG.md` | Modify | One-line entry |
| GitHub issues ×3 | Create | Trigger-based backlog (rename script, CSP seam, theme seam) |

---

## PR A — fork seams

### Task 1: Brand locale seam

**Files:**

- Modify: `spec/code_smells/template_invariants_spec.rb` (append new describe before the final `end`)
- Create: `config/locales/en/brand.en.yml`
- Modify: `config/locales/en/application.en.yml`

- [ ] **Step 1: Write the failing invariant specs**

Open `spec/code_smells/template_invariants_spec.rb`. Inside the top-level `RSpec.describe "Template invariants" do`, append this describe block before its closing `end` (match the file's existing style — it asserts file contents, not behavior):

```ruby
  describe "Fork seams (downstream disentanglement — see /docs/forking)" do
    it "keeps brand identity strings in the fork-owned brand locale file" do
      brand = YAML.load_file(Rails.root.join("config/locales/en/brand.en.yml"))
      expect(brand.dig("en", "application", "name")).to be_present
      expect(brand.dig("en", "application", "description")).to be_present
      expect(brand.dig("en", "footer", "copyright")).to be_present
    end

    it "defines no brand strings in template-owned locale files (forks edit brand.en.yml only)" do
      app_locale = YAML.load_file(Rails.root.join("config/locales/en/application.en.yml"))
      expect(app_locale.dig("en", "application", "name")).to be_nil
      expect(app_locale.dig("en", "application", "description")).to be_nil
      expect(app_locale.dig("en", "footer", "copyright")).to be_nil
    end

    it "still resolves the brand translations after the move (the views did not change)" do
      expect(I18n.exists?("application.name")).to be(true)
      expect(I18n.exists?("application.description")).to be(true)
      expect(I18n.exists?("footer.copyright")).to be(true)
    end
  end
```

Note the assertions are **brand-agnostic** (presence, not `eq "ModelRails"`) — a renamed fork must pass them unmodified.

- [ ] **Step 2: Run, verify red**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 2 failures (no such file `brand.en.yml`; `application.name` still present in `application.en.yml`). The third example passes — it's the regression guard for the move.

- [ ] **Step 3: Create the brand file and remove the moved keys**

Create `config/locales/en/brand.en.yml`:

```yaml
# Fork-owned: your app's identity strings live here and nowhere else.
# Upstream (modelrails_base) freezes this file after creation — edit freely
# in a fork without merge conflicts. See /docs/forking.
en:
  application:
    name: "ModelRails"
    description: "A multi-tenant SaaS starter kit built on Rails."
  footer:
    copyright: "ModelRails. All rights reserved."
```

In `config/locales/en/application.en.yml`, delete exactly these lines (keys move, structure stays):

- Line 3 (under `application:`): `name: "ModelRails"`
- Line 4 (under `application:`): `description: "A multi-tenant SaaS starter kit built on Rails."`
- Line 58 (under `footer:`): `copyright: "ModelRails. All rights reserved."`

The `application:` key keeps `skip_to_content`; the `footer:` key keeps its nav labels and `aria:` block. Rails merges all locale files in `config/locales/en/`, so `t("application.name")` resolves exactly as before.

- [ ] **Step 4: Run, verify green**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 3 examples, 0 failures.

Then smoke the rendering paths that consume the keys:

Run: `bundle exec rspec spec/requests --fail-fast`
Expected: 0 failures (layout title/description and footer render on every page).

- [ ] **Step 5: Commit**

```bash
git add spec/code_smells/template_invariants_spec.rb config/locales/en/brand.en.yml config/locales/en/application.en.yml
git commit -m "feat(fork-seams): move brand identity strings to fork-owned brand.en.yml"
```

### Task 2: Routes seam

**Files:**

- Modify: `spec/code_smells/template_invariants_spec.rb` (extend the "Fork seams" describe)
- Create: `config/routes/app.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the failing invariant spec**

Append inside the `describe "Fork seams …"` block from Task 1:

```ruby
    it "draws product routes from the fork-owned config/routes/app.rb" do
      expect(File.read(Rails.root.join("config/routes.rb"))).to include("draw(:app)")
      expect(File.read(Rails.root.join("config/routes/app.rb"))).to include('root "pages#home"')
    end
```

- [ ] **Step 2: Run, verify red**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 1 failure (`config/routes/app.rb` does not exist).

- [ ] **Step 3: Create the route file and the draw call**

Create `config/routes/app.rb` (bare DSL — **no** `Rails.application.routes.draw do` wrapper; `draw(:app)` instance_evals this file in the mapper):

```ruby
# Fork-owned: your product's routes live here. Upstream (modelrails_base)
# freezes this file after creation — add and rewrite routes freely in a fork
# without merge conflicts on config/routes.rb. See /docs/forking.

root "pages#home"
get "about", to: "pages#about"
get "privacy", to: "pages#privacy"
get "contact", to: "pages#contact"
```

In `config/routes.rb`, replace these four lines:

```ruby
  root "pages#home"
  get "about", to: "pages#about"
  get "privacy", to: "pages#privacy"
  get "contact", to: "pages#contact"
```

with:

```ruby
  # Fork seam: product routes (root, marketing pages, your features) live in
  # the fork-owned config/routes/app.rb. See /docs/forking.
  draw(:app)
```

- [ ] **Step 4: Run, verify green + routes still resolve**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 4 examples, 0 failures.

Run: `bin/rails routes -g pages`
Expected: `root`, `about`, `privacy`, `contact` all listed, identical to before.

Run: `bundle exec rspec spec/requests --fail-fast`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add spec/code_smells/template_invariants_spec.rb config/routes/app.rb config/routes.rb
git commit -m "feat(fork-seams): draw product routes from fork-owned config/routes/app.rb"
```

### Task 3: Fork-owned contract (.gitattributes merge=ours + brand-agnostic invariants)

**Files:**

- Modify: `spec/code_smells/template_invariants_spec.rb` (extend "Fork seams" describe; fix line ~228)
- Modify: `.gitattributes`

- [ ] **Step 1: Write the failing invariant spec**

Append inside the `describe "Fork seams …"` block:

```ruby
    it "marks fork-owned paths merge=ours so upstream syncs keep the fork's version" do
      gitattributes = File.read(Rails.root.join(".gitattributes"))
      %w[
        app/views/pages/**
        app/controllers/pages_controller.rb
        config/locales/en/pages.en.yml
        config/locales/en/brand.en.yml
        config/routes/app.rb
        config/markdowndocs_categories.local.yml
        README.md
      ].each do |path|
        expect(gitattributes).to match(/^#{Regexp.escape(path)} merge=ours$/),
          "expected .gitattributes to mark #{path} merge=ours"
      end
    end
```

- [ ] **Step 2: Run, verify red**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 1 failure (no merge=ours entries yet).

- [ ] **Step 3: Append the entries to `.gitattributes`**

Append to the existing `.gitattributes` (after the credentials lines):

```text

# Fork-owned paths — downstream forks rewrite these wholesale; upstream
# freezes them. In a fork, run `git config merge.ours.driver true` once
# (see /docs/forking) and `git merge upstream/main` auto-resolves these
# paths in the fork's favor. Inert in this repo (driver unset upstream).
app/views/pages/** merge=ours
app/controllers/pages_controller.rb merge=ours
config/locales/en/pages.en.yml merge=ours
config/locales/en/brand.en.yml merge=ours
config/routes/app.rb merge=ours
config/markdowndocs_categories.local.yml merge=ours
README.md merge=ours
```

`db/seeds.rb` is deliberately **not** listed — its preset section is template-owned; forks extend below it (documented in PR B).

- [ ] **Step 4: Make the devcontainer volume assertion brand-agnostic**

In `spec/code_smells/template_invariants_spec.rb` around line 228 (inside `it "mounts a named volume for the bundle cache (survives container rebuilds)"`), change:

```ruby
      expect(mounts).to include(match(/modelrails-bundle-cache/)),
```

to:

```ruby
      expect(mounts).to include(match(/bundle-cache/)),
```

(If the failure-message string on the following line also names `modelrails-bundle-cache`, generalize it to `bundle-cache` too.) This lets a renamed fork rename the devcontainer volume without touching template-owned specs.

- [ ] **Step 5: Run, verify green**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb`
Expected: all examples in the file pass (the whole file, not just the new describe — Step 4 touched an existing example).

- [ ] **Step 6: Commit**

```bash
git add spec/code_smells/template_invariants_spec.rb .gitattributes
git commit -m "feat(fork-seams): merge=ours contract for fork-owned paths; brand-agnostic volume invariant"
```

### Task 4: Markdowndocs local-categories overlay

**Files:**

- Create: `spec/docs/markdowndocs_local_categories_spec.rb`
- Modify: `config/initializers/markdowndocs.rb`

- [ ] **Step 1: Write the failing behavior spec**

The merge logic lives in an initializer, which can't be called as a unit — so the spec stubs the local file into existence, re-`load`s the initializer, asserts the merged result, and restores the real configuration in `ensure`. Create `spec/docs/markdowndocs_local_categories_spec.rb`:

```ruby
require "rails_helper"

# Fork seam: the markdowndocs initializer merges an optional fork-owned
# categories file (config/markdowndocs_categories.local.yml) into the template
# category map, so a downstream fork registers its own /docs pages without
# editing template-owned files. The file is deliberately absent upstream —
# these specs stub it into existence. See /docs/forking.
RSpec.describe "Markdowndocs local categories overlay" do
  let(:initializer) { Rails.root.join("config/initializers/markdowndocs.rb") }
  let(:local_path) { Rails.root.join("config/markdowndocs_categories.local.yml") }

  def stub_local_file(categories)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(local_path).and_return(true)
    allow(YAML).to receive(:load_file).and_call_original
    allow(YAML).to receive(:load_file).with(local_path).and_return(categories)
  end

  def restore_real_configuration
    allow(File).to receive(:exist?).and_call_original
    allow(YAML).to receive(:load_file).and_call_original
    load initializer
  end

  it "merges fork categories into the template map" do
    stub_local_file("My Product" => %w[my-feature])
    load initializer
    expect(Markdowndocs.configuration.categories["My Product"]).to eq(%w[my-feature])
    expect(Markdowndocs.configuration.categories["Getting Started"]).to eq(%w[getting-started])
  ensure
    restore_real_configuration
  end

  it "appends fork slugs when the fork extends an existing template category" do
    stub_local_file("Guides" => %w[my-guide])
    load initializer
    expect(Markdowndocs.configuration.categories["Guides"]).to include("extending", "my-guide")
  ensure
    restore_real_configuration
  end

  it "leaves the template map untouched when no local file exists (this repo)" do
    expect(File.exist?(local_path)).to be(false)
    expect(Markdowndocs.configuration.categories).to include("Getting Started", "Guides")
  end
end
```

- [ ] **Step 2: Run, verify red**

Run: `bundle exec rspec spec/docs/markdowndocs_local_categories_spec.rb`
Expected: 2 failures ("My Product" key absent; "my-guide" not in Guides). The third example passes today.

- [ ] **Step 3: Implement the merge in the initializer**

In `config/initializers/markdowndocs.rb`, change the categories assignment. Replace `config.categories = {` … `}` (lines 16–29) so the hash is assigned to a local and merged (keep the existing comments and hash contents verbatim):

```ruby
  template_categories = {
    "Getting Started" => %w[getting-started],
    # The presets hub + its three per-preset spokes form their own cluster,
    # placed second so it reads as the next step after "getting started".
    "Presets" => %w[presets presets-solo presets-single-tenant presets-open-saas],
    "Architecture" => %w[architecture],
    # `notifications` (audience: guide) and `notifications-technical`
    # (audience: technical) are paired companion docs — the mode switcher
    # shows whichever matches the viewer's mode, with no cross-category
    # split. Listing both here keeps the topic discoverable from the
    # canonical "Features" category in either mode.
    "Features" => %w[accounts workspaces projects identity-system emails notifications notifications-technical],
    "Guides" => %w[extending security ui-patterns components accessibility deployment background-jobs troubleshooting]
  }

  # Fork seam: a downstream fork registers its own docs pages in
  # config/markdowndocs_categories.local.yml (absent upstream) instead of
  # editing this initializer. Same-named categories append. See /docs/forking.
  local_path = Rails.root.join("config/markdowndocs_categories.local.yml")
  local_categories = File.exist?(local_path) ? YAML.load_file(local_path) || {} : {}
  config.categories = template_categories.merge(local_categories) do |_category, template_slugs, fork_slugs|
    template_slugs + fork_slugs
  end
```

The merge block matters: without it, a fork extending `"Guides"` would *replace* the template's slugs, orphaning template docs and tripping `index_coverage_spec`'s stale-slug guard.

- [ ] **Step 4: Run, verify green**

Run: `bundle exec rspec spec/docs/`
Expected: both spec files pass (`index_coverage_spec` needs no changes — it reads the booted, post-merge configuration).

- [ ] **Step 5: Commit**

```bash
git add spec/docs/markdowndocs_local_categories_spec.rb config/initializers/markdowndocs.rb
git commit -m "feat(fork-seams): docs categories overlay via markdowndocs_categories.local.yml"
```

### Task 5: PR A wrap-up

**Files:**

- Modify: `CHANGELOG.md`

- [ ] **Step 1: CHANGELOG entry**

Under `## [Unreleased]`, in the `### Added` subsection (create it after the existing subsections if absent, matching the file's one-line-per-entry style):

```markdown
- Fork seams for downstream apps: brand strings in fork-owned `config/locales/en/brand.en.yml`, product routes in `config/routes/app.rb` via `draw(:app)`, `/docs` categories extendable through `config/markdowndocs_categories.local.yml`, and fork-owned paths marked `merge=ours` in `.gitattributes`.
```

- [ ] **Step 2: Full suite**

Run: `bundle exec rspec`
Expected: 0 failures, 0 pending-without-reason. Do not push on anything less.

- [ ] **Step 3: Commit, push, open PR**

```bash
git add CHANGELOG.md
git commit -m "chore: changelog entry for fork seams"
git push -u origin feat/fork-seams   # Lefthook pre-push runs the CI mirror — let it
gh pr create --title "feat: fork seams — disentangle downstream apps from template-owned files" --body "$(cat <<'EOF'
Four seams so downstream forks (first: sonicpics) edit fork-created files instead of template-owned ones — upstream merges stay conflict-free by construction. Per the approved design (docs/superpowers/specs/2026-06-12-fork-seams-and-forking-docs-design.md):

- **Brand locale file** — `config/locales/en/brand.en.yml` now defines `application.name`, `application.description`, `footer.copyright`. Zero call-site changes (views already used `t()`).
- **Routes seam** — `draw(:app)` loads fork-owned `config/routes/app.rb` (root + marketing pages moved there). Minimal subset of the panel-deferred full routes split.
- **Fork-owned contract** — `.gitattributes` marks pages views/controller, marketing + brand locales, `routes/app.rb`, the local categories file, and README `merge=ours` (driver is opt-in per clone; inert upstream). Devcontainer volume invariant made brand-agnostic (`/bundle-cache/`).
- **Docs categories overlay** — `config/markdowndocs_categories.local.yml` (absent upstream) merges into the category map; same-named categories append. `index_coverage_spec` unchanged — it reads the booted config.

Docs PR (forking guide at `/docs/forking`) follows and documents all four.
EOF
)"
```

- [ ] **Step 4: Watch CI**

Run: `gh pr checks --watch`
Expected: all green. If infra-transient (all jobs fail in 2–30s at setup), `gh run rerun <id> --failed` once before investigating.

**Do not merge yet if the user hasn't seen it** — but per standing preference the user merges green PRs themselves.

---

## PR B — forking documentation

### Task 6: The forking guide

**Files:**

- Create: `app/docs/forking.md`
- Modify: `config/initializers/markdowndocs.rb` (register the slug)

- [ ] **Step 1: Branch off PR A's branch**

```bash
git checkout -b docs/forking-guide   # from feat/fork-seams — the guide documents those seams
```

(If PR A has already merged, branch from updated `main` instead.)

- [ ] **Step 2: Create the doc (this is also the red step)**

Create `app/docs/forking.md` with exactly this content:

````markdown
---
title: Forking
description: Start a downstream app from this template and keep merging upstream improvements
keywords: fork template upstream downstream merge sync rename clone brand seams update jumpstart
audience: [guide, technical]
---

# Forking this template

ModelRails is an **upstream template**: you clone it to start a product, build in
fork-owned files, and periodically merge upstream improvements back in — the same
workflow commercial Rails templates like Jumpstart Pro use.

Three things make the merges cheap:

1. **Shared git history** — your app is a true clone, so `git merge upstream/main`
   is an ordinary merge.
2. **Fork-owned files** — everything you are expected to rewrite (marketing pages,
   brand strings, your routes, your docs) lives in files upstream never edits again.
3. **A merge driver** — fork-owned paths are marked `merge=ours` in
   `.gitattributes`, so syncs resolve them in your favor automatically.

## Start a new app

Create an **empty** private repository on GitHub first (no README, no license — it
must be truly empty). Then:

```bash
git clone git@github.com:dschmura/modelrails_base.git myapp
cd myapp

# The template becomes a read-only "upstream" remote
git remote rename origin upstream
git remote set-url --push upstream DISABLED   # a stray `git push upstream` now fails loudly

# Your new repository becomes origin
git remote add origin git@github.com:YOU/myapp.git
git push -u origin main

# Activate the fork-owned merge driver (one-time, per clone)
git config merge.ours.driver true
```

> **Why not GitHub's "Use this template" button, or a GitHub fork?** "Use this
> template" squashes the entire history into one unrelated commit — every later
> `git merge upstream/main` would need `--allow-unrelated-histories` and conflict
> on everything. And GitHub will not fork a repository into the account that
> already owns it. Clone + re-pointed remotes gives you a private repo **and**
> mergeable history.

Every teammate's clone of your new repository repeats the two one-time commands:

```bash
git remote add upstream git@github.com:dschmura/modelrails_base.git
git config merge.ours.driver true
```

## Rename the identity

Do this before your first commit, so the rename is one clean commit you can always
find again.

| What | Where | Notes |
| ---- | ----- | ----- |
| Ruby module name | `config/application.rb` (`module ModelrailsBase`) | `bin/rails app:update` won't do this for you |
| Kamal service name | `config/deploy.yml` (`service:`) | Tags Docker containers; collides if two apps share a host |
| Docker image name | `config/deploy.yml` (`image:`) | Must match your registry path |
| Storage volume names | `config/deploy.yml` (`volumes:`) | Renaming later orphans the old volume — do it before first deploy |
| Brand strings | `config/locales/en/brand.en.yml` | Product name, description, copyright — fork-owned, one file |
| Marketing copy | `config/locales/en/pages.en.yml` + `app/views/pages/` | Fork-owned — rewrite wholesale |
| PWA app name | `public/manifest.webmanifest` + `app/views/pwa/manifest.json.erb` | Shown on the home screen if users install the PWA |
| CI image tags | `.github/workflows/ci.yml` + `image_scan.yml` (`tags:`) | Local-only build tags; cosmetic but confusing if stale |
| npm lockfile name | `package-lock.json` | Auto-derived from the directory name — regenerates on `npm install` |
| Devcontainer bundle-cache volume | `.devcontainer/devcontainer.json` | Optional; the invariant spec only checks the `bundle-cache` suffix |
| Session cookie key | optional `config/initializers/session_store.rb` | Only if multiple forks will share a cookie domain |

Then verify nothing was missed:

```bash
grep -ri modelrails . \
  --exclude-dir={.git,node_modules,tmp,log,coverage,storage,vendor} \
  --exclude=package-lock.json
bundle exec rspec
```

Expected leftovers: references to the **modelrails_ui** design-system gem
(`Gemfile`, `.modelrails_ui/`, generated component comments) — that's the
library's name, not your app's. Lookbook preview sample copy under
`spec/components/previews/` also mentions ModelRails; rename it or leave it,
nothing asserts on it. The full test suite and CI's production-image build are
the rename's safety net.

## Bootstrap secrets and configuration

The template ships **zero** encrypted credential blobs — your fork generates its
own on first edit:

```bash
bin/rails credentials:edit --environment development
bin/rails credentials:edit --environment production
```

Add OAuth keys and `mailer.from` (structure in [Getting Started](getting-started)).
Your fork **may** commit its own `.yml.enc` blobs — normal for a private app; the
`.key` files stay gitignored. `.kamal/secrets` reads
`config/credentials/production.key` at deploy time.

For production you'll also set `RAILS_HOST`, pick a tenancy preset
(`TENANCY_ONBOARDING`), and choose a signup mode — see `.env.example`,
[Presets](presets), and [Deployment](deployment).

## Fork-owned files

These paths are yours. Upstream froze them the day the seams shipped and will
never meaningfully change them again; the `merge=ours` driver keeps your version
on every sync.

| Path | What goes there |
| ---- | --------------- |
| `config/locales/en/brand.en.yml` | Product name, description, copyright |
| `config/locales/en/pages.en.yml` | Marketing copy for your pages |
| `app/views/pages/**`, `app/controllers/pages_controller.rb` | Your marketing/static pages |
| `config/routes/app.rb` | Your product's routes (loaded by `draw(:app)`) |
| `config/markdowndocs_categories.local.yml` | Registers your own docs pages on this `/docs` index |
| `README.md` | Your product's README |

One caveat to know: with the driver active, upstream changes to these paths are
**silently discarded** in your fork — that is the point; they're yours. If you
ever want an upstream improvement to one of them (say, a marketing-page
restyle), cherry-pick it deliberately.

`db/seeds.rb` is shared ground: the tenancy-preset bootstrap at the top is
template-owned; add your domain seeds below it.

### Adding your own docs page

Drop `app/docs/my-feature.md` (same frontmatter as this file), then create
`config/markdowndocs_categories.local.yml`:

```yaml
My Product:
  - my-feature
```

Categories named like template ones ("Guides", "Features") **append** to them;
new names become new index sections. The docs-coverage spec keeps guarding
orphaned pages across both maps automatically.

## Pull upstream updates

```bash
git fetch upstream
git log --oneline main..upstream/main   # review what's coming; read CHANGELOG.md too

git checkout -b chore/upstream-sync-$(date +%F)
git merge upstream/main
```

Conflict doctrine:

| Conflict in | Resolution |
| ----------- | ---------- |
| Fork-owned paths | None — the merge driver already kept yours |
| Identity values (`config/deploy.yml` service/image/volumes, `config/application.rb` module) | Keep your names; take structural changes around them |
| Behavior (app code, specs, config) | Take theirs — unless you deliberately diverged, in which case consider sending your version upstream instead |
| `Gemfile.lock`, `package-lock.json` | Never hand-merge: take either side, then `bundle install` / `npm install` and commit the regenerated files |

Then prove the merge:

```bash
bin/rails db:migrate    # upstream may ship migrations
bundle exec rspec       # full suite green before the PR
```

Open a pull request into your app's main branch like any other change. A good
cadence is after each meaningful upstream change, or monthly — small merges stay
small.

## Contribute a fix back

Make template-worthy fixes in a checkout of `modelrails_base` itself (branch →
PR), not in your app — `upstream` is push-disabled by design. If the fix already
exists as a commit in your app:

```bash
cd ../modelrails_base
git checkout -b fix/thing main
git remote add myapp ../myapp && git fetch myapp
git cherry-pick <sha>
```

Strip anything product-specific before opening the PR.

## Stay mergeable

- **Prefer new files to edited template files** — new files merge clean by
  definition. New models, controllers, components, initializers, docs pages: all
  conflict-free.
- **Brand strings only in `brand.en.yml`** — if you find one hardcoded anywhere
  else, that's an upstream bug; report or fix it upstream.
- **Product routes only in `config/routes/app.rb`** — leave `config/routes.rb`
  to the template.
- **Treat `UI::*` primitives as upstream-owned** — extend by composing new
  components rather than editing the primitives; the planned design-system
  update engine will regenerate them.
- **When you must edit a template file** (adding a nav item, a new Gemfile
  entry), make the edit additive — append rather than rewrite — so the merge has
  one obvious resolution.
````

- [ ] **Step 3: Run, verify red**

Run: `bundle exec rspec spec/docs/index_coverage_spec.rb`
Expected: 1 failure — `forking` is an uncategorized orphan. (This is the natural failing test for doc registration.)

- [ ] **Step 4: Register the slug**

In `config/initializers/markdowndocs.rb`, change the Guides line inside `template_categories`:

```ruby
    "Guides" => %w[extending security ui-patterns components accessibility deployment background-jobs troubleshooting forking]
```

- [ ] **Step 5: Run, verify green + render check**

Run: `bundle exec rspec spec/docs/`
Expected: 0 failures.

Run: `bin/dev` (or existing server), visit `http://localhost:3000/docs/forking` — page renders with title, tables, and code blocks intact; it appears under Guides on `/docs`. (Render truth is browser-only — do this, don't skip it.)

- [ ] **Step 6: Commit**

```bash
git add app/docs/forking.md config/initializers/markdowndocs.rb
git commit -m "docs: in-app forking guide at /docs/forking"
```

### Task 7: README slimming

**Files:**

- Modify: `README.md` (lines 83–116, the "Forking this template" section)

- [ ] **Step 1: Replace the section**

Replace everything from `## Forking this template` (line 83) up to (not including) `## What's included (Phase 1)` (line 118) with:

````markdown
## Forking this template

This repo is an upstream template: clone it with full history, build your product
in fork-owned files, and merge upstream improvements back in periodically.

```bash
git clone git@github.com:dschmura/modelrails_base.git myapp
cd myapp
git remote rename origin upstream
git remote set-url --push upstream DISABLED
git remote add origin git@github.com:YOU/myapp.git   # an empty repo — no README/license
git push -u origin main
git config merge.ours.driver true                    # activates the fork-owned merge driver
```

The complete guide — identity-rename checklist, secrets bootstrap, the fork-owned
file contract, and the upstream-update workflow — lives in
[app/docs/forking.md](app/docs/forking.md), rendered at `/docs/forking` in the
running app. Your fork inherits it.
````

(The session-cookie and credentials details now live in the guide — do not duplicate them here.)

- [ ] **Step 2: Lint and commit**

Run: `npx markdownlint-cli README.md` (CI's lint_docs mirror; if npx is unavailable locally, Lefthook pre-push will catch it)
Expected: clean.

```bash
git add README.md
git commit -m "docs: slim README forking section to clone commands + pointer to /docs/forking"
```

### Task 8: PR B wrap-up

**Files:**

- Modify: `CHANGELOG.md`

- [ ] **Step 1: CHANGELOG entry**

Under `## [Unreleased]` → `### Added`:

```markdown
- In-app forking guide at `/docs/forking` — start a downstream app, rename the identity, pull upstream updates; the README forking section now points there.
```

- [ ] **Step 2: Full suite, push, PR**

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add CHANGELOG.md
git commit -m "chore: changelog entry for forking guide"
git push -u origin docs/forking-guide
```

**If PR A has not merged yet:** wait (`gh pr view <A-number> --json state,mergedAt`) — the user merges green PRs promptly. Once merged, rebase onto main and open the PR:

```bash
git fetch origin main
git rebase origin/main   # drops the duplicated seam commits if A was squash-merged; resolve nothing by hand without diffing first
git push --force-with-lease
gh pr create --base main --title "docs: JumpstartPro-style forking guide at /docs/forking" --body "$(cat <<'EOF'
The documentation half of the fork-workflow design (spec: docs/superpowers/specs/2026-06-12-fork-seams-and-forking-docs-design.md). Follows the fork-seams PR and documents the shipped seams.

- New in-app guide `/docs/forking` (forks inherit it): start a new app via clone + re-pointed remotes (with the "Use this template" history warning), identity-rename checklist (+ devcontainer volume row), secrets bootstrap, the fork-owned file contract and merge driver, upstream-sync workflow with conflict doctrine, contributing back, staying mergeable.
- README forking section slimmed to clone commands + pointer (single source of truth in the guide).
EOF
)"
gh pr checks --watch
```

### Task 9: Backlog issues

- [ ] **Step 1: Check for existing issues first (open + closed)**

```bash
gh issue list --state all --search "rename" --json number,title,state
gh issue list --state all --search "CSP oauth" --json number,title,state
gh issue list --state all --search "theme seam brand color" --json number,title,state
```

Expected: no duplicates. If any exist, comment on them instead of creating new ones.

- [ ] **Step 2: Create the three trigger-based issues**

```bash
gh issue create --title "bin/rename-app: one-command fork identity rename" --body "$(cat <<'EOF'
Script the manual rename checklist from /docs/forking (module name, deploy.yml service/image/volumes, brand.en.yml, PWA manifest, CI tags, devcontainer volume).

**Trigger to act:** second fork created (first fork = sonicpics validates the manual checklist; the script pays for itself at #2).
**Source:** fork-workflow design, docs/superpowers/specs/2026-06-12-fork-seams-and-forking-docs-design.md.
EOF
)"

gh issue create --title "Fork seam: extract CSP OAuth provider hosts to config" --body "$(cat <<'EOF'
config/initializers/content_security_policy.rb hardcodes accounts.google.com / github.com. A fork swapping OAuth providers must edit this template-owned initializer.

**Trigger to act:** first fork that swaps or adds OAuth providers. Until then YAGNI — the shipped defaults serve forks keeping Google+GitHub.
**Source:** fork-readiness entanglement survey, 2026-06-12.
EOF
)"

gh issue create --title "Fork seam: verify brand-color/theme customization path for forks" --body "$(cat <<'EOF'
OKLCH theming is partly runtime/DB-driven (user/workspace primary_color hue). Unverified: what a fork must touch to change DEFAULT brand colors (compile-time tokens in app/assets/tailwind vs runtime config), and whether that's a fork-owned seam or a template edit.

**Trigger to act:** sonicpics' branding pass — it will reveal exactly what's missing. Do the verification then; don't pre-build a theme.css seam on guesses.
**Source:** fork-readiness entanglement survey, 2026-06-12 (survey agent's compile-time claims were NOT verified).
EOF
)"
```

---

## Self-review notes (already applied)

- Spec's "update `index_coverage_spec`" requirement dropped: verified unnecessary (it reads the booted, post-merge `Markdowndocs.configuration.categories`). The spec doc's assumption is superseded by Task 4's design.
- Spec's "layout meta description" call-site edit dropped: verified the layout already uses `t("application.description")`.
- Added (not in spec, found during planning): brand-agnostic devcontainer-volume regex (Task 3 Step 4) — the only spec asserting a brand literal.
- All invariant assertions are presence-based, never `eq("ModelRails")`, so a renamed fork passes them unmodified.
