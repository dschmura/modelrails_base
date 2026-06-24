# GitHub Codespaces (Browser-Hosted Dev Container) — Design

**Date:** 2026-06-24
**Status:** Approved (pending spec review)
**Scope:** Make `modelrails_base` run in a browser-hosted GitHub Codespace: the
app boots, you can complete magic-link sign-in, and the RSpec + Playwright test
suite runs in-container. Passkeys-over-Codespaces and Kamal-from-Codespace are
explicitly out of scope.

## Problem

The repo already ships a working `.devcontainer/` (a `devcontainer.json` +
`setup.sh`) built and proven for **local** VS Code Dev Containers. GitHub
Codespaces consumes the *same* `devcontainer.json` spec but runs it on a cloud
VM and reaches the app through a forwarded HTTPS proxy at
`https://<codespace-name>-<port>.app.github.dev` instead of `localhost`.

That single change of origin breaks three `localhost`-only assumptions, and the
current container spec carries one mount that is meaningless on a Codespaces VM:

1. **Host authorization (403 "Blocked host").** In development Rails'
   `ActionDispatch::HostAuthorization` only allows `localhost`, `0.0.0.0`,
   `*.local`, and IPs. `config/environments/development.rb` adds no host config,
   so a request to `…app.github.dev` is rejected until the domain is allowed.
2. **Magic-link sign-in links point at `localhost`.** This app is
   passwordless-first; sign-in emails render in Letter Opener Web (port 1080)
   with URLs built from
   `config.action_mailer.default_url_options = { host: "localhost", … }`. In a
   browser Codespace a `localhost:3000` link resolves to nothing, so sign-in
   cannot be completed. The mailer host must point at the forwarded URL.
3. **Server binding** is already handled. `rails server` binds to `localhost`
   in development by default (railties `server_command.rb`:
   `ENV.fetch("BINDING", default_host)` with a dev default of `"localhost"`),
   which the forward proxy cannot reach. The existing
   `remoteEnv: { BINDING: "0.0.0.0" }` already flips this to all-interfaces. No
   change — we keep it.
4. **Redundant `.ssh` bind mount.** `devcontainer.json` bind-mounts
   `${localEnv:HOME}/.ssh`, which does not exist on a Codespaces VM (Codespaces
   injects git auth via `gh`/`GITHUB_TOKEN`). It is also redundant locally — the
   VS Code Dev Containers extension auto-forwards the host SSH agent. Remove it
   so one config serves both environments.

## Decisions (locked during brainstorming)

- **One shared `devcontainer.json`** for local + Codespaces (not a split
  per-environment config). The only truly local-only entry — the `.ssh` mount —
  is redundant in both environments, so removing it unifies cleanly.
- **Scope:** boot + sign-in + in-container test suite. Passkeys/Kamal deferred.
- **Codespaces detection logic lives in a small, pure, unit-testable module**
  (`lib/codespaces.rb`), called from `development.rb` — not an inline,
  untestable `if` block. Environment files don't load in the `test` env, so
  inline logic could not satisfy the project's strict-TDD rule; an extracted
  module can.

## Architecture / units

### Unit A — `Codespaces` module (`lib/codespaces.rb`)

Pure functions over an env hash. No Rails dependency; autoloads as `Codespaces`
because `application.rb` already declares `config.autoload_lib(ignore:
%w[assets tasks])`.

```ruby
module Codespaces
  module_function

  # True only inside a GitHub Codespace (the CODESPACES env var is set to
  # "true" by the platform).
  def active?(env = ENV)
    env["CODESPACES"] == "true"
  end

  # e.g. "app.github.dev" — the port-forwarding domain the platform injects.
  def forwarding_domain(env = ENV)
    env["GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"]
  end

  # The forwarded host for a given app port, e.g.
  # "musical-space-abc123-3000.app.github.dev". No scheme, no trailing slash.
  def forwarded_host(port:, env: ENV)
    "#{env["CODESPACE_NAME"]}-#{port}.#{forwarding_domain(env)}"
  end
end
```

- **What it does:** answers "are we in a Codespace?" and "what host does the
  browser use to reach app port N?"
- **How you use it:** `Codespaces.active?`, `Codespaces.forwarding_domain`,
  `Codespaces.forwarded_host(port: 3000)`.
- **Depends on:** an env hash (defaulting to `ENV`). Nothing else.

### Unit B — Codespaces block in `config/environments/development.rb`

Appended immediately after the existing unconditional
`config.action_mailer.default_url_options` line (so the override sits next to
what it overrides):

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

- `config.hosts << ".app.github.dev"` (leading dot = allow the domain and its
  subdomains) clears the 403.
