# Auth-Flow Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two gate gaps left over from PR #172 — OAuth Branch 3 doesn't consume invitations, and `MagicLinkCallbacksController#create` bypasses the signup gate entirely. Extract the now-three transactional signup paths into a `Signupable` controller concern. Persist invitation tokens on pending `Authentication` records during unverified-email OAuth signup so acceptance can be deferred to email-verification time.

**Architecture:** New `Signupable` concern centralizes the "user save + invitation accept in one transaction" pattern. `Invitation::NotAcceptable` exception replaces the type-dispatch smell. New `pending_invitation_token` column on `authentications` enables deferred acceptance for unverified-email OAuth. The existing `Account::ConnectedAccountsController#verify` is extended to claim the pending invitation AND sign in unauthenticated new-user verifications.

**Tech Stack:** Rails 8.1, SQLite, RSpec, FactoryBot, Capybara + Playwright, `rails-controller-testing` (from PR #172), OmniAuth 2.x + omniauth-rails_csrf_protection.

**Spec:** `docs/superpowers/specs/2026-05-25-auth-flow-consistency-design.md` (commits `361712b`, `1f6f47b`, `81ff347`).

---

## File Structure

**Files to CREATE (6):**

- `db/migrate/YYYYMMDDhhmmss_add_pending_invitation_token_to_authentications.rb` — column for deferred acceptance
- `app/controllers/concerns/signupable.rb` — shared transactional signup logic
- `spec/controllers/concerns/signupable_spec.rb` — concern unit spec
- `spec/initializers/content_security_policy_spec.rb` — source-level CSP coverage spec
- `spec/factories/magic_link_tokens.rb` — magic link token factory with traits
- `spec/support/shared_examples/invited_signup_atomicity.rb` — 3×3 matrix shared example

**Files to MODIFY (12):**

- `app/models/invitation.rb` — define `Invitation::NotAcceptable`, raise from `accept!`
- `app/models/authentication.rb` — add `claim_pending_invitation!` method
- `app/controllers/registrations_controller.rb` — include `Signupable`, refactor `#create`
- `app/controllers/omniauth_callbacks_controller.rb` — include `Signupable`, refactor `handle_new_user_oauth` verified and unverified branches
- `app/controllers/magic_link_callbacks_controller.rb` — include `Signupable`, add gate, refactor `#create`
- `app/controllers/account/connected_accounts_controller.rb` — extend `#verify` to call `claim_pending_invitation!` and sign in unauthenticated users
- `app/views/registrations/closed.html.erb` — render `shared/oauth_buttons` partial
- `spec/models/invitation_spec.rb` — assert `accept!` raises `NotAcceptable` (not generic `RecordInvalid`)
- `spec/models/authentication_spec.rb` — add `#claim_pending_invitation!` cases
- `spec/requests/registrations_spec.rb` — update for concern refactor (no behavior change in green path)
- `spec/requests/omniauth_callbacks_spec.rb` — add new cases per spec test plan
- `spec/requests/magic_link_callbacks_spec.rb` — add gate + race tests (create file if missing)
- `spec/requests/account/connected_accounts_spec.rb` — add `claim_pending_invitation!` integration cases
- `spec/system/invite_only_signup_spec.rb` — add OAuth-via-button scenario

---

## Task 1: Migration — add `pending_invitation_token` column to authentications

**Files:**

- Create: `db/migrate/YYYYMMDDhhmmss_add_pending_invitation_token_to_authentications.rb`
- Modified by `db:migrate`: `db/schema.rb`

- [ ] **Step 1.1: Generate the migration**

```bash
mise exec -- bin/rails generate migration AddPendingInvitationTokenToAuthentications pending_invitation_token:string
```

Edit the generated file so it has this exact content:

```ruby
class AddPendingInvitationTokenToAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :authentications, :pending_invitation_token, :string

    # Partial index keeps the index small — only the rare authentications
    # carrying a pending invitation get indexed. Used by
    # Authentication#claim_pending_invitation!.
    add_index :authentications, :pending_invitation_token,
              where: "pending_invitation_token IS NOT NULL"
  end
end
```

- [ ] **Step 1.2: Run the migration**

```bash
mise exec -- bin/rails db:migrate
```

Expected: `add_column(:authentications, :pending_invitation_token, :string)` succeeds. `add_index` succeeds. `db/schema.rb` regenerates with the new column and the partial index.

- [ ] **Step 1.3: Verify schema reflects the change**

```bash
mise exec -- bin/rails runner 'puts Authentication.column_names.include?("pending_invitation_token")'
```

Expected: `true`

- [ ] **Step 1.4: Verify the partial index exists**

```bash
mise exec -- bin/rails runner 'puts Authentication.connection.indexes("authentications").map(&:name)'
```

Expected: the index list includes `index_authentications_on_pending_invitation_token`.

- [ ] **Step 1.5: Commit**

```bash
git add db/migrate/*_add_pending_invitation_token_to_authentications.rb db/schema.rb
git commit -m "feat(authentications): add pending_invitation_token column

Used by the deferred-acceptance design for unverified-email OAuth
signup. Partial index keeps storage small since most authentications
have no pending invitation."
```

---

## Task 2: `Invitation::NotAcceptable` exception + `accept!` updated to raise it

**Files:**

- Modify: `app/models/invitation.rb`
- Test: `spec/models/invitation_spec.rb`

- [ ] **Step 2.1: Write failing tests**

Open `spec/models/invitation_spec.rb` and add (placed near the existing `accept!` tests):

```ruby
describe "Invitation::NotAcceptable" do
  it "is a standalone StandardError (not an ActiveRecord::RecordInvalid)" do
    expect(Invitation::NotAcceptable.ancestors).to include(StandardError)
    expect(Invitation::NotAcceptable.ancestors).not_to include(ActiveRecord::RecordInvalid)
  end
end

describe "#accept! raise behavior" do
  let(:user) { create(:user) }

  it "raises Invitation::NotAcceptable when invitation is already accepted" do
    invitation = create(:invitation, :accepted)
    expect {
      invitation.accept!(user)
    }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
  end

  it "raises Invitation::NotAcceptable when invitation is expired" do
    invitation = create(:invitation, :expired)
    expect {
      invitation.accept!(user)
    }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
  end

  it "raises Invitation::NotAcceptable when invitation is declined" do
    invitation = create(:invitation, :declined)
    expect {
      invitation.accept!(user)
    }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
  end

  it "does NOT raise NotAcceptable on a valid pending invitation" do
    invitation = create(:invitation)
    expect {
      invitation.accept!(user)
    }.not_to raise_error
  end
end
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/models/invitation_spec.rb -e "Invitation::NotAcceptable" -e "#accept! raise behavior"
```

Expected: All `NotAcceptable` tests fail — the constant doesn't exist yet and `accept!` raises the generic exception type (or `RuntimeError` from a bare `raise`).

- [ ] **Step 2.3: Define the exception and update `accept!`**

Open `app/models/invitation.rb`. Inside the class body (near the top, before any callbacks), add:

```ruby
class NotAcceptable < StandardError; end
```

Then find the existing `accept!` method (around line 97). The current implementation has `raise unless pending? && !expired?`. Replace that line with:

```ruby
raise NotAcceptable, "Invitation no longer acceptable" unless pending? && !expired?
```

Leave the surrounding `transaction { lock! ... }` structure untouched.

- [ ] **Step 2.4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/models/invitation_spec.rb -e "Invitation::NotAcceptable" -e "#accept! raise behavior"
```

Expected: All 5 tests pass.

- [ ] **Step 2.5: Run full invitation spec for regressions**

```bash
mise exec -- bundle exec rspec spec/models/invitation_spec.rb
```

Expected: 0 failures. If existing tests were rescuing `RuntimeError` or `RecordInvalid` from `accept!`, they'll break — update them to rescue `Invitation::NotAcceptable`. Per audit, the only existing caller is `RegistrationsController#accept_pending_invitation` which is being rewritten in Task 7, so this should be clean.

- [ ] **Step 2.6: Commit**

```bash
git add app/models/invitation.rb spec/models/invitation_spec.rb
git commit -m "feat(invitation): add NotAcceptable exception

Invitation#accept! now raises a specific exception class instead
of a bare RuntimeError. NotAcceptable is a standalone StandardError
(NOT a RecordInvalid subclass) so callers can rescue it specifically
without catching unrelated validation failures."
```

---

## Task 3: `Authentication#claim_pending_invitation!` method

**Files:**

- Modify: `app/models/authentication.rb`
- Test: `spec/models/authentication_spec.rb`

- [ ] **Step 3.1: Write failing tests**

Add to `spec/models/authentication_spec.rb`:

```ruby
describe "#claim_pending_invitation!" do
  let(:user) { create(:user) }
  let(:authentication) { create(:authentication, user: user, pending_invitation_token: nil) }

  it "is a no-op when pending_invitation_token is blank" do
    expect {
      authentication.claim_pending_invitation!(user)
    }.not_to change(user.workspaces, :count)
  end

  it "clears the token and returns nil when token matches no invitation" do
    authentication.update!(pending_invitation_token: "no-such-token-anywhere")
    authentication.claim_pending_invitation!(user)
    expect(authentication.reload.pending_invitation_token).to be_nil
  end

  it "accepts the invitation and clears the token on success" do
    invitation = create(:invitation)
    authentication.update!(pending_invitation_token: invitation.token)

    authentication.claim_pending_invitation!(user)

    expect(invitation.reload).to be_accepted
    expect(authentication.reload.pending_invitation_token).to be_nil
    expect(user.workspaces).to include(invitation.invitable)
  end

  it "raises Invitation::NotAcceptable and does NOT clear the token when invitation is stale" do
    invitation = create(:invitation, :expired)
    authentication.update!(pending_invitation_token: invitation.token)

    expect {
      authentication.claim_pending_invitation!(user)
    }.to raise_error(Invitation::NotAcceptable)

    expect(authentication.reload.pending_invitation_token).to eq(invitation.token)
  end
end
```

- [ ] **Step 3.2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/models/authentication_spec.rb -e "#claim_pending_invitation!"
```

Expected: All 4 tests fail with `NoMethodError: undefined method 'claim_pending_invitation!'`.

- [ ] **Step 3.3: Implement the method**

Open `app/models/authentication.rb`. In the public section (NOT inside `private`), add:

```ruby
def claim_pending_invitation!(user)
  return if pending_invitation_token.blank?

  invitation = Invitation.find_by(token: pending_invitation_token)
  if invitation.nil?
    update!(pending_invitation_token: nil)
    return
  end

  invitation.accept!(user)
  update!(pending_invitation_token: nil)
end
```

- [ ] **Step 3.4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/models/authentication_spec.rb -e "#claim_pending_invitation!"
```

Expected: All 4 tests pass.

- [ ] **Step 3.5: Run full authentication spec for regressions**

```bash
mise exec -- bundle exec rspec spec/models/authentication_spec.rb
```

Expected: 0 failures.

- [ ] **Step 3.6: Commit**

```bash
git add app/models/authentication.rb spec/models/authentication_spec.rb
git commit -m "feat(authentication): add claim_pending_invitation! method

Called by the email verification flow (ConnectedAccountsController#verify)
to accept a pending invitation that was persisted onto the Authentication
during unverified-email OAuth signup. Mirrors Signupable#accept_pending_invitation!
but reads from the column instead of session."
```

---

## Task 4: `Signupable` controller concern

**Files:**

- Create: `app/controllers/concerns/signupable.rb`
- Test: `spec/controllers/concerns/signupable_spec.rb`

- [ ] **Step 4.1: Write failing unit spec**

Create `spec/controllers/concerns/signupable_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Signupable, type: :controller do
  controller(ApplicationController) do
    include Signupable
    allow_unauthenticated_access

    def create
      user = User.new(
        email_address: params[:email_address],
        first_name: "Test",
        last_name: "User",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      )

      if commit_signup_atomically(user) { |u| u.authentications.create!(provider: "email", uid: u.email_address) }
        render plain: "ok"
      else
        render plain: "fail", status: :unprocessable_entity
      end
    end
  end

  before do
    routes.draw { post "create" => "anonymous#create" }
  end

  describe "#commit_signup_atomically" do
    it "returns true and commits when block succeeds" do
      post :create, params: { email_address: "new@example.com" }
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email_address: "new@example.com")).to be_present
    end

    it "returns false when user.save! raises RecordInvalid" do
      post :create, params: { email_address: "not an email" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find_by(email_address: "not an email")).to be_nil
    end

    it "consumes the session token on success when invitation is present" do
      invitation = create(:invitation, email: "invitee@example.com")
      session[:pending_invitation_token] = invitation.token

      post :create, params: { email_address: "invitee@example.com" }

      expect(response).to have_http_status(:ok)
      expect(invitation.reload).to be_accepted
      expect(session[:pending_invitation_token]).to be_nil
    end

    it "rolls back user creation when invitation accept! raises NotAcceptable" do
      invitation = create(:invitation, :accepted)
      session[:pending_invitation_token] = invitation.token

      expect {
        post :create, params: { email_address: "racer@example.com" }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to be_present
    end

    it "leaves session token in place when invitation NotAcceptable" do
      invitation = create(:invitation, :expired)
      session[:pending_invitation_token] = invitation.token

      post :create, params: { email_address: "retry@example.com" }

      expect(session[:pending_invitation_token]).to eq(invitation.token)
    end
  end

  describe "#accept_pending_invitation!" do
    let(:user) { create(:user) }

    it "is a no-op when no token in session" do
      expect { controller.send(:accept_pending_invitation!, user) }.not_to raise_error
    end

    it "is a no-op when token does not match any invitation" do
      controller.session[:pending_invitation_token] = "no-such-token"
      controller.send(:accept_pending_invitation!, user)
      expect(controller.session[:pending_invitation_token]).to eq("no-such-token")
    end

    it "accepts and clears token on valid invitation" do
      invitation = create(:invitation)
      controller.session[:pending_invitation_token] = invitation.token
      controller.send(:accept_pending_invitation!, user)
      expect(invitation.reload).to be_accepted
      expect(controller.session[:pending_invitation_token]).to be_nil
    end
  end
end
```

- [ ] **Step 4.2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/controllers/concerns/signupable_spec.rb
```

Expected: All tests fail with `NameError: uninitialized constant Signupable`.

- [ ] **Step 4.3: Create the concern**

Create `app/controllers/concerns/signupable.rb`:

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
  # Sets flash.now[:alert] only on Invitation::NotAcceptable (so the caller
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
  # longer acceptable. Session token is deleted ONLY on successful acceptance.
  def accept_pending_invitation!(user)
    token = session[:pending_invitation_token]
    return if token.blank?

    invitation = Invitation.find_by(token: token)
    return if invitation.nil?

    invitation.accept!(user)
    session.delete(:pending_invitation_token)
  end
end
```

- [ ] **Step 4.4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/controllers/concerns/signupable_spec.rb
```

Expected: All 8 tests pass.

- [ ] **Step 4.5: Commit**

```bash
git add app/controllers/concerns/signupable.rb spec/controllers/concerns/signupable_spec.rb
git commit -m "feat(auth): add Signupable concern with atomic signup helper

commit_signup_atomically wraps user creation, block-provided work
(authentications, verification tokens), and invitation acceptance in
a single transaction. Rescues Invitation::NotAcceptable specifically
to set the invitation-consumed flash; generic RecordInvalid returns
false without setting flash (caller renders @user.errors)."
```

---

## Task 5: Magic link tokens factory + shared examples

**Files:**

- Create: `spec/factories/magic_link_tokens.rb`
- Create: `spec/support/shared_examples/invited_signup_atomicity.rb`

- [ ] **Step 5.1: Verify MagicLinkToken model columns**

```bash
mise exec -- bin/rails runner 'puts MagicLinkToken.column_names.inspect'
```

Expected output includes at least: `email`, `token`, `consumed_at`, `expires_at`.

- [ ] **Step 5.2: Create the factory**

Create `spec/factories/magic_link_tokens.rb`:

```ruby
FactoryBot.define do
  factory :magic_link_token do
    email { Faker::Internet.email }
    token { SecureRandom.hex(32) }
    expires_at { 1.hour.from_now }

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end
```

- [ ] **Step 5.3: Verify the factory builds cleanly**

```bash
mise exec -- bundle exec rspec --init-script -e 'puts FactoryBot.build(:magic_link_token).valid?' 2>/dev/null || mise exec -- bin/rails runner 'require "factory_bot_rails"; puts FactoryBot.build(:magic_link_token).valid?'
```

Expected: `true`. If the model has additional required columns, add them to the factory.

- [ ] **Step 5.4: Create the shared examples file**

Create `spec/support/shared_examples/invited_signup_atomicity.rb`:

```ruby
RSpec.shared_examples "an invited signup path that consumes invitations" do
  it "creates the user, consumes the invitation, and adds workspace membership" do
    invitation = create(:invitation, invitable: workspace, email: signup_email)
    post accept_invitation_path(token: invitation.token)
    expect(response).to have_http_status(:found).or have_http_status(:see_other)

    expect { perform_signup }.to change(User, :count).by(1)

    expect(invitation.reload).to be_accepted
    new_user = User.find_by(email_address: signup_email)
    expect(new_user).to be_present
    expect(new_user.workspaces).to include(workspace)
  end

  it "does NOT consume the invitation if signup fails (validation)" do
    invitation = create(:invitation, invitable: workspace, email: signup_email)
    post accept_invitation_path(token: invitation.token)

    expect { perform_failing_signup }.not_to change(User, :count)
    expect(invitation.reload).to be_pending
  end
end
```

- [ ] **Step 5.5: Verify shared examples file loads**

The shared examples file is in `spec/support/shared_examples/` which `rails_helper.rb` loads via `Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }`. Verify:

```bash
mise exec -- bundle exec rspec --dry-run spec/support/shared_examples/invited_signup_atomicity.rb 2>&1 | tail -5
```

Expected: no syntax errors. (Dry-run on a shared-examples file gives "0 examples" which is fine — it's a definition file.)

- [ ] **Step 5.6: Commit**

```bash
git add spec/factories/magic_link_tokens.rb spec/support/shared_examples/invited_signup_atomicity.rb
git commit -m "test(auth): add magic_link_tokens factory and invited-signup-atomicity shared examples

