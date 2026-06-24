# GitHub Codespaces (Browser-Hosted Dev Container) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `modelrails_base` run in a browser-hosted GitHub Codespace — the app boots, magic-link sign-in works, and the test suite runs in-container — using the same `.devcontainer/` config as a local Dev Container.

**Architecture:** A Codespace runs the existing dev container on a cloud VM and reaches the app through a forwarded HTTPS proxy at `https://<codespace-name>-<port>.app.github.dev` instead of `localhost`. A small pure `Codespaces` module (`lib/codespaces.rb`) detects the Codespace and computes the forwarded host; `config/environments/development.rb` uses it to (a) allow the forwarded domain past Rails host authorization and (b) point magic-link mailer URLs at the forwarded domain. The container spec drops one redundant local-only mount; `setup.sh` and a new developer doc cover the browser workflow.

**Tech Stack:** Ruby 4.0.4 / Rails 8.1, RSpec, dev-container `devcontainer.json` spec, bash, markdowndocs (docs engine).

## Global Constraints

- **Runtimes:** Ruby `4.0.4`, Node `24.4.1`, pinned by `.tool-versions`. Run every Ruby/Node command through the toolchain manager: prefix with `mise exec --` (e.g. `mise exec -- bundle exec rspec …`).
- **Ruby style:** every `.rb` file starts with `# frozen_string_literal: true`; 2-space indentation; `snake_case` methods, `PascalCase` constants. RuboCop runs on `git commit` (Lefthook pre-commit) — code must be autocorrect-clean.
- **Strict TDD:** write the failing test first, watch it fail, then implement. This applies to the one unit-testable component (the `Codespaces` module).
- **Commits:** Conventional Commits format. **Never add a `Co-Authored-By:` trailer or any AI-authorship line.**
- **Never bypass Lefthook:** no `--no-verify`, no `LEFTHOOK=0`. Fix the issue instead.
- **Docs registration:** every file under `app/docs/` MUST appear in exactly one category in `config/initializers/markdowndocs.rb`, or `spec/docs/index_coverage_spec.rb` fails CI.
- **I18n:** not applicable here — this plan introduces no user-facing Rails view/flash text (markdown doc content and shell `echo` output are not I18n'd).
- **Green before push:** the full local suite (`bin/ci`) must pass with zero failures before pushing / opening a PR. The Lefthook pre-push hook also runs CI.
- **Branch:** all work lands on the already-created `codespaces-devcontainer` branch.

---

### Task 1: `Codespaces` detection module

The single unit-testable piece: pure functions over an env hash that answer "are we in a Codespace?" and "what host reaches app port N?". Lives in `lib/` and is `require`d (not autoloaded) by `development.rb`, mirroring the existing `lib/markdowndocs_local_categories.rb` + `config/initializers/markdowndocs.rb` precedent.

**Files:**
- Create: `lib/codespaces.rb`
- Test: `spec/lib/codespaces_spec.rb`

**Interfaces:**
- Produces:
  - `Codespaces.active?(env = ENV) -> Boolean` — true only when `env["CODESPACES"] == "true"`.
  - `Codespaces.forwarding_domain(env = ENV) -> String | nil` — value of `env["GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"]`.
  - `Codespaces.forwarded_host(port:, env: ENV) -> String` — `"#{env["CODESPACE_NAME"]}-#{port}.#{forwarding_domain(env)}"` (no scheme, no trailing slash).

- [ ] **Step 1: Write the failing test**

Create `spec/lib/codespaces_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require "codespaces"

RSpec.describe Codespaces do
  describe ".active?" do
    it "is true only when CODESPACES is exactly \"true\"" do
      expect(described_class.active?({ "CODESPACES" => "true" })).to be(true)
    end

    it "is false when CODESPACES is absent" do
      expect(described_class.active?({})).to be(false)
    end

    it "is false when CODESPACES holds any other value" do
      expect(described_class.active?({ "CODESPACES" => "false" })).to be(false)
      expect(described_class.active?({ "CODESPACES" => "1" })).to be(false)
    end
  end

  describe ".forwarding_domain" do
    it "returns the injected port-forwarding domain" do
      env = { "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev" }
      expect(described_class.forwarding_domain(env)).to eq("app.github.dev")
    end

    it "returns nil when the domain is unset" do
      expect(described_class.forwarding_domain({})).to be_nil
    end
  end

  describe ".forwarded_host" do
    it "builds <name>-<port>.<domain> with no scheme or trailing slash" do
      env = {
        "CODESPACE_NAME" => "musical-space-abc123",
        "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev"
      }
      expect(described_class.forwarded_host(port: 3000, env: env))
        .to eq("musical-space-abc123-3000.app.github.dev")
    end

    it "reflects the port argument" do
      env = {
        "CODESPACE_NAME" => "cs",
        "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev"
      }
      expect(described_class.forwarded_host(port: 1080, env: env))
        .to eq("cs-1080.app.github.dev")
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mise exec -- bundle exec rspec spec/lib/codespaces_spec.rb`
Expected: FAIL — `cannot load such file -- codespaces` (the lib file does not exist yet).

- [ ] **Step 3: Write the minimal implementation**

Create `lib/codespaces.rb`:

```ruby
# frozen_string_literal: true

# GitHub Codespaces detection + forwarded-URL helpers. A browser Codespace
# reaches the app through an HTTPS proxy at
# <codespace-name>-<port>.<forwarding-domain> (not localhost), which dev config
# must allow past host authorization and target with mailer links. Pure
# functions over an env hash so they unit-test without a real Codespace.
# Required explicitly by config/environments/development.rb — environment config
# runs before Zeitwerk autoloading, same as lib/markdowndocs_local_categories.rb.
module Codespaces
  # The platform sets CODESPACES=true only inside a Codespace.
  def self.active?(env = ENV)
    env["CODESPACES"] == "true"
  end

  # The port-forwarding domain the platform injects, e.g. "app.github.dev".
  def self.forwarding_domain(env = ENV)
    env["GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"]
  end

  # The forwarded host for a given app port, e.g.
  # "musical-space-abc123-3000.app.github.dev" — no scheme, no trailing slash.
  def self.forwarded_host(port:, env: ENV)
    "#{env["CODESPACE_NAME"]}-#{port}.#{forwarding_domain(env)}"
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mise exec -- bundle exec rspec spec/lib/codespaces_spec.rb`
Expected: PASS — 7 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/codespaces.rb spec/lib/codespaces_spec.rb
git commit -m "feat(codespaces): add Codespaces env-detection helper module"
```

Expected: Lefthook pre-commit runs RuboCop on the two `.rb` files and passes; commit succeeds.

---

### Task 2: Wire Codespaces awareness into development config

Use the module in `development.rb` to clear the two `localhost`-only blockers: host authorization (the 403) and the magic-link mailer host. No-op outside a Codespace.

**Files:**
- Modify: `config/environments/development.rb` (add a `require_relative` near the top; add a conditional block immediately after the existing `config.action_mailer.default_url_options` line, currently line 47).

**Interfaces:**
- Consumes: `Codespaces.active?`, `Codespaces.forwarding_domain`, `Codespaces.forwarded_host(port:)` from Task 1.

- [ ] **Step 1: Add the explicit require near the top of `development.rb`**

In `config/environments/development.rb`, immediately after the first line `require "active_support/core_ext/integer/time"`, add:

```ruby
# Required explicitly (not autoloaded): environment config runs before Zeitwerk
# autoloading is active — same pattern as config/initializers/markdowndocs.rb.
require_relative "../../lib/codespaces"
```

- [ ] **Step 2: Add the Codespaces block after the mailer line**

The existing line reads:

```ruby
  config.action_mailer.default_url_options = { host: "localhost", port: ENV.fetch("PORT", 3000).to_i }
```

Immediately after it, insert:

```ruby

  # GitHub Codespaces: the browser reaches the app through a forwarded HTTPS
  # proxy at <codespace>-<port>.app.github.dev, not localhost. Allow that host
  # past DNS-rebinding protection and point mailer links (magic-link sign-in) at
  # the forwarded URL so they resolve in the browser. No-op outside Codespaces.
  if Codespaces.active?
    config.hosts << ".#{Codespaces.forwarding_domain}"

    config.action_mailer.default_url_options = {
      host: Codespaces.forwarded_host(port: ENV.fetch("PORT", 3000)),
      protocol: "https"
    }
  end
```

- [ ] **Step 3: Verify the block activates under simulated Codespaces env**

Run (simulates a Codespace without needing one):

```bash
CODESPACES=true \
CODESPACE_NAME=test-cs \
GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev \
RAILS_ENV=development \
mise exec -- bin/rails runner 'puts Rails.application.config.hosts.inspect; puts Rails.application.config.action_mailer.default_url_options.inspect'
```

Expected: the printed `hosts` array includes the string `".app.github.dev"`, and the mailer line prints `{:host=>"test-cs-3000.app.github.dev", :protocol=>"https"}`.

- [ ] **Step 4: Verify it is a no-op without the Codespaces env**

Run:

```bash
RAILS_ENV=development mise exec -- bin/rails runner 'puts Rails.application.config.action_mailer.default_url_options.inspect'
```

Expected: `{:host=>"localhost", :port=>3000}` — unchanged from the original behavior, and `".app.github.dev"` is NOT in `config.hosts`.

- [ ] **Step 5: Commit**

```bash
git add config/environments/development.rb
git commit -m "feat(codespaces): allow forwarded host + target mailer links in dev"
```

---

### Task 3: Drop the redundant `.ssh` mount from the dev container

The `${localEnv:HOME}/.ssh` bind mount does not exist on a Codespaces VM (Codespaces injects git auth via `gh`/`GITHUB_TOKEN`) and is redundant locally (VS Code auto-forwards the host SSH agent). Removing it makes one config serve both environments.

**Files:**
- Modify: `.devcontainer/devcontainer.json` (remove the `.ssh` entry from `mounts`).

- [ ] **Step 1: Remove the `.ssh` mount line**

The current `mounts` block reads:

```json
  "mounts": [
    "source=modelrails-bundle-cache,target=/usr/local/bundle,type=volume",
    "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
  ],
```

Replace it with (drop the second entry and the trailing comma on the first):

```json
  "mounts": [
    "source=modelrails-bundle-cache,target=/usr/local/bundle,type=volume"
  ],
```

Leave `remoteEnv` (`BINDING: 0.0.0.0`), `forwardPorts`, `portsAttributes`, `features`, and `customizations` untouched.

- [ ] **Step 2: Verify the file is still valid JSON**

Run: `mise exec -- ruby -rjson -e 'JSON.parse(File.read(".devcontainer/devcontainer.json")); puts "valid json"'`
Expected: `valid json` (no parse error).

- [ ] **Step 3: Confirm the `.ssh` mount is gone**

Run: `grep -c "\.ssh" .devcontainer/devcontainer.json`
Expected: `0`.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/devcontainer.json
git commit -m "chore(codespaces): drop redundant .ssh bind mount from devcontainer"
```

---

### Task 4: Make `setup.sh` Codespaces-friendly

Auto-create `.env` from the example (convenience — all vars default, `dotenv` only loads `.env` when present) and print Codespaces-correct next steps (Ports panel, forwarded URLs) when running inside a Codespace.

**Files:**
- Modify: `.devcontainer/setup.sh` (add `.env` bootstrap before `bin/setup`; branch the closing message on `CODESPACES`).

- [ ] **Step 1: Add the `.env` bootstrap before the `bin/setup` step**

In `.devcontainer/setup.sh`, immediately before the `echo "=== Running bin/setup ==="` line, insert:

```bash
echo "=== Bootstrapping .env ==="
# Convenience only: every var in .env.example has a working default and dotenv
# loads .env only when present, so this just gives the dev a ready file to edit.
if [ ! -f .env ]; then
  cp .env.example .env
  echo "(copied .env.example -> .env)"
else
  echo "(.env already exists — leaving it)"
fi

```

- [ ] **Step 2: Replace the closing next-steps message with a Codespaces-aware branch**

The current closing block reads:

```bash
cat <<'NEXT_STEPS'

=== Dev environment ready ===

Next steps:
  1. Copy .env.example to .env and fill in any secrets you need
  2. Run: bin/dev
  3. Visit: http://localhost:3000

For deployment with Kamal:
  1. Edit config/deploy.yml (server IP, registry, app name)
  2. Set KAMAL_REGISTRY_PASSWORD in .kamal/secrets
  3. Run: bin/kamal setup
NEXT_STEPS
```

Replace it entirely with:

```bash
if [ "${CODESPACES:-}" = "true" ]; then
  cat <<'NEXT_STEPS'

=== Dev environment ready (GitHub Codespaces) ===

Next steps:
  1. Run: bin/dev
  2. Open the app: click the port 3000 entry in the PORTS panel (or the
     auto-forward notification) — not http://localhost:3000.
  3. Sign in (passwordless): request a magic link, then open it from
     Letter Opener Web on the forwarded port 1080 URL (also in the PORTS panel).

.env was created from .env.example; edit it if you need to change any defaults.
NEXT_STEPS
else
  cat <<'NEXT_STEPS'

=== Dev environment ready ===

Next steps:
  1. Edit .env (copied from .env.example) if you need to change any defaults
  2. Run: bin/dev
  3. Visit: http://localhost:3000

For deployment with Kamal:
  1. Edit config/deploy.yml (server IP, registry, app name)
  2. Set KAMAL_REGISTRY_PASSWORD in .kamal/secrets
  3. Run: bin/kamal setup
NEXT_STEPS
fi
```

- [ ] **Step 3: Verify the script still parses**

Run: `bash -n .devcontainer/setup.sh && echo "syntax ok"`
Expected: `syntax ok` (no syntax errors).

- [ ] **Step 4: Verify both message branches render**

Run: `CODESPACES=true bash -c 'set -e; if [ "${CODESPACES:-}" = "true" ]; then echo CODESPACES_BRANCH; else echo LOCAL_BRANCH; fi'`
Expected: `CODESPACES_BRANCH`. Then run the same without the env: `bash -c 'if [ "${CODESPACES:-}" = "true" ]; then echo CODESPACES_BRANCH; else echo LOCAL_BRANCH; fi'`
Expected: `LOCAL_BRANCH`. (Confirms the branch guard; the full `setup.sh` is exercised end-to-end in Task 6's manual UAT.)

- [ ] **Step 5: Commit**

```bash
git add .devcontainer/setup.sh
git commit -m "chore(codespaces): bootstrap .env and print forwarded-URL next steps"
```

---

### Task 5: Developer doc + markdowndocs registration

Add a `/docs` page covering the Codespaces workflow, and register it so the docs index-coverage spec passes.

**Files:**
- Create: `app/docs/developer/codespaces.md`
- Modify: `config/initializers/markdowndocs.rb` (add `developer/codespaces` to the `"Getting Started"` category)
- Test (existing gate): `spec/docs/index_coverage_spec.rb`

- [ ] **Step 1: Write the doc**

Create `app/docs/developer/codespaces.md`:

```markdown
---
title: GitHub Codespaces
description: Run ModelRails in a browser-hosted Codespace — boot, magic-link sign-in, and the test suite
keywords: codespaces devcontainer browser cloud dev container github forwarded port host authorization magic link letter opener playwright
---

# GitHub Codespaces

ModelRails runs in a browser-hosted [GitHub Codespace](https://docs.github.com/en/codespaces) using the same `.devcontainer/` config as a local Dev Container. A Codespace runs that container on a cloud VM and reaches the app through a forwarded HTTPS proxy at `https://<codespace-name>-<port>.app.github.dev` instead of `localhost`.

## Quickstart

1. On the repo's GitHub page: **Code → Codespaces → Create codespace**. The first build runs `.devcontainer/setup.sh` (system packages, Playwright chromium, `bin/setup`) — a few minutes.
2. In the Codespace terminal: `bin/dev`.
3. Open the app: the **Ports** panel forwards port **3000** — click its URL (or the auto-forward notification). Do not use `http://localhost:3000`.
4. Sign in: ModelRails is passwordless. Request a magic link, then open it from **Letter Opener Web** on the forwarded port **1080** URL (also in the Ports panel). The link targets the forwarded domain, so it resolves in the browser.

## Why the Codespaces-specific config exists

Two `localhost`-only assumptions break when the origin becomes `*.app.github.dev`, so `config/environments/development.rb` adapts when `CODESPACES=true` (see `lib/codespaces.rb`):

- **Host authorization.** Rails' DNS-rebinding protection allows only `localhost`/IPs by default and returns `403 Blocked host` for the forwarded domain. The Codespaces block adds `.app.github.dev` to `config.hosts`.
- **Mailer link host.** Magic-link emails are built from `config.action_mailer.default_url_options`. In a Codespace that host is set to the forwarded URL (HTTPS, with the port baked into the subdomain) so sign-in links work from the browser.

The server already binds correctly: `.devcontainer/devcontainer.json` sets `BINDING=0.0.0.0`, which `rails server` needs to be reachable through the forward (its development default is `localhost`).

## Running the test suite

`bin/ci` and the Playwright/axe system specs run entirely in-container against `127.0.0.1`, so they need no Codespaces-specific configuration. The default 2-core Codespace runs the full suite but slowly — if you run `bin/ci` often, bump the machine type from the Codespaces UI (**Change machine type**).

## Out of scope

Passkeys (WebAuthn) over the Codespaces origin and Kamal/Docker builds from inside a Codespace are not configured here.
```

- [ ] **Step 2: Run the docs coverage spec to confirm it now fails (doc is unregistered)**

Run: `mise exec -- bundle exec rspec spec/docs/index_coverage_spec.rb`
Expected: FAIL — the spec reports `developer/codespaces` (or `app/docs/developer/codespaces.md`) as an orphaned/uncategorized doc.

- [ ] **Step 3: Register the doc in the markdowndocs category map**

In `config/initializers/markdowndocs.rb`, change the `"Getting Started"` line from:

```ruby
    "Getting Started"            => %w[user/welcome developer/getting-started],
```

to:

```ruby
    "Getting Started"            => %w[user/welcome developer/getting-started developer/codespaces],
```

- [ ] **Step 4: Run the docs specs to verify they pass**

Run: `mise exec -- bundle exec rspec spec/docs/`
Expected: PASS — 0 failures (coverage spec now sees `developer/codespaces` registered; the SVG/auth/deprecation/preset doc specs are unaffected).

- [ ] **Step 5: Commit**

```bash
git add app/docs/developer/codespaces.md config/initializers/markdowndocs.rb
git commit -m "docs(codespaces): add developer Codespaces guide and register it"
```

---

### Task 6: Full-suite verification + manual Codespaces UAT

Declarative container config (`devcontainer.json`, `setup.sh`) is not unit-testable; it is verified by launching a real Codespace. First confirm the whole suite is still green locally, then run the manual UAT.

**Files:** none (verification only).

- [ ] **Step 1: Run the full local suite**

Run: `mise exec -- bin/ci`
Expected: all stages pass with zero failures. If a system spec fails intermittently, re-run once to rule out a known flake before investigating (see project notes on flaky system specs); a reproducible failure must be fixed before proceeding.

- [ ] **Step 2: Push the branch and open the PR**

```bash
git push -u origin codespaces-devcontainer
```

Expected: the Lefthook pre-push hook runs CI locally and passes before the push completes. Then open a PR against `main` (e.g. `gh pr create`).

- [ ] **Step 3: Manual Codespaces UAT (run in a real Codespace from the PR branch)**

Create a Codespace on the `codespaces-devcontainer` branch (**Code → Codespaces → Create codespace on codespaces-devcontainer**) and verify, in order:

1. The container builds and `setup.sh` completes; the closing message shows the **Codespaces** next-steps variant and reports `.env` was created.
2. `bin/dev` starts; the **Ports** panel lists ports **3000** (Rails) and **1080** (Letter Opener).
3. Click the forwarded **3000** URL → the public home page loads with **no `403 Blocked host`**.
4. Request a magic-link sign-in; open the email in Letter Opener via the forwarded **1080** URL; confirm the magic link's host is the forwarded `…-3000.app.github.dev` domain; click it → sign-in completes in the browser.
5. (Optional, slow on 2-core) `bin/ci` passes inside the Codespace.

- [ ] **Step 4: Record UAT outcome on the PR**

Comment the UAT results (pass/fail per step, with the codespace machine size used) on the PR so the manual verification is captured alongside the automated suite.

---

## Self-Review

**Spec coverage** (each spec unit → task):

- Unit A (`Codespaces` module) → Task 1.
- Unit B (development.rb host + mailer block) → Task 2.
- Unit C (`devcontainer.json`, remove `.ssh` mount; no `hostRequirements`) → Task 3. (Spec's revised decision = *no* `hostRequirements`; Task 3 adds none. ✓)
- Unit D (`setup.sh` `.env` bootstrap + Codespaces next-steps) → Task 4.
- Unit E (`codespaces.md`) → Task 5, plus the markdowndocs registration the spec implies via the "every doc must be categorized" rule.
- Testing (unit spec + manual UAT) → Task 1 (spec) and Task 6 (full suite + UAT).
- Server-binding "already handled, keep `BINDING`" → preserved by Task 3 leaving `remoteEnv` untouched; documented in Task 5's doc.

**Placeholder scan:** no `TBD`/`TODO`/"add error handling"/"similar to Task N" — every step has concrete code or an exact command with expected output.

**Type/name consistency:** `Codespaces.active?`, `.forwarding_domain`, `.forwarded_host(port:)` are defined identically in Task 1's interface, Task 1's implementation, and consumed verbatim in Task 2. The doc slug `developer/codespaces` matches the file path `app/docs/developer/codespaces.md` and the category-map entry in Task 5.
