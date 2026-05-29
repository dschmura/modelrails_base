---
title: Open SaaS
description: Stand up and verify the Open SaaS preset — per-customer org workspaces, shareable join links, two signup postures
keywords: open-saas preset multi-tenant signup posture open_link join link flow a flow b allowlist tightening
audience: [guide, technical]
---

[App Presets](/docs/presets) › Open SaaS

# Open SaaS

The public-SaaS / multi-workspace shape: per-workspace control over how new members join. Workspace admins choose between **invite-only** and a **shareable open link** for each workspace they own. Built incrementally across Reshape 2 slices.

**Current status (Reshape 2b shipped):**

| Capability | Status |
|---|---|
| Per-workspace `join_policy` (invite / open_link) | ✅ |
| `WorkspaceJoinLink` model + atomic rotate + revoke | ✅ |
| Workspace settings UI (radio + active link + copy/rotate/revoke) | ✅ |
| Instance allowlist (`SIGNUP_PERMITTED_JOIN_STRATEGIES`) | ✅ |
| Flow A — *existing* authenticated user joins via link | ✅ |
| Flow B — *new* user via link (link opens the signup gate) | ✅ |
| `:domain` strategy (verified-email-domain auto-join) | ⏳ Reshape 3 |

**What you get when configured.**

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | `:open` *or* `:invite_only` — see posture below | `config/initializers/signup.rb` (`SIGNUP_MODE`) |
| `tenancy.onboarding` | `:personal` — each user gets a personal workspace, then creates/joins orgs | `User#onboard_workspace` |
| `tenancy.workspace_creation` | `:enabled` — users can create org workspaces | `WorkspacesController#new` |
| `permitted_join_strategies` | `[:invite, :open_link]` | `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` |

Open SaaS is **Solo-default's tenancy** (personal onboarding, workspace creation on) **plus the `open_link` join strategy** — so a workspace Owner can hand out a shareable join link instead of inviting people one by one.

## Signup posture — pick one

Open SaaS supports two front-door postures. They differ *only* in whether a stranger can create an account with no invitation and no link; both give workspace Owners/Admins identical control over their own members.

| | **Fully public** | **Controlled-growth** |
|---|---|---|
| `SIGNUP_MODE` | `open` | `invite_only` |
| `SIGNUP_PERMITTED_JOIN_STRATEGIES` | `invite,open_link` | `invite,open_link` |
| Who can create an account | anyone, at `/sign-up` | only via an invitation or a valid open-link token |
| Good for | self-serve products, communities | B2B, controlled betas, "every user vouched-for" |

Choose by whether you want an **anonymous front door**. `open` maximizes self-serve discovery. `invite_only + open_link` means every account traces to an invitation or a shared link — no cold signup — at the cost of no organic self-registration.

**The two knobs are independent.** `SIGNUP_MODE` controls *who may create an account*; `SIGNUP_PERMITTED_JOIN_STRATEGIES` controls *which join mechanisms exist*. Setting `SIGNUP_MODE=open` does **not** enable shareable links — you still need `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` for that. Both postures above set the strategies allowlist explicitly for exactly this reason.

> **`SIGNUP_MODE` is not how you "get an admin."** It only controls the anonymous front door. Your admin account, and the power to invite / approve / remove members, come from a workspace **Owner/Admin role** (`manage_members`) — present in *either* posture. There is no instance-wide super-admin: administration is per-workspace, so a user who self-registers under `open` owns and administers their own workspace. If you need cross-instance user administration, that's a feature to build, not a `SIGNUP_MODE` setting.

**Verify the strategy is enabled.** With `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` set, in `bin/rails console`:

```ruby
SignupPolicy.permits_strategy?(:open_link)   # => true

w = Workspace.create!(name: "Acme", personal: false, join_policy: "open_link")
w.open_join?                                  # => true (open to link-joins)
```

If `permits_strategy?(:open_link)` is `false`, the env var isn't set — links will be inert and the join-policy radio won't offer "Shareable join link".

**Setup (Reshape 2a — Flow A):**

