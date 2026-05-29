---
title: Solo-default
description: Stand up and verify the Solo-default preset — every user gets a personal workspace; signup open or invite-only
keywords: solo-default preset personal workspace prosumer multi-workspace signup onboarding switcher
audience: [guide, technical]
---

[App Presets](/docs/presets) › Solo-default

# Solo-default

**What it is.** The default shape modelrails_base ships with. Every user auto-gets a *personal* workspace on signup. They can be invited to additional workspaces (org or personal) by other users. The tenancy UI (workspace switcher, "create workspace") surfaces naturally when they belong to more than one workspace.

**Who it's for.** Prosumer / multi-workspace tools — products where a solo user can use the app meaningfully alone (in their personal workspace) but team workspaces are also a first-class concept. Notion, Figma, Linear's personal tier all fit this shape.

**What you get out of the box.** This is the shipped state; no configuration changes are needed to land on it.

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | `:invite_only` (default — set `SIGNUP_MODE=open` to flip) | `config/initializers/signup.rb` |
| `tenancy.onboarding` | `:personal` *(implicit — only path currently built)* | `User#create_personal_workspace` callback runs on user creation |
| `tenancy.workspace_creation` | `:enabled` *(implicit)* | `WorkspacesController#new` accessible to any authenticated user |
| `permitted_join_strategies` | `[:invite]` *(implicit — only mechanism built)* | `Invitation.consume!` is the single membership-grant path |

Three specific behaviors worth knowing:

- **Personal workspaces are hidden from the header switcher dropdown** ([#145](https://github.com/dschmura/modelrails_base/pull/145)) — solo users don't see a switcher until they have at least one *org* workspace.
- **Invitation acceptance is email-bound across every path** (signup / OAuth / magic-link / signed-in accept) — a leaked invite link cannot be redeemed by someone else. Magic-link invitations (no email set) remain intentionally bearer. See PRs [#175](https://github.com/dschmura/modelrails_base/pull/175), [#176](https://github.com/dschmura/modelrails_base/pull/176), [#180](https://github.com/dschmura/modelrails_base/pull/180), [#182](https://github.com/dschmura/modelrails_base/pull/182).
- **Email verification uses Rails 8 `generates_token_for`** — signed, stateless, single-use. See `Authentication#generates_token_for :email_verification`.

**How to verify your setup is Solo-default.** After cloning and bootstrapping (`bin/setup`), open a console:

```bash
bin/rails console
```

```ruby
user = User.create!(
  email_address: "test@example.com",
  first_name: "Test", last_name: "User",
  password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!"
)

user.workspaces.count                                  # => 1
user.workspaces.first.personal?                        # => true
user.workspaces.first.memberships.first.role.slug      # => "owner"
```

Three positives confirm the preset: a new user has exactly one workspace, it's flagged personal, and they own it.

Browser verification (optional, requires `SIGNUP_MODE=open` or a valid invitation) — sign up a fresh user and confirm:

1. After verifying their email, they land in their personal workspace.
2. The header workspace switcher does *not* show their personal workspace.
3. `/workspaces/new` is accessible and creates a second workspace.

**When to switch presets.**

- *"Every user should land in one shared workspace — there should* be *no personal workspaces, and the switcher should be gone entirely."* → **[Single-tenant](/docs/presets-single-tenant)** (Reshape 1).
- *"I need self-serve join via shareable links (`open_link`), email-domain auto-join (`domain`), or a request-and-approve flow."* → **[Open SaaS](/docs/presets-open-saas)** (Reshape 2+).

## Next steps

- **[← Compare all presets](/docs/presets)** — the decision matrix and the other two shapes.
- **[Extending ModelRails →](/docs/extending)** — add your own workspace-scoped features on top of this preset.