Factory enables request specs to build tokens without inline construction.
Shared examples DRY up the 3x3 matrix (each of 3 signup paths must
consume invitations + grant workspace membership)."
```

---

## Task 6: Refactor `RegistrationsController#create` to use `Signupable`

**Files:**

- Modify: `app/controllers/registrations_controller.rb`
- Test: `spec/requests/registrations_spec.rb`

- [ ] **Step 6.1: Read the current `#create` method**

Read `app/controllers/registrations_controller.rb` lines 1-56 to confirm the current structure. The current `#create` has its own transactional logic + private `accept_pending_invitation!` method. Both will be replaced.

- [ ] **Step 6.2: Write a regression test pinning current behavior (race rollback)**

Confirm the existing race-condition test in `spec/requests/registrations_spec.rb` still works:

```bash
mise exec -- bundle exec rspec spec/requests/registrations_spec.rb -e "race condition"
```

Expected: PASS (current implementation handles this correctly; we're going to preserve the behavior).

- [ ] **Step 6.3: Refactor the controller**

Open `app/controllers/registrations_controller.rb`. Replace the `#create` method AND remove the private `accept_pending_invitation!` method.

After: include the concern near the top of the class:

```ruby
class RegistrationsController < ApplicationController
  include Signupable
  allow_unauthenticated_access
  require_unauthenticated_access only: :new
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: t("registrations.create.rate_limited") }

  def new
    if signups_open?
      @user = User.new
    else
      render :closed
    end
  end

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

  private

  def registration_params
    params.require(:user).permit(
      :email_address, :first_name, :last_name,
      :password, :password_confirmation
    )
  end
end
```

The previously-private `accept_pending_invitation!` method is GONE (now provided by `Signupable`).

- [ ] **Step 6.4: Run all registrations request specs**

```bash
mise exec -- bundle exec rspec spec/requests/registrations_spec.rb
```

Expected: All tests pass (this is a pure refactor — behavior preserved). If the race-condition test fails, the concern's exception handling doesn't match the prior inline behavior — debug before continuing.

- [ ] **Step 6.5: Commit**

```bash
git add app/controllers/registrations_controller.rb
git commit -m "refactor(registrations): use Signupable concern for atomic signup

Removes the inline transaction + private accept_pending_invitation!
from #create; the concern centralizes the same logic. No behavior
change in the green or race-condition paths."
```

---

## Task 7: `OmniauthCallbacksController` — refactor verified-email branch

**Files:**

- Modify: `app/controllers/omniauth_callbacks_controller.rb`
- Test: `spec/requests/omniauth_callbacks_spec.rb`

- [ ] **Step 7.1: Write failing tests for invited OAuth verified-email signup**

Add to `spec/requests/omniauth_callbacks_spec.rb`:

```ruby
describe "Invited new-user OAuth signup (verified email)" do
  let(:workspace) { create(:workspace) }
  let(:invitation) { create(:invitation, invitable: workspace, email: "newoauth@example.com") }

  let(:google_auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "999888",
      info: { email: "newoauth@example.com", first_name: "New", last_name: "OAuth", email_verified: true },
      credentials: { token: "tk", refresh_token: "rt", expires_at: 1.hour.from_now.to_i }
    )
  end

  before do
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash
    post accept_invitation_path(token: invitation.token)
  end

  after { OmniAuth.config.mock_auth[:google_oauth2] = nil }

  it "creates the user, accepts the invitation, and adds workspace membership" do
    expect {
      post "/auth/google_oauth2/callback"
    }.to change(User, :count).by(1)

    new_user = User.find_by(email_address: "newoauth@example.com")
    expect(new_user).to be_present
    expect(invitation.reload).to be_accepted
    expect(new_user.workspaces).to include(workspace)
  end

  it "signs the user in" do
    post "/auth/google_oauth2/callback"
    expect(response).to redirect_to(root_path)
  end
end
```

- [ ] **Step 7.2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb -e "Invited new-user OAuth signup (verified email)"
```

Expected: User is created BUT invitation is NOT accepted, AND new_user.workspaces does NOT include workspace. The current code creates the user but skips invitation consumption.

- [ ] **Step 7.3: Refactor `handle_new_user_oauth` and add verified-branch atomicity**

Open `app/controllers/omniauth_callbacks_controller.rb`. Near the top, add `include Signupable`.

Then refactor `handle_new_user_oauth` to split into two private sub-handlers. Replace the current method (around line 116) with:

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
  @user = find_verified_user_by_email(auth_hash.info.email) || create_user_from_oauth(auth_hash)

  success = commit_signup_atomically(@user) do |user|
    user.authentications.create!(
      provider: normalized_provider(auth_hash),
      uid: auth_hash.uid,
      email: auth_hash.info.email,
      verified_at: Time.current,
      **oauth_attrs(auth_hash)
    )
  end

  if success
    start_new_session_for(@user)
    redirect_to root_path, notice: t("sessions.create.success")
  else
    redirect_to new_session_path, alert: t("omniauth_callbacks.create.failure")
  end
end
```

(Leave `handle_unverified_email_oauth` untouched for now — Task 8 modifies it. The current implementation should still work for the unverified path.)

- [ ] **Step 7.4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb -e "Invited new-user OAuth signup (verified email)"
```

Expected: Both tests pass — user is created AND invitation is consumed AND workspace membership exists.

- [ ] **Step 7.5: Run the full file to check for regressions**

```bash
mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb
```

Expected: 0 failures. Branch 1 (existing identity) and Branch 2 (signed-in linking) tests still pass.

- [ ] **Step 7.6: Commit**

```bash
git add app/controllers/omniauth_callbacks_controller.rb spec/requests/omniauth_callbacks_spec.rb
git commit -m "feat(oauth): invited verified-email OAuth signup now consumes invitation

Splits handle_new_user_oauth into verified/unverified branches.
The verified branch uses Signupable#commit_signup_atomically, which
consumes the pending invitation atomically with user creation.
Existing identity (Branch 1) and signed-in linking (Branch 2)
paths are unchanged."
```

---

## Task 8: `OmniauthCallbacksController` — unverified-email branch persists invitation token

**Files:**

- Modify: `app/controllers/omniauth_callbacks_controller.rb`
- Test: `spec/requests/omniauth_callbacks_spec.rb`

- [ ] **Step 8.1: Write failing tests for deferred-acceptance behavior**

Add to `spec/requests/omniauth_callbacks_spec.rb`:

```ruby
describe "Invited new-user OAuth signup (UNverified email)" do
  let(:workspace) { create(:workspace) }
  let(:invitation) { create(:invitation, invitable: workspace, email: "unverified@example.com") }

  let(:google_unverified_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "777666",
      info: { email: "unverified@example.com", first_name: "Pending", last_name: "Verify", email_verified: false },
      credentials: { token: "tk2", refresh_token: "rt2", expires_at: 1.hour.from_now.to_i }
    )
  end

  before do
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = google_unverified_hash
    post accept_invitation_path(token: invitation.token)
  end

  after { OmniAuth.config.mock_auth[:google_oauth2] = nil }

  it "creates the user and a pending Authentication" do
    expect {
      post "/auth/google_oauth2/callback"
    }.to change(User, :count).by(1).and change(Authentication, :count).by(1)
  end

  it "persists the invitation token on the pending Authentication" do
    post "/auth/google_oauth2/callback"
    new_user = User.find_by(email_address: "unverified@example.com")
    auth = new_user.authentications.last
    expect(auth.pending_invitation_token).to eq(invitation.token)
    expect(auth.verified_at).to be_nil
  end

  it "does NOT consume the invitation yet (deferred to verification)" do
    post "/auth/google_oauth2/callback"
    expect(invitation.reload).to be_pending
    expect(invitation.reload.accepted_at).to be_nil
  end

  it "clears the session token after persisting onto the Authentication" do
    post "/auth/google_oauth2/callback"
    expect(session[:pending_invitation_token]).to be_nil
  end

  it "does NOT sign the user in (verification still required)" do
    post "/auth/google_oauth2/callback"
    expect(response).to redirect_to(new_session_path)
  end
end
```

- [ ] **Step 8.2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb -e "Invited new-user OAuth signup (UNverified email)"
```

Expected: At least the "persists the invitation token" and "clears the session token" tests fail — current code doesn't write `pending_invitation_token`.

- [ ] **Step 8.3: Update `handle_unverified_email_oauth`**

Replace the existing `handle_unverified_email_oauth` private method with:

```ruby
def handle_unverified_email_oauth(auth_hash)
  @user = create_user_from_oauth(auth_hash)
  pending_auth = nil

  # NOTE: this branch does NOT use commit_signup_atomically — it must NOT
  # consume the invitation yet. We persist the pending invitation token
  # on the new Authentication record so it can be claimed when the user
  # proves email ownership by clicking the verification email link.
  ApplicationRecord.transaction do
    @user.save!
    pending_auth = @user.authentications.create!(
      provider: normalized_provider(auth_hash),
      uid: auth_hash.uid,
      email: auth_hash.info.email,
      verified_at: nil,
      pending_invitation_token: session[:pending_invitation_token],
      **oauth_attrs(auth_hash)
    )
    pending_auth.generate_verification_token!
  end

  # Token persisted on the Authentication; safe to remove from session.
  session.delete(:pending_invitation_token)

  AuthenticationMailer.verification_email(pending_auth).deliver_later
  redirect_to new_session_path, notice: t("omniauth_callbacks.create.check_email")
rescue ActiveRecord::RecordInvalid
  redirect_to new_session_path, alert: t("omniauth_callbacks.create.failure")
end
```

The exact i18n key for the "check_email" notice should match what the existing code uses for the unverified path. If the existing notice key is different (e.g., `omniauth_callbacks.create.unverified_email_pending`), use that one.

- [ ] **Step 8.4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb -e "Invited new-user OAuth signup (UNverified email)"
```

Expected: All 5 tests pass.

- [ ] **Step 8.5: Run the full file for regressions**

```bash
mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb
```

Expected: 0 failures.

- [ ] **Step 8.6: Commit**

```bash
git add app/controllers/omniauth_callbacks_controller.rb spec/requests/omniauth_callbacks_spec.rb
git commit -m "feat(oauth): persist pending invitation on unverified-email OAuth signup

The unverified-email branch no longer calls accept_pending_invitation!
immediately — it writes the session token onto the new pending
Authentication's pending_invitation_token column. Invitation acceptance
is deferred to Account::ConnectedAccountsController#verify (Task 9),
ensuring the invitation is only consumed once email ownership is proven."
```

---

## Task 9: `Account::ConnectedAccountsController#verify` claims pending invitation

**Files:**

- Modify: `app/controllers/account/connected_accounts_controller.rb`
- Test: `spec/requests/account/connected_accounts_spec.rb`

- [ ] **Step 9.1: Read the current `#verify` action**

Read `app/controllers/account/connected_accounts_controller.rb` lines 17-39 to confirm the current dual-purpose flow (signed-in user managing accounts vs new-user OAuth verifying).

- [ ] **Step 9.2: Write failing test**

Add to `spec/requests/account/connected_accounts_spec.rb`:

```ruby
describe "GET /account/connected_accounts/verify (new user with pending invitation)" do
  let(:workspace) { create(:workspace) }
  let(:invitation) { create(:invitation, invitable: workspace, email: "needsverify@example.com") }
  let(:user) { create(:user, email_address: "needsverify@example.com") }
  let(:pending_auth) do
    user.authentications.create!(
      provider: "google_oauth2",
      uid: "verifyme",
      email: "needsverify@example.com",
      verified_at: nil,
      pending_invitation_token: invitation.token
    ).tap(&:generate_verification_token!)
  end

  it "verifies the auth, signs in the user, claims the invitation, and grants workspace membership" do
    token = pending_auth.verification_token
    get verify_account_connected_account_path(token: token)

    expect(pending_auth.reload.verified_at).to be_present
    expect(invitation.reload).to be_accepted
    expect(user.reload.workspaces).to include(workspace)
    expect(pending_auth.reload.pending_invitation_token).to be_nil
  end

  it "shows the invitation_consumed flash if the invitation became stale before verification" do
    # Sabotage the invitation
    invitation.update!(status: "accepted", accepted_at: 1.minute.ago)

    token = pending_auth.verification_token
    get verify_account_connected_account_path(token: token)

    expect(pending_auth.reload.verified_at).to be_present
    expect(flash[:alert]).to include(I18n.t("registrations.create.invitation_consumed"))
  end
end
```

The exact path helper is `verify_account_connected_account_path` per the existing routes; confirm and adjust if different.

- [ ] **Step 9.3: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb -e "new user with pending invitation"
```

Expected: tests fail — current `#verify` doesn't claim invitations or sign in unauthenticated new users.

- [ ] **Step 9.4: Extend the `#verify` action**

Open `app/controllers/account/connected_accounts_controller.rb`. Modify the `#verify` action to (a) for unauthenticated callers with a pending Authentication, sign them in after verification, and (b) call `claim_pending_invitation!` after the auth is verified and the user is signed in.

Replace the current `#verify` method with:

```ruby
def verify
  auth = Authentication.find_by(verification_token: params[:token])

  if auth.nil? || auth.token_expired?
    redirect_to(authenticated? ? account_connected_accounts_path : new_session_path,
                alert: t(".invalid_or_expired"))
    return
  end

  if authenticated? && Current.user.id != auth.user_id
    redirect_to account_connected_accounts_path, alert: t(".invalid_or_expired")
    return
  end

  auth.verify!

  # For unauthenticated callers verifying their first auth (new-user OAuth
  # unverified-email flow), sign them in now that their email is proven.
  start_new_session_for(auth.user) unless authenticated?

  # Claim any pending invitation persisted onto this Authentication.
  # NotAcceptable shouldn't block sign-in — show the flash but continue.
  begin
    auth.claim_pending_invitation!(Current.user)
  rescue Invitation::NotAcceptable
    flash[:alert] = t("registrations.create.invitation_consumed")
  end

  if Current.user == auth.user
    redirect_to root_path, notice: t(".success", provider: auth.provider)
  else
    redirect_to account_connected_accounts_path, notice: t(".success", provider: auth.provider)
  end
end
```

- [ ] **Step 9.5: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb -e "new user with pending invitation"
```

Expected: Both new tests pass.

- [ ] **Step 9.6: Run the full file for regressions**

```bash
mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb
```

Expected: 0 failures. Existing signed-in-user verification flow should still work.

- [ ] **Step 9.7: Commit**

```bash
git add app/controllers/account/connected_accounts_controller.rb spec/requests/account/connected_accounts_spec.rb
git commit -m "feat(verification): claim pending invitation on email-verification success

When a new-user OAuth-unverified-email signup clicks the verification
link, the verify action now: (1) signs them in for the first time
(prior code redirected unauthenticated callers to sign in manually);
(2) claims any pending invitation persisted on the Authentication.
NotAcceptable is rescued and surfaced via flash so a stale invitation
doesn't block sign-in for an unrelated reason."
```

---

## Task 10: `MagicLinkCallbacksController#create` — add gate + use `Signupable`

**Files:**

- Modify: `app/controllers/magic_link_callbacks_controller.rb`
- Test: `spec/requests/magic_link_callbacks_spec.rb` (create if missing)

- [ ] **Step 10.1: Check if request spec exists**

```bash
ls spec/requests/magic_link_callbacks_spec.rb 2>&1 || echo "missing"
```

If missing, create the file with this skeleton header:

```ruby
require "rails_helper"

RSpec.describe "MagicLinkCallbacks", type: :request do
  let(:workspace) { create(:workspace) }
end
```

- [ ] **Step 10.2: Write failing tests**

Add to `spec/requests/magic_link_callbacks_spec.rb`:

```ruby
describe "POST /magic_link_callback/:token (new-user signup)" do
  let(:token_record) { create(:magic_link_token, email: "newml@example.com") }
  let(:params) { { user: { first_name: "Magic", last_name: "Link" } } }

  context "in invite_only mode without an invitation token in session" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

    it "redirects to new_registration_path with 303 and creates no User" do
      expect {
        post "/magic_link_callback/#{token_record.token}", params: params
      }.not_to change(User, :count)

      expect(response).to redirect_to(new_registration_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
    end

    it "does NOT consume the magic-link token" do
      post "/magic_link_callback/#{token_record.token}", params: params
      expect(token_record.reload.consumed_at).to be_nil
    end
  end

  context "in invite_only mode with a valid invitation token in session" do
    let(:invitation) { create(:invitation, invitable: workspace, email: "newml@example.com") }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      post accept_invitation_path(token: invitation.token)
    end

    it "creates the user, consumes the token, accepts the invitation" do
      expect {
        post "/magic_link_callback/#{token_record.token}", params: params
      }.to change(User, :count).by(1)

      expect(token_record.reload.consumed_at).to be_present
      expect(invitation.reload).to be_accepted

      new_user = User.find_by(email_address: "newml@example.com")
      expect(new_user.workspaces).to include(workspace)
    end
  end

  context "when the magic-link token gets consumed concurrently (race)" do
    let(:invitation) { create(:invitation, invitable: workspace, email: "newml@example.com") }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      post accept_invitation_path(token: invitation.token)
      # Simulate concurrent consumption
      allow(MagicLinkToken).to receive(:consume!).and_return(nil)
    end

    it "rolls back user creation when token consume returns nil" do
      expect {
        post "/magic_link_callback/#{token_record.token}", params: params
      }.not_to change(User, :count)

      expect(invitation.reload).to be_pending  # not consumed
    end
  end
end
```

- [ ] **Step 10.3: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb -e "new-user signup"
```

Expected: Gate-related tests fail — current code has no `signups_open?` check.

- [ ] **Step 10.4: Refactor `MagicLinkCallbacksController#create`**

Open `app/controllers/magic_link_callbacks_controller.rb`. Add `include Signupable` near the top of the class. Replace `#create` with:

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
    # Inside this block, @user has been saved by the concern. Attempting
    # to consume the magic-link token: if a concurrent request already
    # consumed it, raise Rollback so the User row is rolled back too.
    # ActiveRecord::Rollback unwinds without propagating — commit_signup_atomically
    # returns true, but token_consumed stays false and we route to :invalid.
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

- [ ] **Step 10.5: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb -e "new-user signup"
```

Expected: All 4 new tests pass.

- [ ] **Step 10.6: Run the full file for regressions**

```bash
mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb
```

Expected: 0 failures. Sign-in flow (`#show` for existing users) unaffected.

- [ ] **Step 10.7: Commit**

```bash
git add app/controllers/magic_link_callbacks_controller.rb spec/requests/magic_link_callbacks_spec.rb
git commit -m "feat(magic_link): gate new-user creation and consume invitations

MagicLinkCallbacksController#create now:
- Refuses new-user creation when SIGNUP_MODE=invite_only and no
  invitation token is in session (303 redirect to closed page).
- Uses Signupable#commit_signup_atomically to wrap user creation +
  magic-link token consumption + invitation acceptance in one transaction.

Existing-user magic link sign-in (#show) is unchanged."
```

---

## Task 11: OAuth buttons on closed page + CSP source-level spec

**Files:**

- Modify: `app/views/registrations/closed.html.erb`
- Create: `spec/initializers/content_security_policy_spec.rb`

- [ ] **Step 11.1: Add OAuth buttons to closed page**

Open `app/views/registrations/closed.html.erb`. Add `<%= render "shared/oauth_buttons" %>` ABOVE the existing "Sign in to an existing account" link block. Per the partial's internal `if oauth_enabled?` guard, the partial self-hides when no providers are configured.

The updated view structure should be:

```erb
<% content_for(:title) { t("registrations.closed.title") } %>

<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading">
    <%= t("registrations.closed.title") %>
  </h1>

  <p class="mt-6 text-base text-text-body">
    <%= safe_html(t("registrations.closed.body_html", app_name: t("app_name"))) %>
  </p>

  <div class="mt-12">
    <%= render "shared/oauth_buttons" %>
  </div>

  <div class="mt-6">
    <%= link_to t("registrations.closed.sign_in_link"),
                new_session_path,
                class: "btn-primary" %>
  </div>
</div>
```

- [ ] **Step 11.2: Create the CSP source-level spec**

Create `spec/initializers/content_security_policy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Content Security Policy" do
  let(:policy) { Rails.application.config.content_security_policy }
  let(:form_action) { policy.directives["form-action"] || [] }

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
    expect(form_action).to include(:self).or include("'self'")
  end
end
```

- [ ] **Step 11.3: Run the CSP spec**

```bash
mise exec -- bundle exec rspec spec/initializers/content_security_policy_spec.rb
```

Expected: 2 examples, 0 failures. (CSP form-action was updated during PR #172 cleanup to include the OAuth hosts.)

- [ ] **Step 11.4: Verify closed-page render via runner (sanity check)**

```bash
mise exec -- bundle exec rspec spec/requests/registrations_spec.rb -e "renders :closed"
```

Expected: tests that assert on the closed page still pass.

- [ ] **Step 11.5: Commit**

```bash
git add app/views/registrations/closed.html.erb spec/initializers/content_security_policy_spec.rb
git commit -m "feat(closed): show OAuth buttons on closed page + add CSP coverage spec

Closed page now offers OAuth sign-in as a one-click recovery for
existing users who landed here looking for sign-in. Partial self-hides
when no OAuth providers are configured.

CSP source-level spec asserts every configured OAuth provider has
its consent-screen host in form-action, catching the regression class
that surfaced in manual testing during PR #172 rollout."
```

---

## Task 12: Add system spec scenario for OAuth-via-button invited signup

**Files:**

- Modify: `spec/system/invite_only_signup_spec.rb`

- [ ] **Step 12.1: Add new scenario**

Open `spec/system/invite_only_signup_spec.rb`. After the existing scenarios, add:

```ruby
scenario "invited user signs up via OAuth (mocked Google)" do
  invitation = create(:invitation,
                      invitable: workspace,
                      email: "oauthinvitee@example.com",
                      invited_by: admin)

  OmniAuth.config.test_mode = true
  OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
    provider: "google_oauth2",
    uid: "sys-spec-uid",
    info: {
      email: "oauthinvitee@example.com",
      first_name: "OAuth",
      last_name: "Invitee",
      email_verified: true
    },
    credentials: { token: "tk", refresh_token: "rt", expires_at: 1.hour.from_now.to_i }
  )

  # Visit the invitation acceptance route (stashes token in session)
  post_accept_invitation(invitation.token)

  # On the registration page, click the Google OAuth button
  visit new_registration_path
  click_button I18n.t("oauth.sign_in_with", provider: "Google")

  # OAuth callback completes the flow
  expect(page).to have_current_path(root_path)

  new_user = User.find_by(email_address: "oauthinvitee@example.com")
  expect(new_user).to be_present
  expect(new_user.workspaces).to include(workspace)
  expect(invitation.reload).to be_accepted

  OmniAuth.config.mock_auth[:google_oauth2] = nil
  OmniAuth.config.test_mode = false
end
```

The `post_accept_invitation` helper should already exist in this spec file (Task 13 of PR #172). If not, define it inline or reuse the DOM-injected form pattern.

- [ ] **Step 12.2: Run the system spec**

```bash
mise exec -- bundle exec rspec spec/system/invite_only_signup_spec.rb
```

Expected: 4 examples, 0 failures (3 existing + 1 new). System specs are slow (Playwright); allow 30-60s.

- [ ] **Step 12.3: Commit**

```bash
git add spec/system/invite_only_signup_spec.rb
git commit -m "test(signup): system spec for invited OAuth signup end-to-end

Covers: invitation click → registration page → Google OAuth button →
mocked callback → user created → workspace membership → invitation
marked accepted. Exercises the full OAuth-via-button path including
the Turbo-disabled form submission introduced during PR #172 cleanup."
```

---

## Task 13: Final integration verification

- [ ] **Step 13.1: Run full test suite**

```bash
mise exec -- bundle exec rspec
```

Expected: 0 failures. Total example count should be roughly 2000+ (PR #172 baseline 1995 plus ~25 new from this PR).

- [ ] **Step 13.2: Run Lefthook pre-push**

```bash
mise exec -- lefthook run pre-push
```

Expected: brakeman, erb_lint, rspec, rubocop, tailwind_build all pass. Per project memory, do NOT skip with `LEFTHOOK=0`.

- [ ] **Step 13.3: Manual smoke test — invited OAuth signup**

In a browser with dev credentials set up:

1. Sign in as an admin user.
2. Create a workspace invitation for `invited-oauth@yourdomain.com` (use a Gmail address you control).
3. Sign out.
4. Click the invitation link in the email.
5. On the registration page, click "Sign in with Google" and authenticate as `invited-oauth@yourdomain.com`.
6. Verify: redirected to root, signed in as the new user, visible as a member of the inviting workspace.
7. Verify in console (`mise exec -- bin/rails console`): the invitation status is `:accepted` and the user has the workspace membership.

- [ ] **Step 13.4: Manual smoke test — unverified-email OAuth path (if accessible)**

If you have a way to force Google to return `email_verified: false` (some Google accounts behave this way for legacy reasons; otherwise this path is hard to manually exercise), test:

1. Create invitation as in 13.3.
2. Click invitation link.
3. Click "Sign in with Google".
4. After callback, you should NOT be signed in — should be redirected to sign-in with a "check your email" notice.
5. The pending Authentication should have `pending_invitation_token` set; the invitation should still be `:pending`.
6. Click the verification email link.
7. Verify: signed in, invitation now `:accepted`, workspace membership exists, Authentication's `pending_invitation_token` is nil.

This step is OPTIONAL — if you can't reliably force unverified email from Google, the request specs prove the path works.

- [ ] **Step 13.5: Manual smoke test — magic link gate**

1. In invite-only mode, send yourself a magic link from `/magic_link` (use an email NOT in the User table).
2. Click the link.
3. The new-user registration form should NOT appear — you should be redirected to the closed page (per the gate).
4. As an admin, create an invitation for that email and accept the invitation link in a new tab.
5. Now click the magic link again — registration should complete and you should land in the workspace.

- [ ] **Step 13.6: Push to remote and update PR #172**

This work belongs on the SAME branch as PR #172 (`feat/invite-required-signup`) per the user's "expanded scope this one time" direction:

```bash
git push origin feat/invite-required-signup
```

The push will run Lefthook again on the remote-bound HEAD. Watch for hooks to pass.

- [ ] **Step 13.7: Update the PR description**

The PR description should be amended to reflect the expanded scope. Add a section to the existing PR #172 description:

> ## Follow-up: Auth Flow Consistency (added during testing)
>
> While testing the initial gate, surfaced two additional gaps:
>
> - OAuth Branch 3 wasn't consuming invitations
> - Magic link new-user path bypassed the gate entirely
>
> Bundled into this PR per `feedback_pr_scoping_preference.md` (one-off scope expansion approved). Adds Signupable concern, deferred-acceptance design for unverified-email OAuth (new `pending_invitation_token` column), CSP source-level spec, and OAuth buttons on the closed page.
>
> See [docs/superpowers/specs/2026-05-25-auth-flow-consistency-design.md](docs/superpowers/specs/2026-05-25-auth-flow-consistency-design.md) for the design discussion.

---

## Notes for the implementer

1. **The verification controller location** — `Account::ConnectedAccountsController#verify` is dual-purpose (signed-in linking AND new-user OAuth verification, branching on `authenticated?`). The new behavior (sign in unauthenticated users + claim pending invitation) preserves the existing signed-in flow.

2. **`normalized_provider(auth_hash)`** is referenced in Tasks 7 and 8 — it's an existing private method in `OmniauthCallbacksController` (probably `auth_hash.provider == "google_oauth2" ? "google" : auth_hash.provider` or similar). Verify the exact method exists at implementation time.

3. **`oauth_attrs(auth_hash)`** is referenced in Tasks 7 and 8 — it's the existing helper that extracts oauth_token/oauth_refresh_token/oauth_expires_at from the auth_hash. Verify it exists.

4. **Re-rebase if Task 6 conflicts** — Task 6 removes `accept_pending_invitation!` from `RegistrationsController` (now in the concern). If you re-run earlier tasks for any reason, the removal must happen exactly once.

5. **Lefthook fails on rubocop / erb-lint** — fix the underlying issue. NEVER `LEFTHOOK=0` per project memory.

6. **System spec failures from Playwright instability** — re-run; if persistent, investigate per `feedback_check_dev_log_first` (tail dev log) before assuming the spec is broken.

7. **No `Co-Authored-By: Claude` trailers** — explicit project convention.