- The mailer override uses `protocol: "https"` and bakes the port into the
  subdomain (no `:port` key) — that is the forwarded-URL shape. Magic-link
  emails then open correctly from the browser.
- **Replace, not merge.** The override reassigns `default_url_options`
  wholesale rather than merging into the existing
  `{ host: "localhost", port: … }`. A merge would retain the stale `:port` key
  and emit a malformed `https://<host>-3000.app.github.dev:3000/…` (port in both
  the subdomain and appended). Replacing is the only correct shape.

### Unit C — `.devcontainer/devcontainer.json`

- **Remove** the `mounts` entry
  `source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly`.
  Keep the `modelrails-bundle-cache` volume mount.
- Keep `remoteEnv: { BINDING: "0.0.0.0" }`, `forwardPorts: [3000, 1080]`,
  `portsAttributes`, features, and `customizations` as-is.
- **No `hostRequirements`.** Default to the smallest Codespaces machine
  (2-core / 8 GB) — the lowest tier that still runs the app and the full
  Playwright/axe suite. The suite is CPU-bound and slow on 2 cores but does not
  fail; a dev who runs it often can bump the machine type from the Codespaces
  UI (documented in `codespaces.md`). Setting no floor avoids forcing a pricier
  machine on every codespace.

### Unit D — `.devcontainer/setup.sh`

- **`.env` bootstrap:** before the "next steps" message, `cp .env.example .env`
  if `.env` is absent. Harmless — every var in `.env.example` has a working
  default and `dotenv` only loads `.env` when present — but it gives the dev a
  ready file to edit.
- **Codespaces-aware next-steps message:** when `CODESPACES=true`, replace the
  `http://localhost:3000` guidance with: open the **Ports** panel (or click the
  forwarded port-3000 notification) to reach the app, and find magic-link emails
  in Letter Opener on the forwarded **1080** URL. Outside Codespaces, keep the
  existing localhost message.

### Unit E — `app/docs/developer/codespaces.md`

A short developer-audience guide (surfaces at `/docs` via markdowndocs):

- One-paragraph "Open in Codespaces" quickstart: create the Codespace →
  `bin/dev` → click the forwarded **3000** URL → request a magic link → open it
  in Letter Opener on **1080** → signed in.
- Why the host-auth and mailer-host settings exist (links to Units A/B).
- Test-suite note: `bin/ci` and the Playwright/axe system specs run entirely
  in-container against `127.0.0.1`, so they need no Codespaces-specific config.
- Machine-size note: the default 2-core Codespace runs the full system suite
  but slowly; bump the machine type from the Codespaces UI if you run `bin/ci`
  frequently.
- Note that passkeys and Kamal-from-Codespace are out of scope for now.

## Testing

This project follows strict TDD; the testable unit is the `Codespaces` module.

- **`spec/lib/codespaces_spec.rb`** (red-first):
  - `active?` is `true` only when the env hash has `CODESPACES == "true"`;
    `false` for absent/`"false"`/other values.
  - `forwarding_domain` returns the injected domain (and `nil` when unset).
  - `forwarded_host(port:)` returns `"<CODESPACE_NAME>-<port>.<domain>"` with no
    scheme and no trailing slash, for representative env hashes.
  - Tests pass explicit env hashes — no real-`ENV` mutation, no env leakage
    between examples.

- **Declarative config is verified by launching a real Codespace** (documented
  as manual UAT in the plan / `codespaces.md`), since `devcontainer.json` and
  `setup.sh` are not unit-testable:
  1. Create a Codespace from the repo in the browser.
  2. `bin/dev`; click the forwarded 3000 URL → app loads (no 403).
  3. Request a magic link; open it from Letter Opener (1080) → sign-in
     completes (link host = forwarded domain).
  4. `bin/ci` → RSpec + Playwright/axe system specs pass in-container.

## Out of scope

- WebAuthn/passkeys over the Codespaces HTTPS origin (`WEBAUTHN_ORIGIN` /
  `WEBAUTHN_RP_ID` derivation from the forwarded host).
- Kamal / docker-outside-of-docker builds executed from inside a Codespace.
- Codespaces **prebuilds** (a startup-latency optimization, not required for
  function).

## Files touched

- `lib/codespaces.rb` *(new)*
- `config/environments/development.rb` *(append Codespaces block)*
- `.devcontainer/devcontainer.json` *(remove `.ssh` mount)*
- `.devcontainer/setup.sh` *(`.env` bootstrap; Codespaces-aware next-steps)*
- `app/docs/developer/codespaces.md` *(new)*
- `spec/lib/codespaces_spec.rb` *(new)*
