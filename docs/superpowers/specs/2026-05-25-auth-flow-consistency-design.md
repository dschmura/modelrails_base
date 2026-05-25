# Auth-Flow Consistency Follow-Up — Design Spec

**Goal:** Close two gate gaps that surfaced when the invite-required signup PR shipped. OAuth signups for invited users (Branch 3 of `OmniauthCallbacksController#create`) currently pass the gate but never consume the invitation, leaving the new user without their inviting workspace membership. Magic link new-user creation (`MagicLinkCallbacksController#create`) bypasses the gate entirely and never consumes invitations. Extract the now-three transactional signup paths into a single `Signupable` controller concern so the atomicity guarantee (user save + invitation acceptance succeed or fail together) lives in one place.

**Scope:** One new controller concern (`Signupable`), three controller refactors/extensions (`RegistrationsController` refactor, `OmniauthCallbacksController` extension, `MagicLinkCallbacksController` extension), one new initializer spec (CSP form-action coverage), one new partial render (OAuth buttons on closed page), and accompanying unit + request + system spec coverage.

**Builds on:** `docs/superpowers/specs/2026-05-24-invite-required-signup-design.md` (the parent feature, shipped as PR #172).

---

## Motivation

The invite-required signup feature shipped with a 3×3 matrix problem that wasn't visible until manual testing surfaced it:

| Signup Path | Gate Enforced (invite-only) | Consumes Invitation? | Joins Inviting Workspace? |
|---|---|---|---|
| **Email/password** (`RegistrationsController#create`) | ✅ Yes (Task 8) | ✅ Yes (Task 9 transactional) | ✅ Yes |
| **OAuth new user** (`OmniauthCallbacksController#handle_new_user_oauth`) | ✅ Yes (Task 10) | ❌ **No** | ❌ **No** |
| **Magic link new user** (`MagicLinkCallbacksController#create`) | ❌ **No** | ❌ **No** | ❌ **No** |

The Email/password row got the full Task 9 treatment. OAuth was gated but the invitation-consumption logic was never wired through `handle_new_user_oauth`. Magic link new-user creation slipped past gate-design entirely because the code path is only reachable in edge cases (e.g., a deleted user clicking an old token link) but is structurally present and represents a complete bypass of the invite-only model.

Adjacent: while manually testing the OAuth flow, a CSP `form-action 'self'` directive blocked the cross-origin redirect to Google's consent screen — a bug class that no test in the suite caught because Playwright bypasses CSP enforcement. A source-level initializer spec catches this regression class going forward.

## Non-Goals

- **Per-recipient rate limiting for magic links.** The current `MagicLinksController` uses `rate_limit to: 5, within: 3.minutes`, which is per-IP and less thorough than the `EmailRecipientThrottle` pattern (per-recipient per-kind). Worth harmonizing some day, but not part of this fix. Captured as a follow-up.
- **Removing the magic link new-user path.** The path will be kept and properly gated (user direction during brainstorm). The alternative (delete the path entirely) was considered but rejected because the user wants magic link to remain a viable third signup vector for future flows that wire magic-link tokens into invitation emails.
- **Per-workspace invite-only mode.** App-level only, same as the parent spec.
- **Refactoring `MagicLinkToken.consume!`.** The existing atomic consume semantics are preserved by this design; the token consumption moves INSIDE the new transaction but its own atomicity is unchanged.
- **Email-match validation on `Invitation#accept!`.** Aaron Patterson's panel review flagged that the unverified-email OAuth branch accepts an invitation without verifying the OAuth-returned email matches the invitation's `email`. In practice the existing OAuth CSRF state token makes the threat model narrow (an attacker can't replay a callback URL across sessions), but the conceptual gap remains. Deferred to a security review pass — would touch the `Invitation` model and several other entry points, larger than this follow-up.
- **Refactoring `Invitation#accept!` for nested-transaction safety.** Aaron noted that `Invitation#accept!` runs its own `transaction { lock!; ... }` internally, which Rails converts to a SAVEPOINT when nested inside `commit_signup_atomically`'s outer transaction. SQLite's row-locking inside savepoints is under-specified across minor SQLite versions. The Task 9 implementation already nests transactions this way and 1995 tests pass, so the risk is theoretical. Trigger to revisit: production load surfaces a savepoint deadlock; would refactor `accept!` to accept `already_in_transaction:` and skip its inner transaction.
- **Behavioral (not config-level) CSP test.** Joël Quenneville noted that the proposed CSP spec asserts the configuration matches a host map, not that the actual OAuth flow succeeds under enforcement. A behavioral test would require a system spec that exercises the cross-origin redirect with CSP enforced — but Playwright bypasses CSP per the project's `feedback_playwright_bypasses_csp.md` memory, so the config-level test is the highest fidelity test available in this codebase today. Trigger to revisit: Playwright gains CSP enforcement, OR a non-Playwright system test stack arrives.

---

## Design decisions (locked during brainstorming)

| Decision | Choice | Reasoning |
| -------- | ------ | --------- |
| Magic link new-user fate | Keep + properly gate | User wants magic link to remain a viable third signup vector. Future-proofs invitation flows that may include magic-link tokens. |
| Shared-logic structure | `Signupable` controller concern | Lifecycle-shaped (touches session, flash, transactions) rather than data-shaped. Concerns are the right abstraction here. Matches existing `Authenticatable`/`Tenanted` precedent. |
| Concern API shape | Block-based atomicity helper: `commit_signup_atomically(user, &block) → bool` | Atomicity is the genuinely-shared concern; everything else (verification email behavior, redirect targets, flash text) is legitimately path-specific. Block pattern keeps controllers distinctive about post-commit. |
| In-scope adjacencies | CSP source-level spec + OAuth buttons on closed page | Both causally related to the gap fix. CSP spec prevents the exact bug class we just hit. Closed page OAuth buttons gives existing users a one-click recovery path. |
| Out-of-scope | Magic link rate limit harmonization | Speculative/defensive, no user-visible bug. Deferred. |
| OAuth unverified-email branch | Also calls `accept_pending_invitation!` | The user doesn't sign in yet (verification pending), but the invitation shouldn't be orphaned while they wait. |

---

## Architecture

### Three signup paths, one shared atomic core

```text
                       ┌────────────────────────────────────────┐
                       │   Signupable concern                   │
                       │   ───────────────────────────────────  │
                       │   commit_signup_atomically(user)       │
                       │     ApplicationRecord.transaction      │
                       │       user.save!                       │
                       │       yield(user)                      │
                       │       accept_pending_invitation!       │
                       │     rescue Invitation::NotAcceptable   │
                       │       → flash + false                  │
                       │     rescue ActiveRecord::RecordInvalid │
                       │       → false (caller reads @errors)   │
                       │                                        │
                       │   accept_pending_invitation!           │
                       │     read session[:token]               │
                       │     Invitation.find_by&.accept!        │
                       │     session.delete on success only     │
                       └─────────────┬──────────────────────────┘
                                        │
            ┌───────────────────────────┼──────────────────────────────┐
            ▼                           ▼                              ▼
RegistrationsController       OmniauthCallbacks                MagicLinkCallbacks
      #create                       #create                          #create
  (existing/refactored)    (branch 3 verified-email block        (NEW gate +
                            extended; unverified-email branch    transactional wrap)
                            also calls accept_pending_invitation!)
```

### The atomicity contract

`commit_signup_atomically(user, &block)`:

1. Opens `ApplicationRecord.transaction`.
2. Calls `user.save!`. If validation fails, raises `RecordInvalid` (rescued below).
3. Yields the user to the block. The block does path-specific in-transaction work — creating authentications, generating verification tokens, consuming external tokens.
4. Calls `accept_pending_invitation!(user)` to consume any pending invitation from the session. If the invitation is no longer acceptable (race), `Invitation#accept!` raises `Invitation::NotAcceptable` and the transaction rolls back.
5. On commit: returns `true`.
6. On `Invitation::NotAcceptable`: sets `flash.now[:alert]` to the "invitation_consumed" message and returns `false`.
7. On any other `RecordInvalid` (e.g., model validation failure): returns `false`. Does NOT set flash — the caller renders the form and reads `@user.errors` directly.

The block is expected to be small. Anything that doesn't need transactional atomicity (mailer enqueuing, session start, redirect, response rendering) stays in the calling controller. Exceptions NOT inheriting from `RecordInvalid` (e.g., `ArgumentError`, `KeyError`, network errors in mailers — though mailers should be OUTSIDE the transaction anyway) propagate beyond `commit_signup_atomically` to the controller's default error handling.

### `accept_pending_invitation!(user)` semantics

```ruby
def accept_pending_invitation!(user)
  token = session[:pending_invitation_token]
  return if token.blank?

  invitation = Invitation.find_by(token: token)
  return if invitation.nil?

  invitation.accept!(user)
  session.delete(:pending_invitation_token)
end
```

- Token is READ from session (not deleted yet).
- If no token is present, the method is a no-op (returns `nil`). This is the "user signing up without an invitation in `:open` mode" case — perfectly legitimate.
- If the token doesn't match any invitation, `find_by` returns `nil` and we return early. Tampered tokens are silently ignored at this layer (the gate already rejected them upstream).
- If the invitation exists but is not acceptable (already accepted, expired, declined, revoked), `Invitation#accept!` raises `Invitation::NotAcceptable`. The transaction rolls back. **The session token remains** because `session.delete` is the LAST line, only reached on successful acceptance.
- On success, `session.delete(:pending_invitation_token)` runs as the final step — the token is single-use only on successful consumption. This is the revised behavior per Aaron Patterson's panel review (originally token was deleted first unconditionally; that left failed-acceptance users stranded with no token to retry).

---

## Implementation

### `Signupable` concern (new — `app/controllers/concerns/signupable.rb`)

```ruby
module Signupable
  extend ActiveSupport::Concern

  # Runs user creation and invitation acceptance in a single transaction.
  # The block receives the saved user and should perform any in-transaction
  # work (creating authentications, generating verification tokens, etc.).
  # Exceptions other than Invitation::NotAcceptable and ActiveRecord::RecordInvalid
  # will propagate beyond this method.
  #
  # Returns true on commit, false on validation failure or invitation race.
  # Sets flash.now[:alert] only on InvitationNotAcceptable (so the caller
  # can rely on @user.errors for model-validation failures).
  def commit_signup_atomically(user, &block)
    ApplicationRecord.transaction do
      user.save!
      yield(user) if block_given?
      accept_pending_invitation!(user)
    end
    true
  rescue Invitation::NotAcceptable
    flash.now[:alert] = I18n.t("registrations.create.invitation_consumed")
    false
  rescue ActiveRecord::RecordInvalid
    false
  end

  # Consumes the session's pending invitation token. Idempotent if no token
  # is present. Raises Invitation::NotAcceptable if the invitation is no
  # longer acceptable (handled by commit_signup_atomically).
  #
  # The session token is deleted ONLY on successful acceptance. If the
  # transaction rolls back for any reason (validation failure, race, crash),
  # the token remains in the session for the user to retry.
  def accept_pending_invitation!(user)
    token = session[:pending_invitation_token]
    return if token.blank?

    invitation = Invitation.find_by(token: token)
    return if invitation.nil?  # tampered token; gate already rejected upstream

    invitation.accept!(user)
    session.delete(:pending_invitation_token)
  end
end
```

**`Invitation::NotAcceptable` (new exception)** — defined inside `app/models/invitation.rb`:

```ruby
class Invitation < ApplicationRecord
  class NotAcceptable < ActiveRecord::RecordInvalid; end

  # ... existing code ...

  def accept!(user)
    with_lock do
      raise NotAcceptable.new(self), "Invitation no longer acceptable" unless acceptable?
      # ... existing acceptance logic continues ...
    end
  end
end
```

Subclassing `ActiveRecord::RecordInvalid` means `Invitation::NotAcceptable` is still rescued by any code that catches `RecordInvalid` (backward-compatible with the existing `accept!` callers that don't know about this exception). The concern catches the more specific class first, then falls through to generic `RecordInvalid` for everything else.

### `RegistrationsController#create` (refactor — replaces Task 9's inline pattern)

```ruby
def create
  unless signups_open?
    render :closed, status: :unprocessable_entity
    return
  end

  @user = User.new(registration_params)
  authentication = nil

  success = commit_signup_atomically(@user) do |user|
    authentication = user.authentications.create!(
      provider: "email",
      uid: user.email_address
    )
    authentication.generate_verification_token!
  end

  if success
    AuthenticationMailer.verification_email(authentication).deliver_later
    start_new_session_for(@user)
    redirect_to root_path, notice: t(".success")
  else
    render :new, status: :unprocessable_entity
  end
end
```

Add `include Signupable` near the top of `RegistrationsController`. The existing private `accept_pending_invitation!` method is REMOVED (now provided by the concern).

### `OmniauthCallbacksController` (extend — wire concern into both branches of `handle_new_user_oauth`)

Add `include Signupable` near the top. Then in `handle_new_user_oauth`:

```ruby
def handle_new_user_oauth(auth_hash)
  unless signups_open?
    redirect_to new_registration_path,
                alert: t("registrations.closed.oauth_blocked"),
                status: :see_other
    return
  end

  if oauth_email_verified?(auth_hash)
    handle_verified_email_oauth(auth_hash)
  else
    handle_unverified_email_oauth(auth_hash)
  end
end

private

def handle_verified_email_oauth(auth_hash)
  @user = find_verified_user_by_email(auth_hash) || create_user_from_oauth(auth_hash)

  success = commit_signup_atomically(@user) do |user|
    user.authentications.create!(
      provider: auth_hash.provider,
      uid: auth_hash.uid,
      email: auth_hash.info.email,
      verified_at: Time.current
    )
  end

  if success
    start_new_session_for(@user)
    redirect_to root_path, notice: t("omniauth_callbacks.create.welcome")
  else
    redirect_to new_session_path, alert: t("omniauth_callbacks.create.failure")
  end
end

def handle_unverified_email_oauth(auth_hash)
  @user = create_user_from_oauth(auth_hash)
  pending_auth = nil

  success = commit_signup_atomically(@user) do |user|
    pending_auth = user.authentications.create!(
      provider: auth_hash.provider,
      uid: auth_hash.uid,
      email: auth_hash.info.email,
      verified_at: nil
    )
    pending_auth.generate_verification_token!
  end

  if success
    AuthenticationMailer.verification_email(pending_auth).deliver_later
    redirect_to new_session_path, notice: t("omniauth_callbacks.create.check_email")
  else
    redirect_to new_session_path, alert: t("omniauth_callbacks.create.failure")
  end
end
```

**Key change:** The unverified-email branch now ALSO calls `commit_signup_atomically` (which calls `accept_pending_invitation!`). The user doesn't sign in yet, but the invitation is consumed and they get the inviting workspace membership. When they eventually click the verification email, they're already a workspace member.

**Why consume invitation BEFORE email verification (DHH panel review concern):** The invitation token is single-use and lives in the session. If verification fails or the user never clicks the email link, the invitation is "consumed" but the user never completes signup — they can't retry without a new invitation. This is a deliberate trade-off: we accept that an abandoned OAuth signup leaves the inviter to issue a new invitation. The alternative (consume only after verification) would require persisting the pending invitation reference across the verification round-trip (probably as a column on `Authentication`), which is a substantially larger change. **The implementer should add an inline comment in `handle_unverified_email_oauth`** stating: "Invitation is consumed now even though sign-in is deferred until email verification. If verification never completes, the invitation is gone and a new one must be issued. See spec section X for rationale."

**For existing-user-via-OAuth (where `find_verified_user_by_email` returns a hit):** `commit_signup_atomically` is safe — `user.save!` on a persisted unchanged record is a no-op, the new authentication is created, and any pending invitation is consumed. Existing users WITH an invitation token in session get the workspace membership too. This is a UX improvement that falls out for free.

### `MagicLinkCallbacksController#create` (extend — NEW gate + concern integration)

Add `include Signupable` near the top. Then:

```ruby
def create
  token_record = MagicLinkToken.find_valid(params[:token])
  unless token_record
    redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
    return
  end

  unless signups_open?
    redirect_to new_registration_path,
                alert: t("registrations.closed.oauth_blocked"),
                status: :see_other
    return
  end

  @user = User.new(
    email_address: token_record.email,
    first_name: params[:user][:first_name],
    last_name: params[:user][:last_name]
  )

  token_consumed = false

  success = commit_signup_atomically(@user) do |user|
    # Inside this block, @user has just been saved by the concern. We now
    # attempt to consume the magic-link token. If a concurrent request
    # already consumed it (race), MagicLinkToken.consume! returns falsy,
    # we raise ActiveRecord::Rollback, and Rails unwinds the ENTIRE outer
    # transaction — the @user.save! is reverted. See note below on why
    # this is watertight despite Aaron Patterson's panel concern.
    token_consumed = MagicLinkToken.consume!(token_record.token)
    raise ActiveRecord::Rollback unless token_consumed

    user.authentications.create!(
      provider: "email",
      uid: user.email_address,
      verified_at: Time.current
    )
  end

  if success && token_consumed
    start_new_session_for(@user)
    redirect_to root_path, notice: t(".registered")
  elsif !token_consumed
    redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
  else
    @token = params[:token]
    @email = token_record.email
    render :new_registration, status: :unprocessable_entity
  end
end
```

**Note on ordering — why save-then-consume is safe (responding to Aaron Patterson's panel concern):** Aaron's review suggested calling `MagicLinkToken.consume!` BEFORE `user.save!` to "fail fast" and avoid even momentarily creating a User row. But the concern's API has `user.save!` BEFORE the block runs, so consume-first would require restructuring the concern (yield-pre-save vs yield-post-save) — which the other two controllers don't want. The save-then-consume ordering IS correct because `ApplicationRecord.transaction` + `ActiveRecord::Rollback` is watertight: when Tab B's consume returns false and we raise `Rollback`, Rails unwinds ALL writes since the transaction began — including the User row. The DB never sees a committed orphan. The "momentary User row" Aaron describes exists only inside the active transaction, not in any committed state another reader could observe. The pin test for this is "Tab B's race-on-token leaves no User row in the DB" — covered in the test plan.

**Note on `raise ActiveRecord::Rollback` vs `RecordInvalid`:** `ActiveRecord::Rollback` is the only exception class that ActiveRecord catches silently to roll back a transaction (Rails-blessed flow control for "abort cleanly, no error"). When the concern's rescue clauses (catching `Invitation::NotAcceptable` and `RecordInvalid`) miss this, the method returns `true` — but the `token_consumed` flag remains `false`, signaling the controller to route to `:invalid`. `Signupable` does NOT need to rescue `Rollback` because Rails handles it automatically.

The flag-checking after `commit_signup_atomically` is needed because we have four possible outcomes — success-with-consume, race-on-token, race-on-invitation, and model-validation-failure — and the boolean return alone can't distinguish them.

`MagicLinkCallbacksController#show` does NOT change. It already correctly handles the "user already exists, just sign them in" case and the "render new_registration form" case. The gate change only affects `#create` because that's where the User row gets persisted.

### CSP source-level spec (new — `spec/initializers/content_security_policy_spec.rb`)

```ruby
require "rails_helper"

RSpec.describe "Content Security Policy" do
  let(:policy) { Rails.application.config.content_security_policy }
  let(:form_action) { policy.directives["form-action"] }

  # When you add a new OAuth provider to OauthHelper::PROVIDER_CONFIG,
  # add the provider's consent-screen host to the hash below AND to
  # config/initializers/content_security_policy.rb's form_action directive.
  EXPECTED_OAUTH_HOSTS_BY_PROVIDER = {
    google_oauth2: "https://accounts.google.com",
    github:        "https://github.com"
  }.freeze

  it "allows form-action to every configured OAuth provider host" do
    OauthHelper::PROVIDER_CONFIG.each_key do |provider|
      expected_host = EXPECTED_OAUTH_HOSTS_BY_PROVIDER.fetch(provider) do
        raise <<~MSG.strip
          Missing CSP form-action host for OAuth provider :#{provider}.
          Add it to EXPECTED_OAUTH_HOSTS_BY_PROVIDER in this spec file:
            #{__FILE__}
          AND to config/initializers/content_security_policy.rb's
          policy.form_action call.
        MSG
      end
      expect(form_action).to include(expected_host),
        "CSP form-action must include #{expected_host} for OAuth provider #{provider}"
    end
  end

  it "always includes :self in form-action" do
    expect(form_action).to include("'self'")
  end
end
```

**On testing config vs behavior (responding to Joël Quenneville's panel concern):** Joël noted that this spec asserts the configuration matches a host map, not that the actual OAuth redirect succeeds under CSP enforcement. A truly behavioral test would require a system spec that exercises the cross-origin redirect WITH CSP enforced — but the project's existing Playwright stack bypasses CSP (per `feedback_playwright_bypasses_csp.md` memory). Until the system test stack gains CSP enforcement, this config-level spec is the highest-fidelity test available. It catches the regression class we just fixed (someone tightens CSP without thinking about OAuth) AND the additive class (someone adds a fourth provider without updating CSP). See "Non-Goals" for the deferred behavioral test trigger.

### OAuth buttons on closed page (modify — `app/views/registrations/closed.html.erb`)

Add a single line above the existing sign-in link block:

```erb
<%= render "shared/oauth_buttons" %>
```

The partial's `if oauth_enabled?` guard means it self-hides when no OAuth providers are configured. No additional logic needed.

---

## Testing strategy

### `spec/controllers/concerns/signupable_spec.rb` (new — unit-level)

Tests the concern in isolation by including it in an anonymous controller test class (per the `rails-controller-testing` pattern already established):

```ruby
describe Signupable do
  controller(ApplicationController) do
    include Signupable
    # ... test actions that exercise commit_signup_atomically and accept_pending_invitation!
  end

  describe "#commit_signup_atomically" do
    it "returns true and commits when block succeeds"
    it "returns false (and leaves flash empty) when user.save! raises RecordInvalid (model validation)"
    it "returns false AND sets flash[:alert] when invitation accept! raises Invitation::NotAcceptable (race)"
    it "Invitation::NotAcceptable is a subclass of ActiveRecord::RecordInvalid (backward compat)"
    it "rolls back user creation when block raises ActiveRecord::Rollback"
    it "consumes session pending_invitation_token on commit"
    it "clears session pending_invitation_token even when block raises Rollback"
  end

  describe "#accept_pending_invitation!" do
    it "is a no-op when no token in session"
    it "is a no-op when token does not match any invitation"
    it "raises Invitation::NotAcceptable when invitation is not acceptable"
    it "does NOT delete session token when invitation raises NotAcceptable (retry preserved)"
    it "DELETES session token only after successful accept!"
    it "calls Invitation#accept!(user) and consumes the token from session"
  end
end
```

### `spec/requests/registrations_spec.rb` (regression after refactor)

All existing tests must still pass. The race-condition test from Task 9 specifically:

- User creation rolls back when `accept!` raises during the transaction
- Flash includes invitation_consumed message
- 422 response

If any of these break after the refactor, the concern's API doesn't match the controller's expectations and the refactor is wrong.

### `spec/requests/omniauth_callbacks_spec.rb` (new cases)

- **New-user OAuth signup WITH invitation token, verified email** → User created AND Authentication created AND invitation reload is `:accepted` AND user has membership in inviting workspace
- **New-user OAuth signup WITH invitation token, unverified email** → User created, pending Authentication created, verification email sent, invitation reload is `:accepted` (consumed even though user not signed in yet)
- **New-user OAuth signup WITH expired/consumed invitation token in session (race)** → User NOT created (transaction rolled back), 303 redirect to sign-in with failure alert
- **Existing-user OAuth sign-in WITH invitation token in session** → User signed in normally AND invitation accepted AND new workspace membership added (the "fall-out-for-free" UX improvement)
- All existing OAuth callback tests still pass (no regressions on the wrap pattern)

### `spec/requests/magic_link_callbacks_spec.rb` (new cases)

- **New-user magic-link signup in invite_only mode WITHOUT invitation token** → 303 redirect to `new_registration_path` with closed alert; no User created; magic-link token NOT consumed
- **New-user magic-link signup WITH valid invitation token in session** → User created, invitation accepted, workspace membership exists, token consumed, signed in
- **New-user magic-link signup with concurrent token consume (race)** → User NOT created, redirect to sign-in with invalid alert, invitation NOT consumed
- **Existing-user magic-link sign-in** (uses `#show`, not `#create`) → unchanged behavior

### `spec/initializers/content_security_policy_spec.rb` (new)

Per the implementation section above. Loops over `OauthHelper::PROVIDER_CONFIG` and asserts each provider has a corresponding host in CSP `form-action`.

### `spec/system/invite_only_signup_spec.rb` (extend)

Add one scenario: invited user mocks Google OAuth via `OmniAuth.config.mock_auth`, clicks the OAuth button from the registration form, ends up signed in AND with workspace membership. Existing scenarios remain.

### `spec/factories/magic_link_tokens.rb` (new — per Joël Quenneville's panel review)

The project currently has no factory for `MagicLinkToken`. Request specs that exercise the magic-link signup path would have to build tokens inline (`MagicLinkToken.create!(email: ..., token: SecureRandom.hex)`). Inline construction is brittle: if the model adds validations, scopes, or computed columns, every spec breaks.

```ruby
FactoryBot.define do
  factory :magic_link_token do
    email { Faker::Internet.email }
    token { SecureRandom.hex(32) }

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :expired do
      created_at { 1.day.ago }
      # Add expires_at override if the model uses a column rather than a window
    end
  end
end
```

The implementer must reconcile the trait against the actual `MagicLinkToken` model — column names, validation rules, and what makes a token "expired" (column or scope-based) may differ from what's assumed here.

### Shared examples for the 3×3 matrix (per Joël Quenneville's panel review)

The three request specs (`registrations_spec.rb`, `omniauth_callbacks_spec.rb`, `magic_link_callbacks_spec.rb`) will assert the same three behaviors per path:

1. Gate enforces (no token in session → redirect or render closed)
2. Invitation consumed (token in session → invitation marked accepted after signup)
3. Workspace membership exists (user joined inviting workspace)

Extract into `spec/support/shared_examples/invited_signup_atomicity.rb`:

```ruby
RSpec.shared_examples "an invited signup path that consumes invitations" do
  it "creates the user, consumes the invitation, and adds workspace membership" do
    invitation = create(:invitation, invitable: workspace, email: signup_email)
    post accept_invitation_path(token: invitation.token)

    expect { perform_signup }.to change(User, :count).by(1)

    expect(invitation.reload).to be_accepted
    new_user = User.find_by(email_address: signup_email)
    expect(new_user.workspaces).to include(workspace)
  end

  it "does not consume the invitation if signup fails (validation)" do
    invitation = create(:invitation, invitable: workspace, email: signup_email)
    post accept_invitation_path(token: invitation.token)

    # Caller defines `perform_failing_signup` for this case
    expect { perform_failing_signup }.not_to change(User, :count)
    expect(invitation.reload).to be_pending
  end
end
```

Each request spec includes the shared example with `perform_signup` and `perform_failing_signup` defined as `let` bindings that POST to its respective endpoint. This eliminates ~60 lines of duplicated test scaffolding across the three specs.

---

## Edge cases pinned by explicit specs

1. **Token cleanup is CONDITIONAL on acceptance success** (revised per Aaron Patterson's panel review). `session.delete(:pending_invitation_token)` runs ONLY after `invitation.accept!(user)` returns successfully. A failed acceptance (race, validation, crash, or transaction rollback) leaves the token in the session — the user can retry, OR an admin can issue a fresh invitation knowing the original is still technically claimable until it expires. The token is still single-use at the DB level (acceptance flips status to `:accepted`), so retry doesn't grant double membership.
2. **Existing user OAuth with invitation token still works.** Branch 1 of `OmniauthCallbacksController#create` (existing-identity sign-in) is untouched and does NOT consume invitations. Only Branch 3 (new-user, via `handle_new_user_oauth`) consumes them. An existing user with a pending invitation must click an OAuth provider that hits `handle_new_user_oauth`'s "user exists by email" branch.
3. **Branch 2 (signed-in user linking new OAuth provider) is untouched.** No invitation logic added there.
4. **Magic link gate does NOT affect `#show` for existing users.** Only `#create` (which builds a new User) consults `signups_open?`. Existing users clicking magic links can always sign in.
5. **`MagicLinkToken.consume!` inside the transaction.** Token consumption moves into the outer transaction. Its atomic update semantics (`UPDATE ... WHERE consumed_at IS NULL`) are unchanged. If the token was already consumed, the inner `consume!` returns falsy and we explicitly `raise ActiveRecord::Rollback` to abort the transaction without propagating.
6. **`Invitation::NotAcceptable` subclass of `RecordInvalid`** preserves backward compatibility for any existing `rescue ActiveRecord::RecordInvalid` callers of `Invitation#accept!` while letting `Signupable` rescue the specific class and set the appropriate flash. Pinned by a unit spec on the exception's inheritance chain.

---

## Out-of-scope follow-ups (captured for later)

- **Magic link per-recipient rate limiting.** Current per-IP `rate_limit` could be supplemented by `EmailRecipientThrottle` for defense in depth. Trigger: real abuse case or a security review request.
- **Magic-link-in-invitation-emails feature.** If invitation emails ever include a magic link token (faster onboarding for invited users), this design's gate + invitation consumption already covers it. No further work needed at gate time.
- **`OauthCredentials` POPO refactor** (from the parent spec) still deferred.
- **Per-workspace invite-only mode** (from the parent spec) still deferred.

---

## Acceptance checklist

- `Signupable` concern exists at `app/controllers/concerns/signupable.rb` with `commit_signup_atomically` and `accept_pending_invitation!` methods as specified.
- **`Invitation::NotAcceptable < ActiveRecord::RecordInvalid`** is defined on the `Invitation` model. `Invitation#accept!` raises it (not generic `RecordInvalid`) when the invitation is not `acceptable?` at lock time.
- **`accept_pending_invitation!` deletes the session token ONLY on successful acceptance.** Failed acceptance (race, validation, crash) leaves the token in session for retry. Pinned by spec.
- `RegistrationsController#create` includes `Signupable` and uses `commit_signup_atomically`; the old inline transaction code is GONE; all existing race-condition specs still pass.
- `OmniauthCallbacksController#handle_new_user_oauth` includes `Signupable` and uses `commit_signup_atomically` for BOTH verified-email AND unverified-email branches.
- `MagicLinkCallbacksController#create` includes `Signupable`, gates on `signups_open?`, and uses `commit_signup_atomically` for the new-user branch. The `raise ActiveRecord::Rollback` path is inline-commented.
- Invited user signing up via OAuth (verified email) ends up with workspace membership AND invitation marked accepted.
- Invited user signing up via OAuth (unverified email) ends up with workspace membership AND invitation marked accepted, even though sign-in is deferred until email verification. Inline comment in `handle_unverified_email_oauth` explains the deliberate trade-off (orphaned invitation if verification never completes; new invitation must be issued).
- Invited user signing up via magic link ends up with workspace membership AND invitation marked accepted.
- Uninvited user signing up via magic link in `:invite_only` mode → 303 to closed page; no User created; no token consumed.
- **Concurrent magic-link signup race (Tab A and Tab B same token, simultaneous POST) → exactly one User created, exactly one token consumption, the losing tab redirects to `:invalid`.** Pinned by request spec.
- **Concurrent invitation race (Tab A and Tab B same invitation, simultaneous OAuth callback) → exactly one User created with workspace membership; the losing tab's User row is rolled back, invitation token stays in session.** Pinned by request spec.
- `Invitation::NotAcceptable` is rescued in `commit_signup_atomically` and sets the `invitation_consumed` flash; generic `RecordInvalid` (from user/auth validation) does NOT set that flash (uses `@user.errors` instead).
- CSP source-level spec passes; iterates over `OauthHelper::PROVIDER_CONFIG` and verifies each provider's host is in `form-action`. Error message on missing provider points to the host map AND the CSP initializer.
- `spec/factories/magic_link_tokens.rb` exists with `:consumed` and `:expired` traits.
- Shared example `"an invited signup path that consumes invitations"` is defined and used by all three request specs.
- Closed page renders `shared/oauth_buttons` partial; partial self-hides when no providers configured.
- System spec covers the end-to-end invited-OAuth-signup path.
- Full test suite passes with no regressions in the auth flow request specs from PR #172.
