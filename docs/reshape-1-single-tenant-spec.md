# Reshape 1: Single-tenant Spec

**Status:** Working draft. Not yet implemented. Tracks back to [#181](https://github.com/dschmura/modelrails_base/issues/181).

## Goal

Add the second app preset: a configuration shape where one shared workspace replaces per-user personal workspaces, the tenancy UI is hidden, and signup is locked. Internal-company-tool shape.

A `:shared` deployment should let a downstream developer set 2–4 env vars, run `bin/setup`, and land on a working app where every user (after invitation) becomes a member of the same workspace — with no workspace switcher, no "create workspace" UI, no personal-workspace concept surfaced.

The Solo-default preset must remain the default and unchanged.

---

## Decision 1: Knob declaration

**Decided:** `config/initializers/tenancy.rb`, ENV-driven, optionally read through Rails encrypted credentials for the sensitive bits (owner email).

```ruby
# config/initializers/tenancy.rb
Rails.application.config.x.tenancy.onboarding =
  ENV.fetch("TENANCY_ONBOARDING", "personal").to_sym

Rails.application.config.x.tenancy.workspace_creation =
  ENV.fetch("TENANCY_WORKSPACE_CREATION", "enabled").to_sym

Rails.application.config.x.tenancy.shared_workspace_slug =
  ENV["TENANCY_SHARED_WORKSPACE_SLUG"]

# Boot-time validation: catch mistyped values early, never at request time.
unless [:personal, :shared].include?(Rails.configuration.x.tenancy.onboarding)
  raise "Invalid TENANCY_ONBOARDING: must be 'personal' or 'shared'"
end

unless [:enabled, :disabled].include?(Rails.configuration.x.tenancy.workspace_creation)
  raise "Invalid TENANCY_WORKSPACE_CREATION: must be 'enabled' or 'disabled'"
end

if Rails.configuration.x.tenancy.onboarding == :shared &&
   Rails.configuration.x.tenancy.shared_workspace_slug.blank?
  raise "TENANCY_SHARED_WORKSPACE_SLUG required when TENANCY_ONBOARDING=shared"
end
```

A thin reader module keeps call sites clean and posture-aware code in one place:

```ruby
# app/lib/tenancy_config.rb
module TenancyConfig
  module_function

  def onboarding              = Rails.configuration.x.tenancy.onboarding
  def shared?                 = onboarding == :shared
  def personal?               = onboarding == :personal
  def workspace_creation_enabled? = Rails.configuration.x.tenancy.workspace_creation == :enabled
  def shared_workspace_slug   = Rails.configuration.x.tenancy.shared_workspace_slug
  def shared_workspace        = Workspace.find_by(slug: shared_workspace_slug) if shared?
end
```

**Why a helper module rather than `Rails.configuration.x.tenancy.shared?` everywhere:** Tell-don't-ask + one place to evolve. When Reshape 2 adds `:create_org`, the third onboarding value lands in one file, not scattered.

---

## Decision 2: Bootstrap-owner mechanism — panel pattern survey

The chicken-and-egg: `:shared` posture needs the shared workspace + an Owner *before* the first user can sign up via the invitation flow. Three candidate mechanisms:

| Pattern | Examples in the wild | Pros | Cons |
|---|---|---|---|
| **A. Env-email + seed creates User directly** | Discourse, Plausible, Mastodon initial admin | Declarative, idempotent, no manual step, no schema change | Creates a User outside the invitation flow (separate code path) |
| **B. Seed creates Invitation, owner signs up via the existing flow** | None directly; closest is "invite first admin" patterns | Reuses the hardened invitation flow — single membership-grant path | Needs `invited_by` workaround (system user or relaxed validation); more moving parts |
| **C. First-signup-becomes-owner** | Redmine (anti-pattern) | Zero config | Race condition under open signup; requires invite_only + bootstrap to invite the first user (circular) |

**Recommendation: A.** The dominant self-hosted Rails pattern, and the simplest. The seed creates Workspace + User + a *verified* email Authentication (operator vouching for the email *is* the verification) + Owner Membership, then mails a password-set link via the existing password-reset flow. The owner clicks, sets a password, signs in, lands as Owner of the shared workspace.

**Why not B (despite reusing #174–182):** the `invited_by` validation is load-bearing for the security model (every invite traces to a human). Relaxing it for bootstrap, or seeding a synthetic "system" user, introduces a permanent shape just to handle one-time setup. A's direct creation is honest about what bootstrap *is* — operator-vouched seed data, not a real invitation.

**Why not C:** The race is real, and under `:invite_only` (the typical `:shared` instance gate) there's no one to issue the first invitation. Circular.

Draft seed code:

```ruby
# db/seeds/tenancy.rb (loaded from db/seeds.rb when TenancyConfig.shared?)
if TenancyConfig.shared?
  slug = ENV.fetch("TENANCY_SHARED_WORKSPACE_SLUG")
  name = ENV.fetch("TENANCY_SHARED_WORKSPACE_NAME", slug.titleize)
  owner_email = ENV.fetch("TENANCY_OWNER_EMAIL") {
    raise "TENANCY_OWNER_EMAIL required for :shared onboarding"
  }

  workspace = Workspace.find_or_create_by!(slug: slug) do |w|
    w.name = name
    w.personal = false
  end

  owner = User.find_or_create_by!(email_address: owner_email) do |u|
    u.first_name = ENV.fetch("TENANCY_OWNER_FIRST_NAME", "Workspace")
    u.last_name  = ENV.fetch("TENANCY_OWNER_LAST_NAME",  "Owner")
    u.password   = SecureRandom.urlsafe_base64(32)  # placeholder; owner sets via reset
    u.password_confirmation = u.password
  end

  owner.authentications.find_or_create_by!(provider: "email", uid: owner.email_address) do |auth|
    auth.email = owner.email_address
    auth.verified_at = Time.current  # operator vouching; reset link proves possession
  end

  Membership.find_or_create_by!(workspace: workspace, user: owner) do |m|
    m.role = Role.find_by!(slug: "owner", workspace_id: nil)
  end

  # Send a password-set link via the existing reset flow.
  # In production, prefer printing the URL for the operator to deliver out-of-band.
  if Rails.env.production?
    Rails.logger.info "[tenancy] Owner setup URL: #{owner.password_reset_url}"
  else
    PasswordsMailer.with(user: owner).reset.deliver_now
  end
end
```

ENV vars (with sensible defaults where possible):

| Variable | Required? | Default | Purpose |
|---|---|---|---|
| `TENANCY_ONBOARDING` | no | `personal` | `personal` \| `shared` |
| `TENANCY_WORKSPACE_CREATION` | no | `enabled` | `enabled` \| `disabled` |
| `TENANCY_SHARED_WORKSPACE_SLUG` | yes (when `:shared`) | — | URL-safe slug of the shared workspace |
| `TENANCY_SHARED_WORKSPACE_NAME` | no | titleized slug | Display name |
| `TENANCY_OWNER_EMAIL` | yes (when `:shared`) | — | Initial owner |
| `TENANCY_OWNER_FIRST_NAME` | no | `"Workspace"` | Display name |
| `TENANCY_OWNER_LAST_NAME` | no | `"Owner"` | Display name |

Sensitive bits (owner email at minimum) can be read from Rails encrypted credentials with ENV fallback if a deployer prefers.

---

## Decision 3: Personal-workspace plumbing — panel synthesis

Should `User#create_personal_workspace` be **conditionalized at the callback** or should the personal-workspace concept (the `personal` flag, the `personal_workspace_id` denormalization, the hide-from-switcher logic) be **removed entirely** under `:shared`?

| Panelist | Position |
|---|---|
| **DHH** | "Delete what you don't use" — *but* this is one template supporting multiple postures. Conditionalize at the boundary; don't proliferate posture-aware code. One if/else, not 47 polymorphic dispatches. |
| **Dave Thomas / Jim Weirich** | Tell don't ask. The User shouldn't check a global config string. Extract a strategy: `Tenancy::Onboarding.run(user)` dispatches to `PersonalWorkspaceOnboarder` vs `SharedWorkspaceOnboarder`. The User model doesn't know what postures exist; the strategy does. |
| **Sandi Metz** | What's the cost of change? Conditional is 5 lines. Strategy is 30 lines + a namespace + extension point. If `:create_org` is months away, conditional is cheaper to live with. Extract when the third caller arrives. |
| **Kent Beck** | "Make the change easy, then make the easy change." Conditional now; extract the strategy when posture #3 knocks. Two data points are better than one for designing an abstraction. |
| **Aaron Patterson** | The schema — `personal: true`, `personal_workspace_id` — should *stay*. They're nullable/unused on `:shared` deployments; that's the cheapest accommodation. Dropping schema per-posture is a maintenance trap. |

**Consensus:**

1. **Conditionalize the `User#onboard_workspace` callback now** — simplest path, established Kent Beck rhythm.
2. **Keep the `personal` flag and `personal_workspace_id` column** — schema stays posture-agnostic; unused under `:shared` costs nothing.
3. **Extract `Tenancy::Onboarding` strategy *if/when* the third posture (`:create_org`) is built** — not yet.
4. **Personal-workspace-hidden-from-switcher logic ([#145](https://github.com/dschmura/modelrails_base/pull/145)) stays untouched** — moot under `:shared` (nothing to hide), so it's free.

Draft callback change:

```ruby
class User < ApplicationRecord
  after_create :onboard_workspace

  private

  def onboard_workspace
    case TenancyConfig.onboarding
    when :personal then create_personal_workspace  # existing method, unchanged
    when :shared   then join_shared_workspace
    end
  end

  def join_shared_workspace
    workspace = TenancyConfig.shared_workspace
    raise "Shared workspace #{TenancyConfig.shared_workspace_slug.inspect} not found" unless workspace

    workspace.memberships.create!(
      user: self,
      role: Role.find_by!(slug: default_shared_role_slug, workspace_id: nil)
    )
  end

  def default_shared_role_slug
    # Lowest privilege for self-onboarding. Owners + admins are seeded separately.
    "member"
  end
end
```

The old `create_personal_workspace` method stays as-is; the only change to `User` is renaming the `after_create` target from `create_personal_workspace` directly to `onboard_workspace` (a one-line dispatch).

---

## Decision 4: UI suppressions — Jason Fried lens

**Principle (per user direction, Fried-aligned):** under `:shared`, don't gate-and-hide — don't *render* what isn't relevant. "Hidden complexity is still complexity." But within a single codebase supporting multiple postures, the practical version of "don't render" is **render-time conditionals on the posture knob at the partial boundaries**, not posture-aware code sprinkled through every view.

Most suppression falls out for free:

| Element | Suppression under `:shared` | Mechanism |
|---|---|---|
| Workspace switcher | **Free** — every user has 1 membership, no personal workspaces exist to filter, so #145's logic naturally produces an empty switcher | Existing |
| "New workspace" link in nav/menus | Wrap in `TenancyConfig.workspace_creation_enabled?` | New conditional |
| `WorkspacesController#new` / `#create` routes | Reject unless `workspace_creation_enabled?` | New `before_action` |
| Personal-workspace settings link / copy | Wrap in `TenancyConfig.personal?` | New conditional, ~1 view |

Controller gate:

```ruby
class WorkspacesController < ApplicationController
  before_action :ensure_workspace_creation_enabled, only: [:new, :create]

  private

  def ensure_workspace_creation_enabled
    return if TenancyConfig.workspace_creation_enabled?
    redirect_to root_path, alert: t("workspaces.creation_disabled")
  end
end
```

View conditional (template):

```erb
<% if TenancyConfig.workspace_creation_enabled? %>
  <%= link_to t("workspaces.new_link"), new_workspace_path, class: "..." %>
<% end %>
```

The Fried discipline: **don't add a `Visible` decorator class, don't add a feature-flag service, don't introduce a "UI manifest."** Two conditionals at the boundaries are enough. The dial is `TenancyConfig`, the call sites are local, no abstraction is justified yet.

---

## Schema changes

**None.** Every existing column accommodates `:shared` posture as-is:

- `workspaces.personal` defaults `false`; the shared workspace simply has `personal: false`.
- `users.personal_workspace_id` is nullable; unused under `:shared`.
- All membership/invitation/auth machinery is unchanged.

---

## Test plan (TDD order)

1. **`spec/lib/tenancy_config_spec.rb`** — defaults, ENV reading, helper predicates.
2. **`spec/initializers/tenancy_spec.rb`** *(or covered in a request spec)* — boot-time validation raises on bad values.
3. **`spec/models/user_spec.rb`** — `#onboard_workspace` under `:personal` creates personal (existing behavior); under `:shared` joins the shared workspace as a member.
4. **`spec/requests/workspaces_spec.rb`** — `GET /workspaces/new` under `workspace_creation: :disabled` redirects with the configured alert.
5. **`spec/seeds_spec.rb`** *(or a dedicated rake spec)* — `:shared` seed creates Workspace + User + verified Authentication + Owner Membership idempotently.
6. **`spec/system/single_tenant_preset_spec.rb`** — end-to-end under `:shared`: invited user signs up, verifies email, lands in the shared workspace; switcher absent; "new workspace" link absent; `/workspaces/new` redirects.

Solo-default specs must continue passing untouched — the `:personal` branch is the existing path.

---

## Documentation update (ships in the same PR)

Fill in the `## Single-tenant` section of `app/docs/presets.md` following the same structure as Solo-default:

- **What it is** — one shared workspace, no personal workspaces, no tenancy UI.
- **Who it's for** — internal company tools, one-org deployments, classroom/cohort tools with central administration.
- **What you get out of the box** — table of the four knobs pinned to the `:shared` preset values.
- **Setup steps** — the env vars table (decision 2), `bin/setup` running the seed, owner clicks the password-set link from their inbox.
- **How to verify** — console snippet (the shared workspace exists, the seeded owner is its Owner, a fresh signed-up user lands as a Member of the same workspace); browser checks (no switcher, no "new workspace," landing page shows the shared workspace).
- **When to switch** — triggers toward Open SaaS (Reshape 2+).

---

## Build sequence (single PR, atomic)

1. `config/initializers/tenancy.rb` + `app/lib/tenancy_config.rb` (no behavior change; `:personal` is default).
2. `User#onboard_workspace` dispatch; existing tests pass under `:personal`.
3. `WorkspacesController` gate + view conditional.
4. Seed conditional (`db/seeds/tenancy.rb` loaded from `db/seeds.rb`).
5. Specs (TDD; system spec is the integration proof).
6. `app/docs/presets.md` Single-tenant section.
7. CHANGELOG `[Unreleased]` entry under `### Added`: "Single-tenant preset (`TENANCY_ONBOARDING=shared`) — see `app/docs/presets.md`."

---

## Risks / open questions

1. **Default role for self-joining members under `:shared`.** Drafted as `member`. Operators of small-team deployments may want `admin` by default. Decide: pin to `member` (safer, document override path) vs. add `TENANCY_SHARED_DEFAULT_ROLE` env var. *Lean: pin to `member`; defer the env var until asked.*
2. **What if `TENANCY_OWNER_EMAIL` matches an existing User on a `:personal`→`:shared` migration?** The seed uses `find_or_create_by!` — idempotent — but the existing user's personal workspace remains. That's correct (data preservation), but the preset docs should call out that **switching presets on a live app is a migration, not a config edit** (already noted in the design record on #181).
3. **Should the seed send the password-set email in `production`?** Drafted as: log the URL in production, send the email in non-production. Reason: production deploys often have email infrastructure that isn't reliable on the *very first* request (queues not yet running, etc.). Operator can run a one-shot rake task to send if preferred.
4. **`:shared` + `signup.mode = :open`.** Permitted by the knobs but unusual. Should the initializer warn? *Lean: no — it's a legitimate combination (a public-join shared space) and not our place to second-guess.*

---

## Out of scope for this reshape

- Per-workspace `join_policy` (Reshape 2 / #181's main slice).
- `:create_org` onboarding (Reshape 2+).
- Domain auto-join, request/approve, SCIM/SSO-JIT (later reshapes).
- A setup wizard UI for first-boot bootstrap (env-driven seed is sufficient).
