# Devcontainer + Dockerfile Cleanup — Design Spec

**Goal:** Address consensus findings from the 8-reviewer panel review of the dev environment. Adopt **Option C** (shared base image `ruby:slim` for devcontainer; keep dev/prod files separate) to gain runtime parity without sacrificing the native-Mac-dev workflow or devcontainer-features ergonomics. Make `.tool-versions` the single source of truth for Ruby version across dev, prod, and CI. Bump Ruby from `4.0.2` to `4.0.4`.

**Scope:** Ten coupled changes touching `.devcontainer/devcontainer.json`, `.devcontainer/setup.sh`, `Dockerfile`, `Gemfile` / `Gemfile.lock`, `config/application.rb`, `config/deploy.yml`, `.tool-versions`, plus a new `.env.example`. Mechanical refactor; no behavior changes to application code. Production topology concerns (Solid Queue in Puma, SQLite rolling-deploy guards, queue separation) are explicitly deferred to a follow-up phase.

**Review provenance:** Template panel (Eileen Uchitelle, Justin Searls, Michael Hartl, Chris Oliver) + Ops panel (Rosa Gutiérrez, Donal McBreen, Aaron Patterson, Nick Janetakis). Per-item authorship noted inline.

---

## Problem

The current dev environment has eight categories of friction surfaced by the panel review, plus one architectural choice (Ubuntu+mise vs. `ruby:slim`) that determines how forkers experience the template.

1. **Ruby version pinned in two unenforced locations** — `Dockerfile:11` (`ARG RUBY_VERSION=4.0.2`) and `.tool-versions:1` (`ruby 4.0.2`). `Gemfile` has no `ruby` directive, so `Gemfile.lock` has no `RUBY VERSION` block. A forker who bumps one file can ship a mismatch between dev and prod. The `Dockerfile:10` comment compounds the problem by referencing `.ruby-version` — a file that doesn't exist in this repo.

2. **Test gems ship to production.** `Dockerfile:27` sets `BUNDLE_WITHOUT="development"`. The `test` group (`rspec-rails`, `capybara`, `playwright-ruby-client`, etc.) is bundled into the production image. Every fork inherits a fatter, slightly less secure prod image.

3. **`Dockerfile` layer cache busts on any `vendor/` change.** Line 39 does `COPY vendor/* ./vendor/` *before* `COPY Gemfile Gemfile.lock` and `bundle install`. Any vendor tweak (including the markdowndocs symlink for Tailwind scanning per project memory) invalidates the bundle layer — 30–90s rebuild penalty per change. The empty-glob case also fails the build on some Docker versions.

4. **No dev/prod base-image parity.** Devcontainer uses `mcr.microsoft.com/devcontainers/base:ubuntu`; prod uses `ruby:4.0.2-slim` (Debian). Different distro, glibc, libvips, sqlite3, OpenSSL. "Works in dev, breaks in Kamal prod" bugs are one native-gem-compile away.

5. **`kamal deploy` cannot run from inside the devcontainer.** No Docker socket, no buildx, no SSH agent forwarding. Forkers attempting the canonical deploy workflow from their dev environment hit an opaque wall.

6. **`setup.sh` is a poor reimplementation of `bin/setup`.** Rails ships `bin/setup` as the canonical "I just cloned this, make it go" entry point. The current `.devcontainer/setup.sh` duplicates its logic in shell while skipping `bin/setup`'s asset-clobber and exec-`bin/dev` behavior. Two divergent setup paths for one project.

7. **Port forwarding is incomplete.** `devcontainer.json:10` forwards only `:3000`. No labels via `portsAttributes`. Forkers adding Letter Opener Web (`:1080`) or similar dev services find themselves debugging port routing.

8. **No onboarding signal post-setup.** `setup.sh` ends with `echo "=== Dev environment ready ==="` and tells the forker nothing about next commands, no `.env` template to copy, no Kamal-setup checklist.

9. **No `.env.example`.** Forkers learn what env vars exist by trial and error (or by reading `config/credentials.yml.enc` and Kamal docs).

10. **Free Rails 8.1 perf left unconfigured.** `config/application.rb` doesn't set `config.yjit = true`. `Dockerfile:28` wires `LD_PRELOAD` for jemalloc but doesn't set `MALLOC_CONF` — the community-tested default delivers tighter RSS on long Puma workers.

---

## Solution

### Decision: Option C (shared base image, separate files)

