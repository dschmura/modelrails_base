# Reshape 2: Per-workspace join_policy Spec

**Status:** Working draft. Not yet implemented. Tracks back to [#181](https://github.com/dschmura/modelrails_base/issues/181). Builds on Reshape 1 ([#184](https://github.com/dschmura/modelrails_base/pull/184), [#192](https://github.com/dschmura/modelrails_base/pull/192)).

## Goal

Add per-workspace control over *how* a user joins, layered on the instance-level posture (Solo-default / Single-tenant / Open SaaS). Introduce a `Workspace#join_policy` enum (starting with `invite` + `open_link`), a `WorkspaceJoinLink` model for shareable bearer links, and the instance-level `permitted_join_strategies` allowlist (the operator ceiling from #181).

This is the slice that **opens the Open SaaS preset** in `app/docs/presets.md`.

## Recommended split: 2a then 2b

Reshape 2 has a natural fault line worth respecting per the smaller-PR preference:

| Slice | Scope | Risk | Touches the auth gate? |
|---|---|---|---|
| **2a** | `join_policy` enum + `WorkspaceJoinLink` + `Workspace#admit` extraction + Flow A (*existing* user self-join via link) + `permitted_join_strategies` ceiling + workspace settings UI | Contained: authenticated self-join only | No |
| **2b** | Flow B (*new* user via link — link opens the signup gate) + `SignupPolicy.workspace_join_acceptable?` + new-user claim-on-verify analog to the invitation flow | Touches `SignupPolicy` + the registration flow | **Yes** |

Build 2a first; it's most of the value for the Notion/Figma-style multi-workspace case (existing users juggle workspaces, share links). 2b unlocks the public-SaaS / class-code-for-new-users case — bigger architectural extension, deserves its own PR and review.

This document specs **both** so the contract is whole; the implementation lands in two atomic PRs.

---

## Decision 1: Schema

### Workspace#join_policy

```ruby
# migration
add_column :workspaces, :join_policy, :string, null: false, default: "invite"
add_index  :workspaces, :join_policy
```

```ruby
# Workspace
enum :join_policy, { invite: "invite", open_link: "open_link" }, default: "invite"

# Hard guard: personal workspaces are never self-joinable, regardless of policy.
validate :personal_workspaces_are_invite_only

# Plus: validate against the instance allowlist (TenancyConfig / SignupPolicy)
validate :join_policy_must_be_permitted_by_instance
```

### WorkspaceJoinLink (new model)

```ruby
# migration
create_table :workspace_join_links do |t|
  t.references :workspace, null: false, foreign_key: true
  t.references :created_by, null: false, foreign_key: { to_table: :users }
  t.string :token, null: false
  t.datetime :revoked_at
  t.timestamps
end
add_index :workspace_join_links, :token, unique: true
add_index :workspace_join_links, [:workspace_id, :revoked_at]
```

```ruby
class WorkspaceJoinLink < ApplicationRecord
  # Rails-canonical stored-token primitive: auto-populates a URL-safe token
  # on create (SecureRandom.base58(24)), and gives us `regenerate_token` for
  # free — exactly what the atomic-rotate UX wants.
  has_secure_token :token

  belongs_to :workspace
  belongs_to :created_by, class_name: "User"

  scope :active, -> { where(revoked_at: nil) }

  def revoked? = revoked_at.present?
  def revoke! = update!(revoked_at: Time.current)
end
```

**Why `has_secure_token` and not `generates_token_for`?** `generates_token_for` is signed-stateless — perfect for the email-verification one-shot we shipped in #178, but unrevocable. Join links must be revocable for rotation; that requires a stored token + `revoked_at`. `has_secure_token` is the Rails primitive for that case.

**Deliberate v1 simplifications** (Chris Oliver pragma — add when a real need surfaces):

- No expiry — links live until revoked.
- No max-uses — links accept any number of joiners.
- No role-per-link — joiners get the workspace's default self-join role (see Decision 4).
- Multiple active links per workspace allowed at the *model* layer; the *UI* exposes one at a time (rotation = create new + revoke previous), but the schema supports audit trail.

### Why a stored token, not `generates_token_for`?

Verification tokens are signed-stateless because they're one-use and time-bound (#178). **Join links must be revocable**, which signed-stateless can't express. Stored tokens with a `revoked_at` column are the right primitive here.

---

## Decision 2: The `Workspace#admit` extraction (Kent Beck again)

The membership-grant logic — lock, find-existing-or-undiscard-or-capacity-check-or-create, with the `:shared` reconciliation from #192 — currently lives in `Invitation#accept_workspace_invitation!`. Both Flow A (open-link self-join) and the invitation flow need the same logic.

**Extract first** (behavior-preserving refactor), **then add the link-flow caller**:

```ruby
class Workspace
  # The single membership-grant entry point. Handles locking, capacity,
  # discarded-reactivation, and (under :shared) role reconciliation.
  def admit(user, role:)
    transaction do
      lock!
      existing = memberships.find_by(user: user)
      if existing&.discarded?
        existing.undiscard!
      elsif existing && !existing.discarded?
        if TenancyConfig.shared?
          existing.update!(role: role) unless existing.role_id == role.id
        else
          raise ActiveRecord::RecordInvalid.new(self), "User is already a member"
        end
      else
        raise ActiveRecord::RecordInvalid.new(self), "Workspace is at capacity" if memberships.kept.count >= max_members
        memberships.create!(user: user, role: role)
      end
    end
  end
end
```

Then `Invitation#accept_workspace_invitation!` collapses to:

```ruby
def accept_workspace_invitation!(user)
  invitable.admit(user, role: role)
end
```

And `Workspaces::JoinsController#create` calls `workspace.admit(Current.user, role: default_self_join_role)`.

This is the *second data point* we waited for to justify the abstraction (Sandi Metz lens) — now there are two callers, the strategy extraction earns its keep.

---

## Decision 3: Instance ceiling — `permitted_join_strategies`

The "third toggle" from #181's design record. Different `:invite_only` instances want different subsets (internal-tool wants `:domain` allowed; education wants `:open_link` allowed; regulated enterprise wants nothing self-serve).

```ruby
# config/application.rb
config.x.signup.permitted_join_strategies =
  ENV.fetch("SIGNUP_PERMITTED_JOIN_STRATEGIES", "invite").split(",").map(&:to_sym)

# config/initializers/signup.rb — validate at boot
valid_strategies = %i[invite open_link]  # 2a; add :domain in Reshape 3
unknown = Rails.configuration.x.signup.permitted_join_strategies - valid_strategies
raise "Unknown SIGNUP_PERMITTED_JOIN_STRATEGIES: #{unknown.join(', ')}" if unknown.any?
```

Defaults to `[:invite]` — preserves Solo-default exactly (no behavior change). Operators opt in to `open_link` by setting `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link`.

**Defense in depth — two enforcement points:**

1. **Validation** on `Workspace#join_policy_must_be_permitted_by_instance` — admins can't *set* a strategy the instance doesn't permit.
2. **Controller / model guard** in `Workspace#open_join?` — rejects joins via a non-permitted strategy even if the workspace somehow has that policy set (e.g. via raw SQL).

---

## Decision 4: Default role for self-join

Pinned to `member` at v1, same reasoning as Reshape 1 (industry convention; lowest privilege; safer default). Defer per-workspace / per-link role customization until asked.

```ruby
class Workspace
  def default_self_join_role
    Role.find_by!(slug: "member", workspace_id: nil)
  end
end
```

---

## Decision 5: Personal-workspace hard guard

Personal workspaces are **never** open-joinable, regardless of `join_policy`:

```ruby
def open_join?
  open_link? &&
    !personal? &&
    SignupPolicy.permits_strategy?(:open_link)
end

private

def personal_workspaces_are_invite_only
  return unless personal? && !invite?
  errors.add(:join_policy, :personal_must_be_invite)
end
```

This catches three failure modes at once: model validation (admin can't set), method guard (controller / model can't dispatch), and never-set-by-construction (personal workspaces seed with `invite`).

---

## Decision 6: Flow A — existing user self-join via link

**Route:**

```ruby
# config/routes.rb
resources :workspaces, param: :slug do
  resources :join_links, only: [:create, :destroy], controller: "workspaces/join_links"
  resource  :join,       only: [:create],           controller: "workspaces/joins"
end
```

A user visits `/workspaces/acme/join/:link_token` (or similar — TBD whether the token goes in the URL or POST body for shareability).

**Controller:**

```ruby
class Workspaces::JoinsController < ApplicationController
  def create
    workspace = Workspace.find_by!(slug: params[:workspace_slug])
    link = workspace.join_links.active.find_by!(token: params[:token])

    raise Pundit::NotAuthorizedError unless workspace.open_join?

    workspace.admit(Current.user, role: workspace.default_self_join_role)
    redirect_to workspace_path(workspace), notice: t(".success")
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: t(".invalid_or_revoked")
  rescue ActiveRecord::RecordInvalid => e  # capacity / already-member
    redirect_to root_path, alert: e.message
  end
end
```

**Pundit:**

`WorkspaceJoinLinkPolicy#create?` and `#destroy?` — owner/admin only (existing `manage_settings` permission). Anyone authenticated can use a link to join (no policy gate beyond `workspace.open_join?`).

---

## Decision 7: Flow B — new user via link (Reshape 2b, the architectural extension)

The link doubles as the account-gate opener under `:invite_only` instances. This is the part that touches `SignupPolicy`.

**`SignupPolicy` extension:**

```ruby
def self.allows_signup?(invitation_token: nil, join_token: nil)
  config_allows_signup? ||
    invitation_acceptable?(invitation_token) ||
    workspace_join_acceptable?(join_token)
end

def self.workspace_join_acceptable?(token)
  return false if token.blank?
  link = WorkspaceJoinLink.active.find_by(token: token)
  return false if link.nil?
  link.workspace.open_join?  # composes the per-workspace + instance-ceiling check
end
```

**Flow:**

1. New user visits the join link.
2. `Workspaces::JoinsController#create` notices unauthenticated → stashes `session[:pending_join_token]` and redirects to `/sign-up`.
3. `ApplicationController#signups_open?` now also checks `session[:pending_join_token]` → gate opens.
4. Registration completes (deferred consumption pattern from #175 — token parked on the email Authentication).
5. Email verification → `Account::ConnectedAccountsController#verify` → claim the parked join token → `workspace.admit(user, role: default_self_join_role)`.

The parking + claim mechanism is **structurally identical to invitation deferral**. We extract a common `pending_claim_token` column on Authentication (renaming `pending_invitation_token`) — or add a sibling column `pending_join_link_token`. Lean: sibling column to keep the two flows distinct in the schema.

**Why 2b is its own PR:** it touches `SignupPolicy`, `ApplicationController`, the registration flow, the Authentication model, and the verify flow — all critical paths covered by the #174–#192 security work. Combining it with 2a would risk masking integration bugs between the two extensions.

---

## Decision 8: UI

**Under `:personal` posture** (Solo-default), `join_policy` is meaningful — surface a setting.

**Under `:shared` posture** (Single-tenant), `join_policy` is moot (one workspace, no separate join story). Suppress the UI entirely.

**Workspace Settings page** (`workspaces/settings#edit`) gains a "Join policy" section, gated on:

```erb
<% if TenancyConfig.personal? && SignupPolicy.permits_any_open_strategy? %>
  <!-- Join policy section: radio for invite vs open_link; if open_link selected,
       show active link with Copy / Rotate / Revoke -->
<% end %>
```

The Rotate / Revoke actions hit `Workspaces::JoinLinksController#create / #destroy`. Copy-to-clipboard uses a small Stimulus controller (existing pattern in the codebase).

**Accessibility (Léonie lens):** the link-display element needs an `aria-live="polite"` region for "Copied!" feedback; revoke action needs confirmation; state-change announcements when policy flips.

**No `:create_org` UI yet** — `:create_org` is Reshape 3+.

---

## Test plan (TDD order)

### Reshape 2a

1. `spec/models/workspace_spec.rb` — `join_policy` enum, `#open_join?` predicate, personal-workspace hard guard, `permitted_join_strategies` validation, `#admit` (extracted) round-trips existing Invitation behavior.
2. `spec/models/workspace_join_link_spec.rb` — token uniqueness, `active` scope (not revoked), `revoke!` setter.
3. `spec/models/invitation_spec.rb` — `#accept_workspace_invitation!` continues to pass (now delegates to `Workspace#admit` — behavior-preserving refactor).
4. `spec/requests/workspaces/join_links_spec.rb` — owner/admin can create/revoke; member can't; instance ceiling blocks setting `:open_link` when not permitted.
5. `spec/requests/workspaces/joins_spec.rb` — authenticated user joins via active link (becomes Member); revoked link 404s; personal workspace 401s even with link; capacity respected; already-member is no-op (under `:shared`) / error (under `:personal`).
6. `spec/system/open_link_self_join_spec.rb` — end-to-end: admin enables open_link, copies link, second user visits + joins.

### Reshape 2b

7. `spec/lib/signup_policy_spec.rb` — `workspace_join_acceptable?` returns true only for an active link of an open-join workspace.
8. `spec/requests/registrations_spec.rb` — under `:invite_only` instance, signup with `pending_join_token` in session is permitted; user is created with the parked token on their email Authentication.
9. `spec/requests/account/connected_accounts_spec.rb` — verify claims the parked join token; user is admitted to the workspace as Member.
10. `spec/system/open_link_new_user_signup_spec.rb` — end-to-end: unauthenticated visit join link → register → verify email → land in workspace.

---

## Documentation updates (each in the corresponding PR)

- **`app/docs/presets.md` Open SaaS section** starts to fill in. Reshape 2a documents `:personal` + `permitted_join_strategies=[invite,open_link]` (the prosumer-with-shareable-links shape). Reshape 2b extends it with the new-user signup-via-link flow.
- **`app/docs/workspaces.md`** gains a "Join policies" section under or near the "Invitations" heading. Distinguishes invite-only (current) from open-link (new).
- **CHANGELOG `[Unreleased]`** — `### Added`: per-workspace join_policy and shareable join links (2a). Same for 2b when it lands.

---

## Build sequence

### Reshape 2a (PR #1)

1. Migration: add `join_policy` to workspaces; create `workspace_join_links` table.
2. **Extract `Workspace#admit`** (behavior-preserving refactor); `Invitation#accept_workspace_invitation!` delegates. Full suite stays green.
3. `Workspace` enum, `#open_join?`, validations (personal-guard + permitted_strategies).
4. `WorkspaceJoinLink` model + `active` scope.
5. `permitted_join_strategies` instance config + initializer validation.
6. Pundit: `WorkspaceJoinLinkPolicy` (owner/admin gates).
7. `Workspaces::JoinLinksController` (create/destroy).
8. `Workspaces::JoinsController#create` (Flow A only — assumes authenticated user).
9. Settings UI for join_policy + link display (Stimulus copy-to-clipboard, accessibility).
10. Specs (TDD).
11. Doc updates: presets.md, workspaces.md, CHANGELOG.

### Reshape 2b (PR #2)

12. `SignupPolicy.workspace_join_acceptable?` + `permits_strategy?` predicates.
13. `Authentication#pending_join_link_token` column (migration) + `claim_pending_join_link!` analog to `claim_pending_invitation!`.
14. `ApplicationController#signups_open?` reads `session[:pending_join_token]` too.
15. `Workspaces::JoinsController` unauthenticated branch (stash token, redirect to signup).
16. Registration flow: parks `pending_join_link_token` on the email Authentication.
17. `Account::ConnectedAccountsController#verify` claims the join token (next to claim_pending_invitation).
18. Specs (TDD).
19. Doc updates: presets.md Open SaaS expanded; CHANGELOG.

---

## Risks / open questions

1. **Token in URL vs POST body.** Shareable links want the token in the URL (`/workspaces/acme/join/<token>`) so they can be copy-pasted. URL exposure (referer headers, browser history) is the standard tradeoff. *Lean: URL, matching how invitation links already work.*
2. **One active link per workspace, or multiple?** Schema supports multiple (audit trail of rotations); UI exposes one at a time. *Lean: that asymmetry — schema permissive, UI restrictive.*
3. **Rotation UX.** When admin clicks "Rotate", do we (a) revoke the old + create new in one click, or (b) two-step (create new, then prompt to revoke old)? *Lean: (a) atomic — "rotate" is the explicit user intent.*
4. **What does the "Settings → Join policy" UI look like under `:invite_only` instance with `permitted_join_strategies=[invite]`?** The radio for `open_link` is disabled / hidden with an explanation ("Open join links are not permitted on this deployment"). *Decide: hide entirely, or show disabled-with-tooltip explanation?*
5. **Should Flow A require email verification?** A signed-in user already verified their email at signup; Flow A doesn't re-verify. *Lean: no — they're already verified. The link is the trust anchor.*
6. **Capacity behavior on link-self-join.** Current `admit` raises RecordInvalid at capacity. Should the link page show a "this workspace is full" message instead? *Lean: catch the exception in the controller, show the i18n message — clearer UX than the bare error.*
7. **Should `WorkspaceJoinLink` count toward any audit log / activity feed?** The codebase has a `Trackable` concern. *Lean: yes — create / revoke events on join links are workspace-admin actions worth logging.*

---

## Out of scope (later reshapes or never)

- `:domain` strategy (Reshape 3 — verified-email-domain auto-join, biggest B2B unlock).
- `:request` strategy (request → admin approves, community-product pattern).
- `:provisioned` strategy (SCIM / SSO JIT, regulated enterprise).
- Public workspace directory / discoverability (Discord-style listing).
- Per-link role / expiry / max-uses (defer to v2 of `WorkspaceJoinLink`).
- The `:create_org` onboarding flow (Reshape 3+).