1. Set `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` (default is `invite` alone — preserves Solo-default).
2. Owner/Admin opens their workspace's `/workspaces/:slug/settings/edit` and selects "Shareable join link" under Join policy.
3. The settings page shows the active link with **Copy / Rotate / Revoke** controls. The link follows the form `/workspaces/:slug/joins/:token`.
4. Share the link with anyone who has an account on this instance — clicking lands them on a confirmation page; the Join button admits them as a Member.

**Key behaviors (Reshape 2a):**

- **Personal workspaces are hard-guarded** — `Workspace#open_join?` returns `false` for personal workspaces regardless of `join_policy`. A personal workspace cannot be configured as `open_link` (validation rejects).
- **Instance allowlist enforced at two layers** — model validation (admins can't *set* `:open_link` when the instance forbids it) AND runtime guard (`Workspace#open_join?` re-checks defense-in-depth).
- **Atomic rotate** — clicking "Rotate" revokes the current link and creates a new one in one transaction. The previous link stops working immediately.
- **Capacity respected** — `Workspace#admit` honors `max_members`; an over-capacity join surfaces a clean error.
- **Single membership-grant entry point** — both invitation acceptance and link self-join go through `Workspace#admit`, sharing the same lock, capacity, and (under `:shared` posture) role-reconciliation logic.
- **Settings UI auto-hidden under `:shared` posture** — single-tenant deployments don't see the join-policy section.

**Setup (Reshape 2b — Flow B):** Already enabled by the same `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` setting from 2a. The Flow B path is automatic:

1. Brand-new visitor (no account) clicks a shareable join link.
2. `Workspaces::JoinsController#create` stashes the token in `session[:pending_join_token]` and redirects to `/sign-up`.
3. `SignupPolicy.allows_signup?` checks `workspace_join_acceptable?` — the open-link token opens the gate even under `SIGNUP_MODE=invite_only`. The signup form renders.
4. Visitor registers. `RegistrationsController#create` parks the token on the new email `Authentication` (`pending_join_link_token`), clears the session, sends the verification email.
5. Visitor clicks the verification email link. `Account::ConnectedAccountsController#verify` proves email ownership, then `Authentication#claim_pending_join_link!` admits them to the workspace as Member via `Workspace#admit`.

Stale conditions at claim time (link revoked, workspace policy reverted to `:invite`, instance allowlist no longer permits `:open_link`) are silently no-op'd — email verification proceeds and the user lands signed in but without the workspace membership. Capacity errors at claim time surface as a flash without blocking sign-in.

**Tightening the allowlist on a live app.** Removing `open_link` from `SIGNUP_PERMITTED_JOIN_STRATEGIES` (e.g. reverting to `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite`) takes effect **immediately at runtime** — there is no data migration. `Workspace#open_join?` re-checks the allowlist on every call, so all existing shareable links stop working at once and both Flow A and Flow B silently no-op. Workspaces keep their stored `join_policy: "open_link"` value, but it is now inert.

That stale value has one sharp edge: `join_policy_must_be_permitted_by_instance` validates on **every save**, so a workspace still carrying `open_link` becomes unsaveable — editing any unrelated field (name, color, …) fails with *"Join policy is not permitted by this instance"* — until its policy is reset.

**Reset command.** Reconcile stale workspaces back to a permitted policy from the Rails console (`bin/rails console`). `update_all` is deliberate here — it bypasses the very validation that would otherwise block the fix:

```ruby
# Reset every workspace still carrying the now-forbidden open_link policy.
Workspace.where(join_policy: "open_link").update_all(join_policy: "invite")
```

Their already-issued join links stay in the table but are inert (`open_join?` is `false`). Leave them, or revoke individually via the settings UI or `link.revoke!`.

**When to switch presets.**

- *"I want to lock signup entirely; users should only join via admin invitation."* → keep `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite` and the per-workspace radio defaults to invite — this *is* Solo-default with no further changes.
- *"Everyone should be in one shared workspace with no join UI at all."* → **[Single-tenant](/docs/presets-single-tenant)** preset (Reshape 1).

## Next steps

- **[← Compare all presets](/docs/presets)** — the decision matrix and the other two shapes.
- **[Extending ModelRails →](/docs/extending)** — add your own workspace-scoped features on top of this preset.