The devcontainer switches to `ruby:4.0.4-slim` as its base image (matching the production Dockerfile's base after the Ruby bump). The mise feature is dropped — Ruby is now baked into the image. `.devcontainer/setup.sh` and the production `Dockerfile` remain separate files with separate concerns, but they share a common base image.

This was selected after evaluating Nick Janetakis's full-unification recommendation (multi-stage Dockerfile with `dev` and `prod` targets) against 8 downstream scenarios. The base-image change captures Nick's primary win (runtime parity preventing libvips/glibc/SQLite divergence bugs) without forcing native Mac developers into Docker for daily dev work and without complicating service composition for forkers who later add Postgres or Redis.

`.tool-versions` remains the universal source of truth for Ruby version. The `Gemfile` adopts a `ruby file: ".tool-versions"` directive so Bundler enforces the runtime everywhere (dev, CI, and prod via `Gemfile.lock`'s `RUBY VERSION` block). The Dockerfile reads the same value via a build-arg flow.

### Ruby version bump: 4.0.2 → 4.0.4

`4.0.4` is the current latest stable Ruby. Lands as part of this work since we're reorganizing the version-pinning machinery anyway. Single concentrated change minimizes Bundler churn vs. two separate bumps.

---

## Architecture

### Modified files

#### `.tool-versions`

```diff
- ruby 4.0.2
+ ruby 4.0.4
  node 24.4.1
```

#### `Gemfile`

Add `ruby` directive at the top, reading from `.tool-versions` (Bundler 2.4+ supports this natively). This is the load-bearing change for single-source-of-truth.

```diff
  source "https://rubygems.org"

+ ruby file: ".tool-versions"
+
  # Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
  gem "rails", "~> 8.1.2", ">= 8.1.2.1"
```

After `bundle install`, `Gemfile.lock` gains a `RUBY VERSION` block (`ruby 4.0.4p0` or equivalent). From this point forward, any environment running `bundle install` against a different Ruby version errors at install time rather than failing silently at runtime.

#### `Dockerfile`

Five changes in one file:

```diff
  # syntax=docker/dockerfile:1
  # check=error=true

  # This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
  # docker build -t modelrails_base .
  # docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name modelrails_base modelrails_base

  # For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

- # Make sure RUBY_VERSION matches the Ruby version in .ruby-version
- ARG RUBY_VERSION=4.0.2
+ # Make sure RUBY_VERSION matches the Ruby version in .tool-versions.
+ # When invoked via Kamal, config/deploy.yml passes RUBY_VERSION as a build arg
+ # derived from .tool-versions (see deploy.yml:builder.args).
+ ARG RUBY_VERSION=4.0.4
  FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

  # Rails app lives here
  WORKDIR /rails

  # Install base packages
  RUN apt-get update -qq && \
      apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
      ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
      rm -rf /var/lib/apt/lists /var/cache/apt/archives

  # Set production environment variables and enable jemalloc for reduced memory usage and latency.
  ENV RAILS_ENV="production" \
      BUNDLE_DEPLOYMENT="1" \
      BUNDLE_PATH="/usr/local/bundle" \
-     BUNDLE_WITHOUT="development" \
-     LD_PRELOAD="/usr/local/lib/libjemalloc.so"
+     BUNDLE_WITHOUT="development:test" \
+     LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
+     MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:0"

  # Throw-away build stage to reduce size of final image
  FROM base AS build

  # Install packages needed to build gems
  RUN apt-get update -qq && \
      apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
      rm -rf /var/lib/apt/lists /var/cache/apt/archives

- # Install application gems
- COPY vendor/* ./vendor/
- COPY Gemfile Gemfile.lock ./
+ # Install application gems FIRST so the bundle layer cache survives vendor changes
+ COPY Gemfile Gemfile.lock ./

  RUN bundle install && \
      rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
      # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
      bundle exec bootsnap precompile -j 1 --gemfile

+ # Vendor contents (including symlinks like markdowndocs for Tailwind scanning) come
+ # AFTER gems so a vendor tweak doesn't invalidate the bundle install layer.
+ COPY vendor/ ./vendor/
+
  # Copy application code
  COPY . .
```

Five distinct fixes:

1. **Line 10 comment** updated from `.ruby-version` to `.tool-versions` (Aaron — stop propagating stale info)
2. **Line 11 `ARG`** bumped from `4.0.2` to `4.0.4` (Ruby bump)
3. **Line 27 `BUNDLE_WITHOUT`** changed to `"development:test"` (Eileen — stop shipping test gems to prod)
4. **Line 28 `MALLOC_CONF`** added (Aaron — community-tested jemalloc tuning for Puma)
5. **Lines 39–40** reordered + `COPY vendor/` moved after `bundle install`, switched from `vendor/*` glob to `vendor/` directory copy (Nick + Justin + Chris + Donal — fixes layer cache, fixes empty-glob build failure)

#### `.devcontainer/devcontainer.json`

Substantive rewrite — base image swap, feature changes, mount and port additions:

```jsonc
{
  "name": "ModelRails",
  "image": "docker.io/library/ruby:4.0.4-slim",
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {},
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
  },
  "mounts": [
    "source=modelrails-bundle-cache,target=/usr/local/bundle,type=volume",
    "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
  ],
  "remoteEnv": {
    "BINDING": "0.0.0.0"
  },
  "postCreateCommand": "bash .devcontainer/setup.sh",
  "forwardPorts": [3000, 1080],
  "portsAttributes": {
    "3000": {
      "label": "Rails",
      "onAutoForward": "notify"
    },
    "1080": {
      "label": "Letter Opener Web",
      "onAutoForward": "silent"
    }
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "Shopify.ruby-lsp",
        "bradlc.vscode-tailwindcss",
        "dbaeumer.vscode-eslint",
        "qwtel.sqlite-viewer"
      ],
      "settings": {
        "editor.tabSize": 2,
        "editor.formatOnSave": true
      }
    }
  }
}
```

Changes from current:

| Element | Change | Why |
|---|---|---|
| `image` | Ubuntu base → `ruby:4.0.4-slim` | Runtime parity with prod (Nick); Ruby baked in |
| `features.mise` | Removed | No longer needed; Ruby is in base image |
| `features.docker-outside-of-docker` | Added | Enables `kamal deploy` from inside devcontainer (Donal) |
| `mounts.bundle-cache` | Added | Survives container rebuilds; eliminates re-install penalty (Nick) |
| `mounts.ssh-bind` | Added | `kamal deploy` SSHes to target server (Donal) |
| `remoteEnv.BINDING` | Added | Ensures `bin/dev` binds outside the container (Justin) |
| `forwardPorts` | `[3000]` → `[3000, 1080]` | Letter Opener Web is a common addition forkers make (Chris) |
| `portsAttributes` | Added | Labels ports in VS Code's Ports panel (Chris/Nick) |
| `extensions.sqlite-viewer` | Added | Forkers will peek at `storage/development.sqlite3` (Justin) |

#### `.devcontainer/setup.sh`

Becomes a thin wrapper around `bin/setup` + devcontainer-specific extras (system packages, Playwright). Ends with explicit next-steps guidance.

```bash
#!/bin/bash
set -e

echo "=== Installing system packages ==="
# Mirror the system packages installed by the production Dockerfile so dev
# matches prod for libvips, sqlite3, jemalloc, libyaml, build tools.
sudo apt-get update -qq
sudo apt-get install --no-install-recommends -y \
  build-essential \
  curl \
  git \
  libjemalloc2 \
  libvips \
  libyaml-dev \
  pkg-config \
  sqlite3
sudo rm -rf /var/lib/apt/lists /var/cache/apt/archives

echo "=== Installing Playwright browsers ==="
# Idempotent: skips re-download if browsers are already cached in the
# named bundle volume.
if [ -z "$(command -v playwright)" ] || ! npx playwright --version > /dev/null 2>&1; then
  npx playwright install --with-deps chromium
else
  echo "(Playwright already installed — skipping)"
fi

echo "=== Running bin/setup ==="
# bin/setup handles bundle install + db:prepare + assets:clobber idempotently.
# --skip-server prevents it from exec'ing bin/dev during postCreate.
bin/setup --skip-server

echo
echo "=== Dev environment ready ==="
echo
echo "Next steps:"
echo "  1. Copy .env.example → .env and fill in any secrets you need"
echo "  2. Run: bin/dev"
echo "  3. Visit: http://localhost:3000"
echo
echo "For deployment with Kamal:"
echo "  1. Edit config/deploy.yml (server IP, registry, app name)"
echo "  2. Set KAMAL_REGISTRY_PASSWORD in .kamal/secrets"
echo "  3. Run: bin/kamal setup"
```

Five behavioral changes:

| Change | Why |
|---|---|
| Drop `mise install` step | Ruby is now baked into the base image |
| Add `apt-get install` for system packages | Match prod Dockerfile's `apt-get` lines for libvips, sqlite3, jemalloc, build tools |
| Replace inline `bundle install` + `db:prepare` with `bin/setup --skip-server` | Single source of truth for "what does ready mean"; honors Rails convention (Justin) |
| Make Playwright install idempotent | Avoid 300MB re-download on rebuild (Justin, Chris) |
| Add explicit "Next steps" echo block | Tell the forker what command to run next (Justin, Hartl, Chris) |

#### `config/application.rb`

Add YJIT enablement (Aaron). Exact line depends on the file's current structure; expectation is one line inside the `Application` class:

```ruby
config.yjit = true
```

This is idempotent — Rails 8.1 may default it on for supported Ruby versions, but stating it explicitly in the template documents the intent for forkers.

#### `config/deploy.yml`

Uncomment and wire the `builder.args` block at lines 87–88:

```diff
  # Configure the image builder.
  builder:
    arch: amd64

    # # Build image via remote server (useful for faster amd64 builds on arm64 computers)
    # remote: ssh://docker@docker-builder-server
    #
-   # # Pass arguments and secrets to the Docker build process
-   # args:
-   #   RUBY_VERSION: ruby-4.0.2
+   # Pass Ruby version through so prod image always matches dev.
+   # Sourced from .tool-versions; keep in sync if you change the format.
+   args:
+     RUBY_VERSION: "4.0.4"
    # secrets:
    #   - GITHUB_TOKEN
    #   - RAILS_MASTER_KEY
```

Note the version format change: the commented example was `ruby-4.0.2` but the Dockerfile's `FROM docker.io/library/ruby:$RUBY_VERSION-slim` expects a bare version (`4.0.4`), not a `ruby-` prefix. The commented example was incorrect; we ship the correct format.

### New files

#### `.env.example`

```bash
# Copy this file to .env and fill in the values you need for local development.
# Production secrets live in Rails credentials (bin/rails credentials:edit) or
# in .kamal/secrets — never commit real secrets to .env files.

# === Rails ===

# Required if you need to run the production-style image locally (e.g. via
# docker compose against the prod Dockerfile). Not needed for `bin/dev`.
# RAILS_MASTER_KEY=

# === Kamal deployment ===

# Personal access token or registry password used by `kamal deploy` to push to
# GitHub Container Registry. See config/deploy.yml:registry for the username.
# KAMAL_REGISTRY_PASSWORD=
```

The file ships with everything commented out so a fresh fork's `.env` (after copying) is a no-op until the forker uncomments what they need. Comments document each variable's purpose.

### Files NOT modified

- `Dockerfile`'s multi-stage structure — Option C keeps prod and dev as separate concerns; multi-target collapse is explicitly out of scope.
- `bin/setup` — unchanged; `setup.sh` now invokes it.
- `config/deploy.yml` beyond the builder.args block — production topology (Solid Queue, SQLite rolling deploy, queue separation) is deferred to a follow-up phase.
- `.gitignore` — no new files need to be ignored (`.env*` already covered).

---

## Verification of base assumptions

These facts inform the spec and should hold true before implementation begins:

| Claim | Evidence |
|---|---|
| `bin/setup` exists and is idempotent | `bin/setup` reads `bundle check || bundle install`, `bin/rails db:prepare`, asset clobber, ends with `exec "bin/dev"` |
| `Gemfile.lock` has no `RUBY VERSION` block | Confirmed via grep — only `BUNDLED WITH 4.0.6` is present |
| `config/application.rb` does not currently set `config.yjit` | Confirmed via grep — no YJIT references in `config/application.rb` or `config/environments/production.rb` |
| `.env.example` does not exist | Confirmed — no `.env*` files in repo root |
| `config/deploy.yml` has `builder.args` scaffolded as comments | Confirmed at `config/deploy.yml:87-88` (incorrect format `ruby-4.0.2`; we ship correct format) |
| `vendor/` contains `.keep` and `javascript/` subdir | Confirmed; markdowndocs symlink may be added by individual forkers per project memory |
| Ruby 4.0.4 is the current latest stable | User-confirmed in this session |

---

## Edge cases

| Case | Behavior |
|---|---|
| Forker on M1 Mac rebuilds devcontainer | `ruby:4.0.4-slim` is multi-arch; arm64 image pulled automatically |
| Forker adds Postgres later | Add via devcontainer feature (`ghcr.io/devcontainers-extra/features/postgres:1`) or compose service; not affected by Option C |
| Forker runs native Mac dev (no devcontainer) | `.tool-versions` drives mise/asdf/rbenv locally; `bin/setup` works identically; workflow unchanged |
| Forker bumps Ruby in `.tool-versions` only | Bundler errors on next `bundle install` because `Gemfile.lock` has a `RUBY VERSION` pin; forker must `bundle install` to regenerate, which updates the lock and Kamal builds pick it up via `config/deploy.yml:builder.args` |
| `vendor/` contains a markdowndocs symlink pointing outside the build context | Reordered `COPY vendor/` runs after `bundle install` but still requires the symlink target to be inside the Docker build context; behavior unchanged from current Dockerfile — symlinks pointing outside build context will fail in both old and new ordering |
| Devcontainer rebuilt against `ruby:4.0.4-slim` for the first time | `common-utils` feature creates the `vscode` user; `setup.sh` uses `sudo apt-get` for system packages (sudo is provided by `common-utils`) |
| Forker has no SSH keys at `~/.ssh` | Bind mount in `devcontainer.json` resolves to a missing directory; container build/rebuild does not fail (Docker tolerates missing bind sources for readonly mounts with appropriate config). Forker without keys cannot `kamal deploy` but devcontainer still functional |
| `bundle exec bootsnap precompile -j 1` after Ruby 4.0.4 bump | Bootsnap re-precompiles for new Ruby version; existing precompile cache is invalidated |
| Bundler 4.0.6 + `ruby file:` directive | `ruby file:` is supported in Bundler 2.4+ and present in Bundler 4.0.6 |

---

## Known limitations

### Native-arch bootsnap build penalty unchanged

The `-j 1` flag on `bootsnap precompile` (`Dockerfile:45` and `:52`) is retained from current code. Aaron flagged that this is unnecessary when CI builds natively (`TARGETPLATFORM == BUILDPLATFORM`), and gating it would unlock multi-core build perf in GitHub Actions runners. This is a small optimization deferred from this spec to keep scope focused on the consensus items — it would change CI build characteristics and deserves its own measured rollout.

### Multi-stage Dockerfile unification deferred

Nick Janetakis's stronger recommendation (collapse dev and prod into a single multi-target `Dockerfile`) was evaluated and explicitly rejected in favor of Option C. The runtime-parity win is captured by the shared base image; the additional CI cache-reuse benefit was judged not worth the comprehension cost and the loss of devcontainer-features ergonomics. If a future bug demonstrates that residual divergence between `Dockerfile` and `.devcontainer/setup.sh` is hurting forkers, revisit.

### Production topology untouched

Rosa Gutiérrez's findings — `SOLID_QUEUE_IN_PUMA: true` default, SQLite rolling-deploy data-loss risk under default Kamal replica settings, mailers/sweep queue separation — are NOT addressed in this spec. They live in `config/deploy.yml`, `config/queue.yml`, and `config/recurring.yml` and represent production behavior changes that deserve their own scoped review with potentially their own dispatched Ops panel re-review. Tracked as a follow-up phase.

---

## Acceptance criteria

Each item is a pass/fail check.

- [ ] `cat .tool-versions | grep ruby` outputs `ruby 4.0.4`
- [ ] `head -5 Gemfile` shows `ruby file: ".tool-versions"` after the `source` line
- [ ] `grep "RUBY VERSION" Gemfile.lock` matches a block containing `ruby 4.0.4`
- [ ] `grep "BUNDLE_WITHOUT" Dockerfile` shows `"development:test"`
- [ ] `grep "MALLOC_CONF" Dockerfile` shows `"dirty_decay_ms:1000,muzzy_decay_ms:0"`
- [ ] `grep "ARG RUBY_VERSION" Dockerfile` shows `=4.0.4`
- [ ] `grep ".tool-versions" Dockerfile` finds the updated comment (not `.ruby-version`)
- [ ] `Dockerfile` line order: `COPY Gemfile Gemfile.lock` appears BEFORE `COPY vendor/` AND BEFORE `bundle install` runs
- [ ] `grep "image" .devcontainer/devcontainer.json` shows `"docker.io/library/ruby:4.0.4-slim"`
- [ ] `grep -c "mise" .devcontainer/devcontainer.json` returns 0
- [ ] `grep "docker-outside-of-docker" .devcontainer/devcontainer.json` finds a match
- [ ] `grep "modelrails-bundle-cache" .devcontainer/devcontainer.json` finds a match
- [ ] `grep "forwardPorts" .devcontainer/devcontainer.json` shows both `3000` and `1080`
- [ ] `grep "portsAttributes" .devcontainer/devcontainer.json` finds a match with labels for each forwarded port
- [ ] `grep "bin/setup" .devcontainer/setup.sh` finds an invocation (no longer reimplementing it)
- [ ] `grep -c "mise install" .devcontainer/setup.sh` returns 0
- [ ] `grep "apt-get install" .devcontainer/setup.sh` shows the system package list mirroring the Dockerfile
- [ ] `.devcontainer/setup.sh` final echo block contains "Next steps:" and references `.env.example` + `bin/dev`
- [ ] `test -f .env.example` succeeds; file contains `RAILS_MASTER_KEY` and `KAMAL_REGISTRY_PASSWORD` (commented)
- [ ] `grep "config.yjit" config/application.rb` finds a match set to `true`
- [ ] `grep -A2 "builder:" config/deploy.yml` shows uncommented `args.RUBY_VERSION: "4.0.4"`
- [ ] `bin/rails about` runs successfully after migration (proves Ruby + gems + Rails boot)
- [ ] Full RSpec suite passes (`bin/rspec`) with 0 failures
- [ ] Lefthook pre-push completes cleanly
- [ ] `docker build .` from repo root succeeds against the production Dockerfile (catches the Ruby bump, COPY reorder, `MALLOC_CONF` syntax in one shot)

---

## Testing strategy

This spec is mechanical infrastructure refactor, not behavior change. The full existing RSpec suite serves as the regression guard — if any test breaks, something more subtle changed than intended. No new tests are required by this spec.

Three operational smoke tests, run manually before the PR ships:

| Test | Method |
|---|---|
| Devcontainer rebuilds cleanly from scratch on the new base image | Delete container, "Rebuild Container" in VS Code, observe `setup.sh` runs to completion |
| Production image builds with the new Ruby + Dockerfile changes | `docker build -t modelrails_base:test .` from repo root |
| `kamal build` works from inside the devcontainer | After rebuild, run `bin/kamal build` (no actual deploy) — confirms docker-outside-of-docker + SSH mount are wired |

---

## What this does NOT cover

- **Multi-target unified Dockerfile** (Nick's full recommendation) — deferred indefinitely; revisit only if dev/prod divergence bugs surface despite Option C.
- **Production topology changes** (Rosa's Ops findings) — `SOLID_QUEUE_IN_PUMA`, SQLite rolling-deploy guards, queue separation — deferred to a separate phase with its own Ops panel re-review.
- **`-j N` parallelism for bootsnap** when building natively — Aaron's optimization deferred for separate measured rollout.
- **CI workflow changes** — the GitHub Actions workflow is not part of this spec. If CI needs to know about the Ruby bump, it inherits it through `.tool-versions` (assuming the workflow already reads from it; if not, that's a separate fix).
- **Lefthook hook updates** — current hooks should pass unchanged.
- **Documentation updates beyond `.env.example`** — README, CHANGELOG, etc. not in scope. If a forker-facing doc explicitly references `.ruby-version` or Ruby `4.0.2`, fix as part of the implementation but not as a primary deliverable.

---

## Verification (post-implementation)

1. **Full RSpec suite** — `bin/rspec`, expect 0 failures (per project's "full suite before commit" rule).
2. **Lefthook pre-push** — `LEFTHOOK=1 git push` to feature branch, expect clean.
3. **Devcontainer rebuild** — VS Code "Dev Containers: Rebuild Container", verify `setup.sh` completes and "Next steps" echo appears.
4. **`bin/rails about`** — runs cleanly inside rebuilt devcontainer; reports Ruby `4.0.4` and Rails `8.1.x`.
5. **`docker build .`** — production image builds successfully on amd64; image size shrinks measurably vs. baseline (proves `BUNDLE_WITHOUT="development:test"` is effective).
6. **`bin/kamal build`** — runs from inside devcontainer without "docker: command not found" or socket errors; confirms `docker-outside-of-docker` is wired.
7. **`ruby --version` parity check** — output inside devcontainer matches `cat .tool-versions | grep ruby` value matches Dockerfile `ARG RUBY_VERSION`.
8. **`bundle install` from a fresh checkout on Mac native** — succeeds with mise-managed Ruby 4.0.4 (proves `.tool-versions`-based pin works outside containers).
9. **`.env.example` copy test** — `cp .env.example .env`; verify `bin/dev` still starts (uncommented vars default to safe no-ops).
