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
                          ┌──────────────────────────────────┐
                          │   Signupable concern             │
                          │   ─────────────────────────────  │
                          │   commit_signup_atomically(user) │
                          │     ApplicationRecord.transaction│
                          │       user.save!                 │
                          │       yield(user)                │
                          │       accept_pending_invitation! │
                          │     rescue RecordInvalid → false │
                          │                                  │
                          │   accept_pending_invitation!     │
                          │     session.delete(token)        │
                          │     Invitation.find_by&.accept!  │
                          └─────────────┬────────────────────┘
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
4. Calls `accept_pending_invitation!(user)` to consume any pending invitation from the session. If the invitation is no longer acceptable (race), `Invitation#accept!` raises `RecordInvalid` and the transaction rolls back.
5. On commit: returns `true`.
6. On `RecordInvalid`: if the failing record is an `Invitation`, sets `flash.now[:alert]` to the "invitation_consumed" message; otherwise leaves flash to the caller (which will typically render the form with model validation errors). Returns `false`.

The block is expected to be small. Anything that doesn't need transactional atomicity (mailer enqueuing, session start, redirect, response rendering) stays in the calling controller.

### `accept_pending_invitation!(user)` semantics

```ruby
def accept_pending_invitation!(user)
  token = session.delete(:pending_invitation_token)
  return if token.blank?

  Invitation.find_by(token: token)&.accept!(user)
end
```

- Token is deleted from session FIRST, unconditionally. Whether acceptance succeeds or fails, the token is single-use — no replay.
- If no token is present, the method is a no-op (returns `nil`). This is the "user signing up without an invitation in `:open` mode" case — perfectly legitimate.
- If the token doesn't match any invitation, `find_by` returns `nil` and `&.accept!` is a no-op. Tampered tokens are silently ignored at this layer (the gate already rejected them upstream).
- If the invitation exists but is not acceptable (already accepted, expired, declined, revoked), `Invitation#accept!` raises `RecordInvalid`. The transaction rolls back.

---

## Implementation

### `Signupable` concern (new — `app/controllers/concerns/signupable.rb`)

```ruby
module Signupable
  extend ActiveSupport::Concern

  # Runs user creation and invitation acceptance in a single transaction.
  # The block receives the saved user and should perform any in-transaction
  # work (creating authentications, generating verification tokens, etc.).
  #
  # Returns true on commit, false on RecordInvalid. On invitation race
  # (RecordInvalid on Invitation), sets flash.now[:alert].
  def commit_signup_atomically(user, &block)
    ApplicationRecord.transaction do
      user.save!
      yield(user) if block_given?
      accept_pending_invitation!(user)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    if e.record.is_a?(Invitation)
      flash.now[:alert] = I18n.t("registrations.create.invitation_consumed")
    end
    false
  end

  # Consumes the session's pending invitation token. Idempotent if no token
  # is present. Raises ActiveRecord::RecordInvalid if the invitation is no
  # longer acceptable (handled by commit_signup_atomically).
  def accept_pending_invitation!(user)
    token = session.delete(:pending_invitation_token)
    return if token.blank?

    Invitation.find_by(token: token)&.accept!(user)
  end
end
```

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

  consumed = false

  success = commit_signup_atomically(@user) do |user|
    consumed = MagicLinkToken.consume!(token_record.token)
    raise ActiveRecord::Rollback unless consumed

    user.authentications.create!(
      provider: "email",
      uid: user.email_address,
      verified_at: Time.current
    )
  end

  if success && consumed
    start_new_session_for(@user)
    redirect_to root_path, notice: t(".registered")
  elsif !consumed
    redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
  else
    @token = params[:token]
    @email = token_record.email
    render :new_registration, status: :unprocessable_entity
  end
end
```

**Note on `raise ActiveRecord::Rollback`:** When `MagicLinkToken.consume!` returns falsy (the token was already consumed by a concurrent request), we abort the transaction. `ActiveRecord::Rollback` is the only exception class that doesn't propagate beyond the transaction block — `commit_signup_atomically` will return `true` (because the rescue clause only catches `RecordInvalid`), but `consumed` will be false, and the controller redirects to the `:invalid` path.

The flag-checking after `commit_signup_atomically` is necessary because we have THREE possible outcomes (success, race-on-token, race-on-invitation, validation-failure), and the boolean return value alone can't distinguish them.

`MagicLinkCallbacksController#show` does NOT change. It already correctly handles the "user already exists, just sign them in" case and the "render new_registration form" case. The gate change only affects `#create` because that's where the User row gets persisted.

