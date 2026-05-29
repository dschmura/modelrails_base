---
title: Single-tenant
description: Stand up and verify the Single-tenant preset — one shared workspace, no personal workspaces, tenancy UI suppressed
keywords: single-tenant preset shared workspace internal tool owner bootstrap seed owner_setup_link invite-only
audience: [guide, technical]
---

[App Presets](/docs/presets) › Single-tenant

# Single-tenant

**What it is.** One shared workspace, no personal workspaces, the tenancy UI suppressed. Every authenticated user is a member of the same workspace; new signups land there automatically. There is no workspace switcher, no "New workspace" UI, and no way for users to create additional workspaces.

**Who it's for.** Internal company tools, one-org deployments, classroom/cohort tools with central administration — any product where "the workspace" is implicit and there's no need to expose tenancy as a user-facing concept.

**What you get when configured.**

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | typically `:invite_only` (your call) | `config/initializers/signup.rb` |
| `tenancy.onboarding` | `:shared` | `User#onboard_workspace` dispatches to `join_shared_workspace` |
| `tenancy.workspace_creation` | `:disabled` | `WorkspacesController` `before_action` redirects `:new`/`:create` |
| `permitted_join_strategies` | `[:invite]` *(implicit — only mechanism built)* | `Invitation.consume!` is the single membership-grant path |

The workspace switcher auto-hides under this preset because every user has exactly one membership (the existing #145 "hide personal from switcher" logic plus the single-membership-no-switcher rule combine naturally — no extra suppression needed).

**Setup steps.**

1. Set the ENV vars before running `bin/setup` (or before deploying):

   | Variable | Required? | Example | Purpose |
   |---|---|---|---|
   | `TENANCY_ONBOARDING` | yes | `shared` | Selects this preset |
   | `TENANCY_WORKSPACE_CREATION` | yes | `disabled` | Turns off "New workspace" UI + route |
   | `TENANCY_SHARED_WORKSPACE_SLUG` | yes | `acme` | URL-safe slug of the shared workspace |
   | `TENANCY_SHARED_WORKSPACE_NAME` | no | `Acme Inc.` | Display name (defaults to titleized slug) |
   | `TENANCY_OWNER_EMAIL` | yes | `admin@acme.com` | Email of the initial Owner |
   | `TENANCY_OWNER_FIRST_NAME` | no | `Admin` | Display first name (default `Workspace`) |
   | `TENANCY_OWNER_LAST_NAME` | no | `User` | Display last name (default `Owner`) |
   | `SIGNUP_MODE` | yes | `invite_only` | Lock account creation to invitations |
   | `APP_HOST` | no | `app.acme.com` | Host used in the logged workspace URL and in `tenancy:owner_setup_link`'s sign-in link (default `localhost` — set this on staging/prod) |

2. Run `bin/setup` (or `bin/rails db:seed` on an existing app). The seed is idempotent — safe to re-run.

3. The seed creates the shared workspace and the Owner user (with a verified email Authentication and an Owner Membership). In development the password-set email is captured by **Letter Opener** — open `/letter_opener` to see it (it isn't sent over SMTP). In `production` it deliberately does **not** put a credential in the logs (a logged token would linger in log retention past its short expiry); instead it logs the workspace URL and points you to an on-demand task. Mint the Owner's sign-in link when you're ready to use it:

   ```bash
   bin/rails tenancy:owner_setup_link
   ```

   This prints a fresh, short-lived password-set URL — the expiry clock starts when you run it, not at deploy time. Deliver it to the Owner out-of-band (or run it yourself if you're claiming the account). It doubles as a break-glass Owner login if email delivery is ever down.

4. The Owner opens the password-set link, sets a password, signs in. They can then invite other users via the normal invitation flow — **each invitation specifies the role the invitee receives** (Member, Admin, etc.). The Owner remains the single source of new-role-granting authority for the shared workspace; roles can also be changed after signup via the members UI at `/workspaces/:slug/members`.

> **Re-inviting under `:shared` updates the role, it doesn't error.** Because `:shared` onboarding pre-creates a placeholder membership for every new user, `Workspace#admit` *reconciles* — admitting an existing member to a new role updates their role rather than raising "already a member" (the behavior you'd get under the default `:personal` posture). So re-inviting someone at a higher role is a valid way to promote them.

**How to verify your setup is Single-tenant.** After running the seed:

```bash
bin/rails console
```

```ruby
TenancyConfig.shared?                          # => true
TenancyConfig.shared_workspace.slug            # => "acme" (your slug)
TenancyConfig.shared_workspace.personal?       # => false
TenancyConfig.shared_workspace.memberships.count  # => 1 (the seeded Owner)

owner = User.find_by!(email_address: ENV["TENANCY_OWNER_EMAIL"])
owner.workspaces                               # => [<Workspace slug: "acme">]
owner.personal_workspace_id                    # => nil
owner.memberships.first.role.slug              # => "owner"
```

In the browser, after the Owner has set their password and signed in:

1. They land directly in the shared workspace (no switcher, no chooser).
2. The header workspace switcher does not appear.
3. `/workspaces/new` redirects to root with the alert `Workspace creation is disabled on this instance.`
4. Invited new users (via the standard invitation flow) verify their email and become Members of the same shared workspace.

**When to switch presets.**

- *"Users should each get their own personal workspace; this is too restrictive."* → **[Solo-default](/docs/presets-solo)**.
- *"Each customer should have their own workspace, and signup should be public."* → **[Open SaaS](/docs/presets-open-saas)** (Reshape 2+).

## Next steps

- **[← Compare all presets](/docs/presets)** — the decision matrix and the other two shapes.
- **[Extending ModelRails →](/docs/extending)** — add your own workspace-scoped features on top of this preset.
