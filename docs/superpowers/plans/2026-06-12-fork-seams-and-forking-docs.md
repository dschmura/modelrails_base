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
- In-app docs need YAML frontmatter (`title`, `description`, `keywords`, `audience: [guide, technical]`) and a category entry in `config/initializers/markdowndocs.rb`, or `index_coverage_spec` fails (one of Task 6's red steps).
- A custom `merge=ours` driver fires ONLY during a content-level three-way merge — i.e., when BOTH sides changed the file since the merge base. If only upstream changed a fork-owned file, the merge takes upstream's version silently (no conflict, driver never runs). If the fork customized it, the driver keeps the fork's version silently — **including over upstream security fixes**. The guide documents both behaviors and a sync-time check (panel finding, Scott Chacon seat).
- The driver activates via `git config merge.ours.driver true` per clone. `bin/setup` is the activation point, gated on `git remote get-url upstream` succeeding — the template repo itself must NOT set the driver (it would mis-resolve the template's own PR merges that touch fork-owned paths).
- Initializers cannot reference autoloaded (`app/lib`) constants under Zeitwerk; the Task 4 loader therefore lives in `lib/` and is `require`d explicitly by the initializer.
- `db/seeds.rb` is `default_roles` + the tenancy-preset bootstrap (template-owned); fork additions go below an explicit end-of-template marker added in Task 3.

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
| `bin/setup` | Modify | Activate merge driver when an `upstream` remote exists |
| `db/seeds.rb` | Modify | End-of-template marker for fork seed additions |
| `lib/markdowndocs_local_categories.rb` | Create | Overlay merge unit (required by the initializer) |
| `config/initializers/markdowndocs.rb` | Modify | Categories assigned through the overlay loader |
| `spec/lib/markdowndocs_local_categories_spec.rb` | Create | Unit spec for the overlay merge (Tempfile fixtures) |
| `spec/code_smells/template_invariants_spec.rb` | Modify | New "Fork seams" describe + brand-agnostic volume regex |
| `CHANGELOG.md` | Modify | One-line entry under [Unreleased] |

**PR B (`docs/forking-guide`):**

| File | Action | Responsibility |
| --- | --- | --- |
| `app/docs/forking.md` | Create | The full forking guide (rendered at `/docs/forking`) |
| `config/initializers/markdowndocs.rb` | Modify | Register `forking` under Guides |
| `spec/code_smells/template_invariants_spec.rb` | Modify | Contract-sync invariant (merge=ours paths ↔ guide) |
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

    it "activates the fork merge driver from bin/setup, gated on the upstream remote" do
      setup_script = File.read(Rails.root.join("bin/setup"))
      expect(setup_script).to include("merge.ours.driver"),
        "bin/setup must activate the merge=ours driver for forks"
      expect(setup_script).to include("git remote get-url upstream"),
        "driver activation must be gated on an upstream remote existing — " \
        "the template repo itself must never set the driver"
    end

    it "marks the fork extension point in db/seeds.rb" do
      expect(File.read(Rails.root.join("db/seeds.rb")))
        .to include("Fork seam: add your app's domain seeds BELOW this line")
    end
```

- [ ] **Step 2: Run, verify red**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 3 failures (no merge=ours entries, no bin/setup driver block, no seeds marker).

- [ ] **Step 3: Append the entries to `.gitattributes`**

Append to the existing `.gitattributes` (after the credentials lines):

```text

# Fork-owned paths — downstream forks rewrite these wholesale; upstream
# freezes them. With the driver active in a fork (bin/setup runs
# `git config merge.ours.driver true` when an upstream remote exists),
# a sync where BOTH sides changed one of these files resolves to the
# fork's version. Files the fork never touched still take upstream's
# changes — the driver only runs on two-sided changes. See /docs/forking.
# Inert in this repo (driver deliberately unset upstream).
app/views/pages/** merge=ours
app/controllers/pages_controller.rb merge=ours
config/locales/en/pages.en.yml merge=ours
config/locales/en/brand.en.yml merge=ours
config/routes/app.rb merge=ours
config/markdowndocs_categories.local.yml merge=ours
README.md merge=ours
```

`db/seeds.rb` is deliberately **not** listed — its preset section is template-owned; forks extend below a marker (added in Step 5).

- [ ] **Step 4: Activate the driver from bin/setup (forks only)**

In `bin/setup`, after the `puts "== Installing dependencies =="` / `system("bundle check") || system!("bundle install")` lines, insert:

```ruby
  # Fork seam: downstream forks have an `upstream` remote (see /docs/forking).
  # Activate the merge=ours driver for fork-owned paths there. Deliberately
  # NOT set in the template repo itself — it would silently mis-resolve the
  # template's own PR merges that touch fork-owned paths.
  if system("git remote get-url upstream", out: File::NULL, err: File::NULL)
    system! "git config merge.ours.driver true"
    puts "\n== Fork detected (upstream remote) — merge=ours driver activated =="
  end
```

The `system(..., out: File::NULL, err: File::NULL)` form returns true/false without printing; this repo has no `upstream` remote, so running `bin/setup` here must NOT set the driver (verify with `git config merge.ours.driver` → empty output).

- [ ] **Step 5: Add the fork extension marker to db/seeds.rb**

Append to the end of `db/seeds.rb`:

```ruby

# === Template seeds end here =================================================
# Fork seam: add your app's domain seeds BELOW this line. Upstream owns
# everything above it; keeping your additions below the marker keeps
# `git merge upstream/main` conflicts away. See /docs/forking.
```

- [ ] **Step 6: Make the devcontainer volume assertion brand-agnostic**

In `spec/code_smells/template_invariants_spec.rb` around line 228 (inside `it "mounts a named volume for the bundle cache (survives container rebuilds)"`), change:

```ruby
      expect(mounts).to include(match(/modelrails-bundle-cache/)),
```

to:

```ruby
      expect(mounts).to include(match(/bundle-cache/)),
```

(If the failure-message string on the following line also names `modelrails-bundle-cache`, generalize it to `bundle-cache` too.) This lets a renamed fork rename the devcontainer volume without touching template-owned specs.

- [ ] **Step 7: Run, verify green**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb`
Expected: all examples in the file pass (the whole file, not just the new describe — Step 6 touched an existing example). Also verify the driver gate: `git config merge.ours.driver` prints nothing in this repo.

- [ ] **Step 8: Commit**

```bash
git add spec/code_smells/template_invariants_spec.rb .gitattributes bin/setup db/seeds.rb
git commit -m "feat(fork-seams): merge=ours contract, bin/setup driver activation, seeds fork marker"
```

### Task 4: Markdowndocs local-categories overlay

**Files:**

- Create: `lib/markdowndocs_local_categories.rb`
- Create: `spec/lib/markdowndocs_local_categories_spec.rb`
- Modify: `config/initializers/markdowndocs.rb`

Panel amendment (Joël Quenneville): the merge logic is an extracted, explicitly-required unit — NOT inline initializer code tested via stub+reload. Initializers can't reference autoloaded `app/lib` constants under Zeitwerk, so the loader lives in `lib/` and the initializer `require`s it.

- [ ] **Step 1: Write the failing unit spec**

Create `spec/lib/markdowndocs_local_categories_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MarkdowndocsLocalCategories do
  let(:template) { { "Guides" => %w[extending], "Features" => %w[accounts] } }

  def with_local_file(content)
    Tempfile.create(["categories", ".yml"]) do |f|
      f.write(content)
      f.flush
      yield Pathname.new(f.path)
    end
  end

  it "returns the template map untouched when no local file exists (this repo)" do
    missing = Rails.root.join("config/markdowndocs_categories.local.yml")
    expect(File.exist?(missing)).to be(false)
    expect(described_class.merge(template, missing)).to eq(template)
  end

  it "adds new fork categories alongside template ones" do
    with_local_file("My Product:\n  - my-feature\n") do |path|
      result = described_class.merge(template, path)
      expect(result["My Product"]).to eq(%w[my-feature])
      expect(result["Guides"]).to eq(%w[extending])
    end
  end

  it "appends fork slugs when the fork extends an existing template category" do
    with_local_file("Guides:\n  - my-guide\n") do |path|
      expect(described_class.merge(template, path)["Guides"]).to eq(%w[extending my-guide])
    end
  end

  it "treats an empty local file as no categories" do
    with_local_file("") do |path|
      expect(described_class.merge(template, path)).to eq(template)
    end
  end
end
```

- [ ] **Step 2: Run, verify red**

Run: `bundle exec rspec spec/lib/markdowndocs_local_categories_spec.rb`
Expected: load error — `uninitialized constant MarkdowndocsLocalCategories`.

- [ ] **Step 3: Write the loader**

Create `lib/markdowndocs_local_categories.rb`:

```ruby
# Fork seam: merges the optional fork-owned categories file
# (config/markdowndocs_categories.local.yml — absent upstream) into the
# template's /docs category map, so a downstream fork registers its own docs
# pages without editing template-owned files. Same-named categories append.
# Required explicitly by config/initializers/markdowndocs.rb (initializers
# cannot reference autoloaded constants under Zeitwerk). See /docs/forking.
module MarkdowndocsLocalCategories
  def self.merge(template_categories, local_path)
    return template_categories unless File.exist?(local_path)

    local_categories = YAML.load_file(local_path) || {}
    template_categories.merge(local_categories) do |_category, template_slugs, fork_slugs|
      template_slugs + fork_slugs
    end
  end
end
```

The merge block matters: without it, a fork extending `"Guides"` would *replace* the template's slugs, orphaning template docs and tripping `index_coverage_spec`'s stale-slug guard.

- [ ] **Step 4: Run, verify green**

Run: `bundle exec rspec spec/lib/markdowndocs_local_categories_spec.rb`
Expected: 4 examples, 0 failures.

- [ ] **Step 5: Wire the initializer through the loader**

In `config/initializers/markdowndocs.rb`, add at the very top (after `# frozen_string_literal: true`):

```ruby
require_relative "../../lib/markdowndocs_local_categories"
```

Then change the categories assignment: rename the `config.categories = {` … `}` hash (lines 16–29) to a local `template_categories = {` … `}` (keep the existing comments and hash contents verbatim) and assign through the loader:

```ruby
  # Fork seam: a downstream fork registers its own docs pages in
  # config/markdowndocs_categories.local.yml (absent upstream) instead of
  # editing this initializer. Same-named categories append. See /docs/forking.
  config.categories = MarkdowndocsLocalCategories.merge(
    template_categories,
    Rails.root.join("config/markdowndocs_categories.local.yml")
  )
```

- [ ] **Step 6: Run, verify nothing regressed**

Run: `bundle exec rspec spec/docs/ spec/lib/markdowndocs_local_categories_spec.rb`
Expected: 0 failures (`index_coverage_spec` needs no changes — it reads the booted, post-merge configuration; with no local file upstream, the booted map is identical to before).

- [ ] **Step 7: Commit**

```bash
git add lib/markdowndocs_local_categories.rb spec/lib/markdowndocs_local_categories_spec.rb config/initializers/markdowndocs.rb
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
- **Fork-owned contract** — `.gitattributes` marks pages views/controller, marketing + brand locales, `routes/app.rb`, the local categories file, and README `merge=ours`. The driver resolves two-sided changes in the fork's favor; `bin/setup` activates it only when an `upstream` remote exists (so the template repo itself never sets it). `db/seeds.rb` gets an explicit end-of-template marker. Devcontainer volume invariant made brand-agnostic (`/bundle-cache/`).
- **Docs categories overlay** — `lib/markdowndocs_local_categories.rb` merges the optional `config/markdowndocs_categories.local.yml` (absent upstream) into the category map; same-named categories append. Unit-tested with Tempfile fixtures; `index_coverage_spec` unchanged — it reads the booted config.

Shaped by a five-seat template-practitioner panel review (Jumpstart Pro / Bullet Train / thoughtbot / git-mechanics personas) — see the design doc's amendments section.

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
- Modify: `spec/code_smells/template_invariants_spec.rb` (contract↔docs sync invariant)

- [ ] **Step 1: Branch off PR A's branch**

```bash
git checkout -b docs/forking-guide   # from feat/fork-seams — the guide documents those seams
```

(If PR A has already merged, branch from updated `main` instead.)

- [ ] **Step 2: Write the failing contract-sync invariant**

Panel amendment (Joël Quenneville): the fork-owned list must not drift between `.gitattributes` and the guide. Append inside the `describe "Fork seams …"` block in `spec/code_smells/template_invariants_spec.rb`:

```ruby
    it "documents every merge=ours path in the forking guide (no silent contract drift)" do
      gitattributes = File.read(Rails.root.join(".gitattributes"))
      guide = File.read(Rails.root.join("app/docs/forking.md"))
      gitattributes.scan(/^(\S+) merge=ours$/).flatten.each do |path|
        expect(guide).to include(path),
          "#{path} is marked merge=ours in .gitattributes but not mentioned in app/docs/forking.md"
      end
    end
```

- [ ] **Step 3: Run, verify red**

Run: `bundle exec rspec spec/code_smells/template_invariants_spec.rb -e "Fork seams"`
Expected: 1 failure — `Errno::ENOENT` (no `app/docs/forking.md` yet).

- [ ] **Step 4: Create the doc**

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
   `.gitattributes`, so when both you and upstream changed one, the sync keeps
   your version (details in [Fork-owned files](#fork-owned-files)).

**Is this model right for you?** If you just want a starting point and never
plan to pull template improvements, skip the machinery: clone, delete the
`upstream` remote, and own everything (the thoughtbot Suspenders model). This
guide earns its keep when you want upstream fixes and features flowing into
your app for years.

Two pieces of shared machinery already update the easy way — the design system
(`modelrails_ui`) and the docs engine (`markdowndocs`) are gems, so improvements
to them arrive via `bundle update`, no merge involved. The merge workflow covers
everything else: the application code around the gems.

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

# Activate the fork-owned merge driver (bin/setup also does this for you,
# but doing it now means your very first merge is already covered)
git config merge.ours.driver true
```

Two things you'll notice afterwards, both intentional:

- `git remote -v` shows upstream's push URL as `DISABLED`. That string is not a
  real URL — it makes any accidental `git push upstream` fail loudly instead of
  writing to the template.
- Your `main` tracks `origin/main` (your repo), so plain `git pull` stays inside
  your app. Upstream only enters when you explicitly run `git merge upstream/main`.

Finally, record the cut point in the template repo — it answers "which template
version is myapp based on?" forever:

```bash
# in your modelrails_base checkout
git tag forks/myapp-baseline main && git push origin forks/myapp-baseline
```

> **Why not GitHub's "Use this template" button, or a GitHub fork?** "Use this
> template" squashes the entire history into one unrelated commit — every later
> `git merge upstream/main` would need `--allow-unrelated-histories` and conflict
> on everything both sides touched. And GitHub will not fork a repository into
> the account that already owns it. Clone + re-pointed remotes gives you a
> private repo **and** mergeable history.

**Every teammate** who clones your new repository needs the upstream remote once
(`bin/setup` then activates the merge driver automatically — it detects the
remote):

```bash
git remote add upstream git@github.com:dschmura/modelrails_base.git
bin/setup
```

To verify the driver on any clone: `git config merge.ours.driver` should print
`true`. If it prints nothing, fork-owned files will conflict like ordinary files
on your next sync.

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

### How the merge driver actually behaves

The `merge=ours` driver is a conflict *resolver*, not a wall. During a sync:

- **You customized the file, upstream changed it too** → the driver keeps
  **your** version, silently — no conflict shown. This is the common case: you
  rewrite all of these paths early, that's why they're on the list.
- **You never touched the file, upstream changed it** → upstream's version
  flows in normally. The driver only runs when *both* sides changed a file.

Two consequences worth understanding:

**You can silently miss upstream fixes.** If upstream patches a bug in a file
you've customized (say `pages_controller.rb`), your next sync keeps your version
and the fix never arrives — with no warning. The update recipe below includes a
one-command check for exactly this.

**The driver must be active.** `bin/setup` activates it on any clone that has an
`upstream` remote. Without it, these paths conflict like ordinary files — verify
with `git config merge.ours.driver` → `true`.

`db/seeds.rb` is shared ground rather than fork-owned: everything above the
"Fork seam" marker at the bottom is template-owned; add your domain seeds below
the marker.

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

### 1. Look before you merge

```bash
git fetch upstream
git log --oneline main..upstream/main   # what's coming
```

Read `CHANGELOG.md` on `upstream/main` first — breaking changes and migrations
are called out under [Unreleased]. If a change sounds structural (schema,
`deploy.yml`), read its PR before merging, not after.

Then check whether upstream touched files **you own** — those changes will NOT
arrive through the merge (the driver keeps yours):

```bash
git log --oneline main..upstream/main -- \
  app/views/pages app/controllers/pages_controller.rb \
  config/locales/en/pages.en.yml config/locales/en/brand.en.yml \
  config/routes/app.rb README.md
```

If a commit there looks like a fix you want, cherry-pick it after the merge:
`git cherry-pick <sha>`, then adapt it to your version of the file.

### 2. Merge on a branch

```bash
git checkout -b chore/upstream-sync-$(date +%F)
git merge upstream/main
```

### 3. If you hit conflicts

| Conflict in | Resolution |
| ----------- | ---------- |
| Fork-owned paths | Shouldn't happen — the driver keeps yours. If it does, the driver isn't active: `git merge --abort`, run `git config merge.ours.driver true`, merge again |
| Identity values (`config/deploy.yml` service/image/volumes, `config/application.rb` module) | Keep your names; take any structural changes around them |
| `Gemfile` | Keep **both** sides' gems, then regenerate the lockfile |
| `Gemfile.lock`, `package-lock.json` | Never hand-merge: `git checkout --theirs <file>`, then `bundle install` / `npm install`, commit the regenerated result |
| Behavior (app code, specs, config) | Take theirs — unless you deliberately diverged, in which case consider sending your version upstream instead |
| Two migrations, same timestamp | Keep both; rename yours to a later timestamp with `git mv`, then re-run `bin/rails db:migrate` |
| Upstream renamed/moved a file you'd edited | Re-apply your edit at the new location, delete the old file. If the same resolution recurs every sync, turn on `git config rerere.enabled true` so git replays it for you |

A conflict looks like this — your side on top, upstream's below:

```text
<<<<<<< HEAD
    primary_cta: "Start organizing your photos"
=======
    primary_cta: "Get started free"
>>>>>>> upstream/main
```

Decide which line the file should have (here it's your marketing copy — keep
yours), delete the other line and all three marker lines, then `git add` the
file. That's the whole skill; the doctrine table tells you which side to favor.

### 4. Prove the merge

```bash
bin/rails db:migrate    # upstream may ship migrations
bundle exec rspec       # full suite green before the PR
```

Open a pull request into your app's main branch like any other change.

### If something looks wrong after the merge

- **A fork-owned file changed unexpectedly** — the driver wasn't active during
  the merge. Restore your version from before the sync:
  `git restore --source=main <path>`, commit, then fix the driver config.
- **Bundler errors** — regenerate instead of debugging the lockfile:
  `git checkout --theirs Gemfile.lock && bundle install`.
- **Tests fail** — run the failing spec alone, then
  `git diff upstream/main -- <file>` on the code it covers to see whether your
  divergence or the upstream change broke it.

### Cadence

Merge after each meaningful upstream change — don't bank up months of drift.
Small frequent merges conflict less than one big annual one; if upstream is
busy, a fixed weekly sync keeps every merge boring.

## Contribute a fix back

Make template-worthy fixes in a checkout of `modelrails_base` itself (branch →
PR), not in your app — `upstream` is push-disabled by design. If the fix already
exists as a commit in your app:

```bash
cd ../modelrails_base
git checkout -b fix/thing main
git remote add myapp git@github.com:YOU/myapp.git   # or ../myapp for a local checkout
git fetch myapp
git cherry-pick <sha>
```

Three guardrails before you open the PR:

- **Only template-owned files.** If the commit also touches fork-owned paths
  (your README, pages, brand strings), it would pollute the template — split the
  commit, or port the change by hand instead of cherry-picking.
- **Regular commits only, never merge commits** — cherry-picking a merge commit
  needs `-m` and rarely does what you meant.
- **Strip anything product-specific** (names, copy, config values) so the change
  reads as a template improvement.

## Stay mergeable

- **Prefer new files to edited template files** — new files merge clean by
  definition. New models, controllers, components, initializers, docs pages: all
  conflict-free.
- **Brand strings only in `brand.en.yml`** — if you find one hardcoded anywhere
  else, that's an upstream bug; report or fix it upstream.
- **Product routes only in `config/routes/app.rb`** — leave `config/routes.rb`
  to the template.
- **Gemfile: add, don't pin.** Append your gems with loose constraints
  (`"~> 1.0"`); pinning exact versions or git branches conflicts with upstream's
  dependency bumps every sync.
- **Treat `UI::*` primitives as upstream-owned** — extend by composing new
  components rather than editing the primitives; the planned design-system
  update engine will regenerate them.
- **Layouts and shared partials are template-owned but not frozen.** Adding a
  nav link to the header partial is fine — insert lines, don't restructure, so a
  future conflict has one obvious resolution.
- **When you must edit any template file** (an initializer, `application.rb`),
  make the edit additive — append rather than rewrite.
````

- [ ] **Step 5: Run, verify the second red**

Run: `bundle exec rspec spec/docs/index_coverage_spec.rb`
Expected: 1 failure — `forking` is an uncategorized orphan. (This is the natural failing test for doc registration.)

- [ ] **Step 6: Register the slug**

In `config/initializers/markdowndocs.rb`, change the Guides line inside `template_categories`:

```ruby
    "Guides" => %w[extending security ui-patterns components accessibility deployment background-jobs troubleshooting forking]
```

- [ ] **Step 7: Run, verify green + render check**

Run: `bundle exec rspec spec/docs/ spec/code_smells/template_invariants_spec.rb`
Expected: 0 failures (index coverage, contract-sync invariant, and the rest of the invariants file).

Run: `bin/dev` (or existing server), visit `http://localhost:3000/docs/forking` — page renders with title, tables, and code blocks intact; it appears under Guides on `/docs`. (Render truth is browser-only — do this, don't skip it.)

- [ ] **Step 8: Commit**

```bash
git add app/docs/forking.md config/initializers/markdowndocs.rb spec/code_smells/template_invariants_spec.rb
git commit -m "docs: in-app forking guide at /docs/forking + contract-sync invariant"
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
- Added (not in spec, found during planning): brand-agnostic devcontainer-volume regex (Task 3 Step 6) — the only spec asserting a brand literal.
- All invariant assertions are presence-based, never `eq("ModelRails")`, so a renamed fork passes them unmodified.

## Panel amendments (2026-06-12, applied)

Five-seat template-practitioner review (Chris Oliver, Colin Jilbert, Andrew
Culver, Joël Quenneville, Scott Chacon personas). Consensus: architecture sound;
the following precision fixes are folded into the tasks above:

1. **merge=ours semantics corrected** (Scott + Colin): driver fires only on
   two-sided changes; guide now documents both behaviors, the silent-discard
   hazard for customized files, and a pre-merge check + cherry-pick escape hatch
   (Task 6 guide §"How the merge driver actually behaves" and §"Look before you merge").
2. **Task 4 redesigned** (Joël): extracted `lib/markdowndocs_local_categories.rb`
   unit + Tempfile spec; no initializer reload, no global File/YAML stubs.
3. **Driver activation in bin/setup** (Scott/Culver/Colin), gated on
   `git remote get-url upstream` — the template repo must never set the driver
   (it would mis-resolve its own PR merges). Task 3 Step 4 + invariant.
4. **db/seeds.rb fork marker** (Colin): explicit end-of-template comment,
   invariant-backed (Task 3 Step 5).
5. **Contract-sync invariant** (Joël): every merge=ours path must be named in
   forking.md (Task 6 Step 2).
6. **Guide additions** (Chris/Colin/Culver/Scott/Joël): pre-merge CHANGELOG +
   fork-owned-paths check, worked conflict example, doctrine rows for Gemfile /
   migration timestamps / upstream renames + rerere, post-merge troubleshooting,
   contribute-back guardrails, DISABLED push-URL and branch-tracking notes,
   baseline tag, teammate setup via bin/setup, "is this model right for you"
   (Suspenders) paragraph, gem-trajectory paragraph, Gemfile add-don't-pin and
   layout-partials bullets.
7. **Baseline tagging** (Chris): one-line `git tag forks/<app>-baseline` step in
   the guide's "Start a new app".