### CSP source-level spec (new — `spec/initializers/content_security_policy_spec.rb`)

```ruby
require "rails_helper"

RSpec.describe "Content Security Policy" do
  let(:policy) { Rails.application.config.content_security_policy }
  let(:form_action) { policy.directives["form-action"] }

  it "allows form-action to every configured OAuth provider host" do
    expected_hosts_by_provider = {
      google_oauth2: "https://accounts.google.com",
      github:        "https://github.com"
    }

    OauthHelper::PROVIDER_CONFIG.each_key do |provider|
      expected_host = expected_hosts_by_provider.fetch(provider) do
        raise "Add expected host for OAuth provider #{provider} to this spec"
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
    it "returns false when user.save! raises RecordInvalid"
    it "returns false and sets flash[:alert] when invitation accept! raises RecordInvalid (race)"
    it "rolls back user creation when block raises ActiveRecord::Rollback"
    it "consumes session pending_invitation_token on commit"
    it "clears session pending_invitation_token even when block raises Rollback"
  end

  describe "#accept_pending_invitation!" do
    it "is a no-op when no token in session"
    it "is a no-op when token does not match any invitation"
    it "raises RecordInvalid when invitation is not acceptable"
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

---

## Edge cases pinned by explicit specs

1. **Token cleanup is unconditional.** Whether `commit_signup_atomically` commits or rolls back, `session.delete(:pending_invitation_token)` runs first inside `accept_pending_invitation!`. A failed acceptance does NOT leave the token in session for a retry.
2. **Existing user OAuth with invitation token still works.** Branch 1 of `OmniauthCallbacksController#create` (existing-identity sign-in) is untouched and does NOT consume invitations. Only Branch 3 (new-user, via `handle_new_user_oauth`) consumes them. An existing user with a pending invitation must click an OAuth provider that hits `handle_new_user_oauth`'s "user exists by email" branch.
3. **Branch 2 (signed-in user linking new OAuth provider) is untouched.** No invitation logic added there.
4. **Magic link gate does NOT affect `#show` for existing users.** Only `#create` (which builds a new User) consults `signups_open?`. Existing users clicking magic links can always sign in.
5. **`MagicLinkToken.consume!` inside the transaction.** Token consumption moves into the outer transaction. Its atomic update semantics (`UPDATE ... WHERE consumed_at IS NULL`) are unchanged. If the token was already consumed, the inner `consume!` returns falsy and we explicitly `raise ActiveRecord::Rollback` to abort.

---

## Out-of-scope follow-ups (captured for later)

- **Magic link per-recipient rate limiting.** Current per-IP `rate_limit` could be supplemented by `EmailRecipientThrottle` for defense in depth. Trigger: real abuse case or a security review request.
- **Magic-link-in-invitation-emails feature.** If invitation emails ever include a magic link token (faster onboarding for invited users), this design's gate + invitation consumption already covers it. No further work needed at gate time.
- **`OauthCredentials` POPO refactor** (from the parent spec) still deferred.
- **Per-workspace invite-only mode** (from the parent spec) still deferred.

---

## Acceptance checklist

- `Signupable` concern exists at `app/controllers/concerns/signupable.rb` with `commit_signup_atomically` and `accept_pending_invitation!` methods as specified.
- `RegistrationsController#create` includes `Signupable` and uses `commit_signup_atomically`; the old inline transaction code is GONE; all existing race-condition specs still pass.
- `OmniauthCallbacksController#handle_new_user_oauth` includes `Signupable` and uses `commit_signup_atomically` for BOTH verified-email AND unverified-email branches.
- `MagicLinkCallbacksController#create` includes `Signupable`, gates on `signups_open?`, and uses `commit_signup_atomically` for the new-user branch.
- Invited user signing up via OAuth (verified email) ends up with workspace membership AND invitation marked accepted.
- Invited user signing up via OAuth (unverified email) ends up with workspace membership AND invitation marked accepted, even though sign-in is deferred until email verification.
- Invited user signing up via magic link ends up with workspace membership AND invitation marked accepted.
- Uninvited user signing up via magic link in `:invite_only` mode → 303 to closed page; no User created; no token consumed.
- CSP source-level spec passes; iterates over `OauthHelper::PROVIDER_CONFIG` and verifies each provider's host is in `form-action`.
- Closed page renders `shared/oauth_buttons` partial; partial self-hides when no providers configured.
- System spec covers the end-to-end invited-OAuth-signup path.
- Full test suite passes with no regressions in the auth flow request specs from PR #172.
