# Invite-Required Signup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate new-user signup behind a configurable `SIGNUP_MODE` env var (default `invite_only`), with one policy POPO consulted from `RegistrationsController` (both actions) and the new-user branch of `OmniauthCallbacksController`. Existing users always retain sign-in; only new-account creation is gated.

**Architecture:** A single class-method API at `app/lib/signup_policy.rb` decides per-request whether signup is allowed (config-open OR valid invitation token in session). Controllers consult the policy via a memoized `signups_open?` helper on `ApplicationController`. New `closed.html.erb` view renders when the gate denies; `POST /registrations` returns 422 on gate-deny so Turbo handles it cleanly. User creation + invitation acceptance are wrapped in a single transaction to prevent two-browser races.

**Tech Stack:** Rails 8.1, RSpec, Capybara + Playwright, FactoryBot, ActiveSupport::CurrentAttributes, TailwindCSS 4 with semantic tokens.

**Spec:** `docs/superpowers/specs/2026-05-24-invite-required-signup-design.md` (commits `24056d7`, `be107d3`, `ac97683`).

---

## File Structure

**Files to CREATE:**

- `app/lib/signup_policy.rb` — class-method POPO; pure function of (config, token)
- `config/initializers/signup.rb` — boot-time validation of `SIGNUP_MODE`
- `app/views/registrations/closed.html.erb` — sibling template to `new.html.erb`
- `spec/lib/signup_policy_spec.rb` — unit spec
- `spec/system/invite_only_signup_spec.rb` — end-to-end happy path + closed page

**Files to MODIFY:**

- `config/application.rb` — add `config.x.signup.mode`
- `config/locales/en.yml` — add `app_name` and `registrations.closed.*` keys
- `app/models/invitation.rb` — add `acceptable?` method
- `app/controllers/application_controller.rb` — add memoized `signups_open?` helper
- `app/controllers/registrations_controller.rb` — gate `#new` and `#create`; wrap save + accept in transaction
- `app/controllers/omniauth_callbacks_controller.rb` — gate branch 3 only
- `app/views/pages/home.html.erb` — conditional sign-up CTA
- `.env.example` — document `SIGNUP_MODE`
- `spec/requests/registrations_spec.rb` — add gate behavior cases
- `spec/requests/omniauth_callbacks_spec.rb` — add gate + regression cases

---

## Task 1: Config and boot-time validation

**Files:**

- Modify: `config/application.rb`
- Create: `config/initializers/signup.rb`

- [ ] **Step 1.1: Add config to `application.rb`**

Open `config/application.rb`. Inside the `Application` class body, add this line after the existing config block (around line 26):

```ruby
config.x.signup.mode = ENV.fetch("SIGNUP_MODE", "invite_only").to_sym
```

- [ ] **Step 1.2: Create the validation initializer**

Create `config/initializers/signup.rb` with this exact content:

```ruby
valid_modes = %i[open invite_only]
unless valid_modes.include?(Rails.configuration.x.signup.mode)
  raise "Invalid SIGNUP_MODE: #{Rails.configuration.x.signup.mode.inspect}. " \
        "Must be one of: #{valid_modes.join(', ')}"
end
```

- [ ] **Step 1.3: Verify boot succeeds with default**

Run: `bin/rails runner "puts Rails.configuration.x.signup.mode"`

Expected: `invite_only`

- [ ] **Step 1.4: Verify boot fails with invalid mode**

Run: `SIGNUP_MODE=opn bin/rails runner "puts :ok" 2>&1 | head -5`

Expected: A `RuntimeError` mentioning `Invalid SIGNUP_MODE: :opn`. The command exits non-zero.

- [ ] **Step 1.5: Verify boot succeeds with explicit `:open`**

Run: `SIGNUP_MODE=open bin/rails runner "puts Rails.configuration.x.signup.mode"`

Expected: `open`

- [ ] **Step 1.6: Commit**

```bash
git add config/application.rb config/initializers/signup.rb
git commit -m "feat(signup): add SIGNUP_MODE config with boot-time validation"
```

---

## Task 2: `Invitation#acceptable?` method

**Files:**

- Modify: `app/models/invitation.rb`
- Test: `spec/models/invitation_spec.rb`

- [ ] **Step 2.1: Write the failing tests**

Open `spec/models/invitation_spec.rb` (create the file if it doesn't exist; if it does, find the appropriate `describe` block to nest these in). Add this `describe` block at the appropriate location:

```ruby
describe "#acceptable?" do
  it "returns true for a pending, non-expired invitation" do
    invitation = build(:invitation)
    expect(invitation.acceptable?).to be true
  end

  it "returns false for an expired invitation" do
    invitation = build(:invitation, :expired)
    expect(invitation.acceptable?).to be false
  end

  it "returns false for an accepted invitation" do
    invitation = build(:invitation, :accepted)
    expect(invitation.acceptable?).to be false
  end

  it "returns false for a declined invitation" do
    invitation = build(:invitation, :declined)
    expect(invitation.acceptable?).to be false
  end

  it "returns false for a revoked invitation" do
    invitation = build(:invitation, :revoked)
    expect(invitation.acceptable?).to be false
  end
end
```

- [ ] **Step 2.2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/invitation_spec.rb -e "#acceptable?"`

Expected: All 5 tests fail with `NoMethodError: undefined method 'acceptable?' for an instance of Invitation`.

- [ ] **Step 2.3: Implement the method**

Open `app/models/invitation.rb`. Add this method in the public section (not inside the `private` block):

```ruby
def acceptable?
  pending? && !expired?
end
```

Place it near the existing `expired?` method (around line 117) for cohesion.

- [ ] **Step 2.4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/invitation_spec.rb -e "#acceptable?"`

Expected: All 5 tests pass.

- [ ] **Step 2.5: Run full invitation spec for regressions**

Run: `bundle exec rspec spec/models/invitation_spec.rb`

Expected: All tests pass, no new failures.

- [ ] **Step 2.6: Commit**

```bash
git add app/models/invitation.rb spec/models/invitation_spec.rb
git commit -m "feat(invitation): add acceptable? predicate

Wraps pending? && !expired? for use by SignupPolicy without
duplicating the enum + expiry check at the call site."
```

---

## Task 3: `SignupPolicy` POPO

**Files:**

- Create: `app/lib/signup_policy.rb`
- Create: `spec/lib/signup_policy_spec.rb`

- [ ] **Step 3.1: Write the failing unit spec**

Create `spec/lib/signup_policy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SignupPolicy do
  describe ".allows_signup?" do
    context "when SIGNUP_MODE is :open" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      end

      it "returns true with no token" do
        expect(SignupPolicy.allows_signup?(token: nil)).to be true
      end

      it "returns true with a blank token" do
        expect(SignupPolicy.allows_signup?(token: "")).to be true
      end

      it "returns true even when the token does not match any invitation" do
        expect(SignupPolicy.allows_signup?(token: "nonsense")).to be true
      end
    end

    context "when SIGNUP_MODE is :invite_only" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      end

      it "returns false with no token" do
        expect(SignupPolicy.allows_signup?(token: nil)).to be false
      end

      it "returns false with a blank token" do
        expect(SignupPolicy.allows_signup?(token: "")).to be false
      end

      it "returns false with a non-matching token string" do
        expect(SignupPolicy.allows_signup?(token: "garbage")).to be false
      end

      it "returns false for an expired invitation token" do
        invitation = create(:invitation, :expired)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns false for an already-accepted invitation" do
        invitation = create(:invitation, :accepted)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns false for a declined invitation" do
        invitation = create(:invitation, :declined)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns false for a revoked invitation" do
        invitation = create(:invitation, :revoked)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns true for a valid pending invitation token" do
        invitation = create(:invitation)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be true
      end
    end
  end

  describe ".config_allows_signup?" do
    it "returns true when mode is :open" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      expect(SignupPolicy.config_allows_signup?).to be true
    end

    it "returns false when mode is :invite_only" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      expect(SignupPolicy.config_allows_signup?).to be false
    end
  end
end
```

- [ ] **Step 3.2: Run tests to verify they fail**

Run: `bundle exec rspec spec/lib/signup_policy_spec.rb`

Expected: All tests fail with `NameError: uninitialized constant SignupPolicy`.

- [ ] **Step 3.3: Implement `SignupPolicy`**

Create `app/lib/signup_policy.rb`:

```ruby
class SignupPolicy
  def self.allows_signup?(token: nil)
    config_allows_signup? || invitation_acceptable?(token)
  end

  def self.config_allows_signup?
    Rails.configuration.x.signup.mode == :open
  end

  def self.invitation_acceptable?(token)
    return false if token.blank?

    !!Invitation.find_by(token: token)&.acceptable?
  end
end
```

- [ ] **Step 3.4: Run tests to verify they pass**

Run: `bundle exec rspec spec/lib/signup_policy_spec.rb`

Expected: All tests pass.

- [ ] **Step 3.5: Commit**

```bash
git add app/lib/signup_policy.rb spec/lib/signup_policy_spec.rb
git commit -m "feat(signup): add SignupPolicy POPO

Single decision point for whether the gate allows signup.
Called from RegistrationsController (both actions) and the
new-user branch of OmniauthCallbacksController."
```

---

## Task 4: Memoized `signups_open?` helper on `ApplicationController`

**Files:**

- Modify: `app/controllers/application_controller.rb`
- Test: `spec/requests/application_controller_spec.rb` (create if missing)

- [ ] **Step 4.1: Write the failing memoization test**

Create `spec/requests/application_controller_spec.rb` if it doesn't exist, or add this `describe` block to the existing file:

```ruby
require "rails_helper"

RSpec.describe "ApplicationController#signups_open?", type: :request do
  context "when SIGNUP_MODE is :invite_only with a valid token in session" do
    let(:invitation) { create(:invitation) }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    end

    it "queries Invitation at most once per request even if helper is called multiple times" do
      # Visit the home page with the token in session by first hitting the
      # invitation acceptance route, then the home page.
      get accept_invitation_path(token: invitation.token), as: :html

      expect(Invitation).to receive(:find_by).with(token: invitation.token).at_most(:once).and_call_original

      get root_path
    end
  end
end
```

> If the invitation acceptance path is named differently (the spec audit cited `invitations/:token/accept` → `invitation_accepts#create`), substitute the correct path helper. Look up the actual helper name via `bundle exec rails routes | grep invitation`.

- [ ] **Step 4.2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/application_controller_spec.rb`

Expected: Either a `NoMethodError` (helper doesn't exist) or the expectation fires too many times (helper is unmemoized).

- [ ] **Step 4.3: Add the memoized helper**

Open `app/controllers/application_controller.rb`. After the existing `include` and `rescue_from` lines (around the top of the class), add:

```ruby
helper_method :signups_open?

def signups_open?
  @signups_open ||= SignupPolicy.allows_signup?(
    token: session[:pending_invitation_token]
  )
end
```

- [ ] **Step 4.4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/application_controller_spec.rb`

Expected: Test passes.

- [ ] **Step 4.5: Commit**

```bash
git add app/controllers/application_controller.rb spec/requests/application_controller_spec.rb
git commit -m "feat(signup): add memoized signups_open? helper

Available to all controllers and views via helper_method.
Memoization on the per-request controller instance prevents
multi-query hits when partials consult the helper repeatedly."
```

---

## Task 5: Closed-page locale keys

**Files:**

- Modify: `config/locales/en.yml`

- [ ] **Step 5.1: Add the locale keys**

Open `config/locales/en.yml`. Find the existing `en:` root (around line 30). Add these keys under `en:` (alphabetize by top-level key — `app_name` and `registrations` near each other):

```yaml
en:
  hello: "Hello world"   # existing key, keep
  app_name: "ModelRails"
  registrations:
    closed:
      title: "Sign-ups are by invitation only"
      body_html: |
        If your team uses %{app_name}, ask your workspace administrator
        to send you an invitation. Already have an invitation email?
        Click the link in that message to get started.
      sign_in_link: "Sign in to an existing account"
      oauth_blocked: "Sign-ups are by invitation only. Please ask your workspace administrator for an invitation."
```

> If `app_name` already exists elsewhere in the file or in another locale file, do not duplicate — reuse the existing key. Search first: `grep -rn "app_name" config/locales/`.

- [ ] **Step 5.2: Verify the locale parses**

Run: `bin/rails runner 'puts I18n.t("registrations.closed.title")'`

Expected: `Sign-ups are by invitation only`

- [ ] **Step 5.3: Verify the interpolation works**

Run: `bin/rails runner 'puts I18n.t("registrations.closed.body_html", app_name: I18n.t("app_name"))'`

Expected: Output contains the literal text `If your team uses ModelRails, ask your workspace administrator...`

- [ ] **Step 5.4: Commit**

```bash
git add config/locales/en.yml
git commit -m "feat(i18n): add closed-signup locale keys with app_name interpolation"
```

---

## Task 6: `closed.html.erb` view

**Files:**

- Create: `app/views/registrations/closed.html.erb`

- [ ] **Step 6.1: Create the view**

Create `app/views/registrations/closed.html.erb` with this exact content:

```erb
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading">
    <%= t("registrations.closed.title") %>
  </h1>

  <p class="mt-6 text-base text-text-body">
    <%= safe_html(t("registrations.closed.body_html", app_name: t("app_name"))) %>
  </p>

  <div class="mt-12">
    <%= link_to t("registrations.closed.sign_in_link"),
                new_session_path,
                class: "btn-primary" %>
  </div>
</div>
```

- [ ] **Step 6.2: Verify the view renders standalone**

Run: `bundle exec rails runner 'puts ApplicationController.render(template: "registrations/closed").length > 0'`

Expected: `true`

If this errors with "missing helper" or "missing method `safe_html`", confirm `safe_html` is available app-wide via `ApplicationHelper` or similar. If not, find the right helper module include and reconcile.

- [ ] **Step 6.3: Commit**

```bash
git add app/views/registrations/closed.html.erb
git commit -m "feat(signup): add closed-signup view template

Sibling to registrations/new.html.erb. Uses semantic
text tokens (text-text-heading, text-text-body) for dark-mode
inheritance and AAA contrast. mt-6/mt-12 spacing chosen
per panel review for an unhurried, intentional feel."
```

---

## Task 7: Gate `RegistrationsController#new`

**Files:**

- Modify: `app/controllers/registrations_controller.rb`
- Test: `spec/requests/registrations_spec.rb`

- [ ] **Step 7.1: Write failing request specs**

Open `spec/requests/registrations_spec.rb`. Find the existing `describe "GET /signup"` (or similar) block. Add these contexts:

```ruby
describe "GET /signup" do
  context "when signups are open via config" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

    it "renders :new" do
      get new_registration_path
      expect(response).to render_template(:new)
      expect(response).to have_http_status(:ok)
    end
  end

  context "when SIGNUP_MODE is :invite_only" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

    it "renders :closed when there is no invitation token in session" do
      get new_registration_path
      expect(response).to render_template(:closed)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("registrations.closed.title"))
    end

    it "renders :new when a valid invitation token is in session" do
      invitation = create(:invitation)
      # Set the session token by hitting the invitation acceptance route.
      get accept_invitation_path(token: invitation.token)

      get new_registration_path
      expect(response).to render_template(:new)
    end
  end
end
```

- [ ] **Step 7.2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "GET /signup"`

Expected: The `:invite_only` tests fail because `#new` always renders `:new`.

- [ ] **Step 7.3: Update `#new` action**

Open `app/controllers/registrations_controller.rb`. Find the existing `def new` (around line 383). Replace its body:

```ruby
def new
  if signups_open?
    @user = User.new
  else
    render :closed
  end
end
```

- [ ] **Step 7.4: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "GET /signup"`

Expected: All three new tests pass.

- [ ] **Step 7.5: Run the full registrations spec for regressions**

Run: `bundle exec rspec spec/requests/registrations_spec.rb`

Expected: All tests pass.

- [ ] **Step 7.6: Commit**

```bash
git add app/controllers/registrations_controller.rb spec/requests/registrations_spec.rb
git commit -m "feat(signup): gate RegistrationsController#new on signup mode

Renders :closed template when signups are not open. Same
URL, two states — RESTful state-based rendering."
```

---

## Task 8: Gate `RegistrationsController#create` (422 on deny)

**Files:**

- Modify: `app/controllers/registrations_controller.rb`
- Test: `spec/requests/registrations_spec.rb`

- [ ] **Step 8.1: Write failing request specs**

In `spec/requests/registrations_spec.rb`, add to the `describe "POST /signup"` block (or create one if missing):

```ruby
describe "POST /signup" do
  let(:valid_params) do
    {
      user: {
        email_address: "newuser@example.com",
        first_name: "New",
        last_name: "User",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      }
    }
  end

  context "when SIGNUP_MODE is :invite_only with no token" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

    it "renders :closed with status 422 and does not create a user" do
      expect {
        post registration_path, params: valid_params
      }.not_to change(User, :count)

      expect(response).to render_template(:closed)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "when SIGNUP_MODE is :invite_only with a valid token" do
    let(:invitation) { create(:invitation, email: "newuser@example.com") }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      get accept_invitation_path(token: invitation.token)  # stash token in session
    end

    it "creates the user and accepts the invitation" do
      expect {
        post registration_path, params: valid_params
      }.to change(User, :count).by(1)

      expect(invitation.reload).to be_accepted
    end
  end
end
```

- [ ] **Step 8.2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "POST /signup"`

Expected: The new `:invite_only with no token` test fails — currently a user IS created (no gate).

- [ ] **Step 8.3: Update `#create` action**

Open `app/controllers/registrations_controller.rb`. Find the existing `def create` (around line 387). At the top of the method body (before the existing logic), add:

```ruby
def create
  unless signups_open?
    render :closed, status: :unprocessable_entity
    return
  end

  # ... existing create logic remains below, unchanged for now
```

- [ ] **Step 8.4: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "POST /signup"`

Expected: Both new tests pass.

- [ ] **Step 8.5: Commit**

```bash
git add app/controllers/registrations_controller.rb spec/requests/registrations_spec.rb
git commit -m "feat(signup): gate POST /signup with 422 deny

422 (not 403) because Turbo's Form adapter treats 4xx as
form-replace; 422 is the idiomatic 'I refuse to process'
status that Turbo handles cleanly."
```

---

## Task 9: Transactional user creation + invitation acceptance

**Files:**

- Modify: `app/controllers/registrations_controller.rb`
- Test: `spec/requests/registrations_spec.rb`

- [ ] **Step 9.1: Write failing race-condition test**

Add to `spec/requests/registrations_spec.rb`:

```ruby
describe "POST /signup race condition handling" do
  let(:invitation) { create(:invitation, email: "racer@example.com") }
  let(:valid_params) do
    {
      user: {
        email_address: "racer@example.com",
        first_name: "Racer",
        last_name: "Test",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      }
    }
  end

  before do
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    get accept_invitation_path(token: invitation.token)  # stash token
  end

  it "rolls back user creation when invitation acceptance fails" do
    # Simulate the invitation being consumed between gate-pass and accept!
    allow_any_instance_of(Invitation).to receive(:accept!).and_raise(
      ActiveRecord::RecordInvalid.new(invitation)
    )

    expect {
      post registration_path, params: valid_params
    }.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] **Step 9.2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "race condition"`

Expected: Test fails — the User IS created today because user.save and accept! are not in the same transaction.

- [ ] **Step 9.3: Wrap user creation + invitation acceptance in a transaction**

Open `app/controllers/registrations_controller.rb`. The existing `#create` action (after the gate added in Task 8) currently does something like:

```ruby
@user = User.new(registration_params)
if @user.save
  # build email authentication, generate verification token, ...
  start_new_session_for(@user)
  accept_pending_invitation(@user)
  redirect_to root_path, notice: ...
else
  render :new, status: :unprocessable_entity
end
```

Refactor it to wrap user creation and invitation acceptance in a single transaction. Replace the post-gate body with:

```ruby
@user = User.new(registration_params)

begin
  ApplicationRecord.transaction do
    @user.save!
    # NOTE: the existing post-save side effects (email authentication,
    # verification token generation, start_new_session_for) stay here
    # in their original order, immediately after @user.save!
    create_email_authentication_for(@user)
    start_new_session_for(@user)
    accept_pending_invitation!(@user)
  end

  send_verification_email_for(@user)
  redirect_to root_path, notice: t("registrations.create.success")
rescue ActiveRecord::RecordInvalid => e
  if e.record.is_a?(Invitation) || e.record.is_a?(User)
    # Either invitation was consumed mid-flight (race) or user-side
    # validation failed. The transaction rolled back either way.
    @user = User.new(registration_params)  # re-build for form re-render
    flash.now[:alert] = t("registrations.create.invitation_consumed") if e.record.is_a?(Invitation)
    render :new, status: :unprocessable_entity
  else
    raise
  end
end
```

The exact names of the helper methods (`create_email_authentication_for`, `send_verification_email_for`, `accept_pending_invitation!`) depend on what already exists in the controller. Reconcile by:

1. Reading the existing `#create` body and the `#accept_pending_invitation` helper (currently lines 387-419 per the spec audit).
2. Moving the verification-email-sending OUTSIDE the transaction (deliver_later inside a transaction queues a job that runs even on rollback — the project memory warns about this).
3. Renaming `accept_pending_invitation` to `accept_pending_invitation!` and removing its internal guards (`pending? && !expired?`) — `accept!` already validates these atomically with a row lock, raising `RecordInvalid` if not pending.

The updated helper:

```ruby
def accept_pending_invitation!(user)
  token = session.delete(:pending_invitation_token)
  return if token.blank?

  invitation = Invitation.find_by(token: token)
  invitation&.accept!(user)
end
```

Add the corresponding flash i18n key in `config/locales/en.yml`:

```yaml
registrations:
  closed:
    # existing keys
  create:
    success: "Welcome! Please check your email to verify your account."
    invitation_consumed: "That invitation is no longer valid. Please ask your workspace administrator for a new one."
```

(Reuse `registrations.create.success` if it already exists.)

- [ ] **Step 9.4: Run race-condition test to verify it passes**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "race condition"`

Expected: Test passes — when `accept!` raises, the User record is gone.

- [ ] **Step 9.5: Run the full registrations spec for regressions**

Run: `bundle exec rspec spec/requests/registrations_spec.rb`

Expected: All tests pass. If the test for the happy path now sends fewer emails, adjust the expectation to count post-commit (the email is now sent AFTER the transaction, not inside it).

- [ ] **Step 9.6: Commit**

```bash
git add app/controllers/registrations_controller.rb spec/requests/registrations_spec.rb config/locales/en.yml
git commit -m "fix(signup): wrap user creation + invitation acceptance in transaction

Prevents the two-browser race where Tab A and Tab B both submit
the same invitation token: Tab B would create a User but fail
invitation acceptance, leaving a half-created account without
the inviting workspace membership.

The verification email is dispatched AFTER the transaction commits
(deliver_later inside a transaction can queue a job that runs even
on rollback)."
```

---

## Task 10: Gate `OmniauthCallbacksController` (branch 3 only)

**Files:**

- Modify: `app/controllers/omniauth_callbacks_controller.rb`
- Test: `spec/requests/omniauth_callbacks_spec.rb`

- [ ] **Step 10.1: Write failing tests for all three branches**

In `spec/requests/omniauth_callbacks_spec.rb`, add this `describe` block:

```ruby
describe "SIGNUP_MODE gate behavior" do
  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "12345",
      info: { email: "newuser@example.com", first_name: "New", last_name: "User" },
      extra: { raw_info: { email_verified: true } }
    )
  end

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth_hash
  end

  context "when SIGNUP_MODE is :invite_only with no token (Branch 3, new user)" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

    it "redirects to new_registration_path with 303 and creates no User or Authentication" do
      expect {
        post "/auth/google_oauth2/callback"
      }.to not_change(User, :count).and not_change(Authentication, :count)

      expect(response).to redirect_to(new_registration_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
    end
  end

  context "when SIGNUP_MODE is :invite_only with a valid invitation token in session" do
    let(:invitation) { create(:invitation, email: "newuser@example.com") }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      get accept_invitation_path(token: invitation.token)
    end

    it "creates a new user via OAuth and signs in" do
      expect {
        post "/auth/google_oauth2/callback"
      }.to change(User, :count).by(1)
    end
  end

  context "when SIGNUP_MODE is :invite_only and an existing user signs in via OAuth (Branch 1)" do
    let!(:user) { create(:user, email_address: "existing@example.com") }
    let!(:authentication) do
      create(:authentication, user: user, provider: "google_oauth2", uid: "existing-uid", verified_at: Time.current)
    end
    let(:existing_auth_hash) do
      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "existing-uid",
        info: { email: "existing@example.com" }
      )
    end

    before do
      OmniAuth.config.mock_auth[:google_oauth2] = existing_auth_hash
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    end

    it "signs in the existing user (gate must NOT block branch 1)" do
      post "/auth/google_oauth2/callback"
      expect(response).to redirect_to(root_path)
      # Existing user signed in; no new User created.
      expect(User.count).to eq(1)
    end
  end

  context "when SIGNUP_MODE is :invite_only and a signed-in user links a new OAuth provider (Branch 2)" do
    let(:user) { create(:user) }
    let(:link_auth_hash) do
      OmniAuth::AuthHash.new(
        provider: "github",
        uid: "github-uid",
        info: { email: user.email_address }
      )
    end

    before do
      OmniAuth.config.mock_auth[:github] = link_auth_hash
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      sign_in_via_helper(user)  # adapt to existing test helper name
    end

    it "links the new authentication (gate must NOT block branch 2)" do
      expect {
        post "/auth/github/callback"
      }.to change { user.authentications.count }.by(1)
    end
  end
end
```

> Adapt `sign_in_via_helper` to whatever sign-in helper the existing OAuth callbacks spec uses (probably defined in `spec/support/authentication_helpers.rb` or similar). Grep `spec/` for an existing helper.

- [ ] **Step 10.2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/omniauth_callbacks_spec.rb -e "SIGNUP_MODE gate"`

Expected: The "no token" test fails because a User IS created today. The other tests' expectations should already be true (existing behavior preserves branches 1 and 2), so they'll pass even before the change — they exist as regression pins.

- [ ] **Step 10.3: Add the gate to branch 3**

Open `app/controllers/omniauth_callbacks_controller.rb`. Find `handle_new_user_oauth(auth_hash)` (around line 104). At the very top of that method body, before any other logic, add:

```ruby
def handle_new_user_oauth(auth_hash)
  unless signups_open?
    redirect_to new_registration_path,
                alert: t("registrations.closed.oauth_blocked"),
                status: :see_other
    return
  end

  # ... existing handle_new_user_oauth body unchanged below
```

- [ ] **Step 10.4: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/omniauth_callbacks_spec.rb -e "SIGNUP_MODE gate"`

Expected: All four new tests pass. Branch 1 (existing user) and Branch 2 (linking) remain unaffected.

- [ ] **Step 10.5: Run full OAuth callbacks spec for regressions**

Run: `bundle exec rspec spec/requests/omniauth_callbacks_spec.rb`

Expected: All tests pass.

- [ ] **Step 10.6: Commit**

```bash
git add app/controllers/omniauth_callbacks_controller.rb spec/requests/omniauth_callbacks_spec.rb
git commit -m "feat(signup): gate new-user OAuth creation on signup mode

The gate sits only in handle_new_user_oauth (Branch 3).
Existing-identity sign-in (Branch 1) and signed-in-user
linking (Branch 2) are unaffected — explicit regression
specs pin this."
```

---

## Task 11: Conditional sign-up CTA on landing page

**Files:**

- Modify: `app/views/pages/home.html.erb`
- Test: `spec/requests/pages_spec.rb` (create or extend)

- [ ] **Step 11.1: Write failing test**

Add to (or create) `spec/requests/pages_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Landing page sign-up CTA", type: :request do
  context "when SIGNUP_MODE is :open" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

    it "shows the Sign up CTA on the landing page" do
      get root_path
      expect(response.body).to include(new_registration_path)
    end
  end

  context "when SIGNUP_MODE is :invite_only without a token" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

    it "does NOT show the Sign up CTA on the landing page" do
      get root_path
      expect(response.body).not_to include(new_registration_path)
    end

    it "still shows the Sign in CTA" do
      get root_path
      expect(response.body).to include(new_session_path)
    end
  end
end
```

- [ ] **Step 11.2: Run tests to verify the closed-mode test fails**

Run: `bundle exec rspec spec/requests/pages_spec.rb`

Expected: The `:invite_only` "does NOT show" test fails — today the page always links to `new_registration_path`.

- [ ] **Step 11.3: Wrap the CTA in a conditional**

Open `app/views/pages/home.html.erb`. The spec audit identified two CTAs that link to `new_registration_path`:

1. Hero section — around line 3-9, passes `cta_primary_path: new_registration_path` to `shared/hero`
2. CTA section near bottom — around line 33-36, a `link_to t("pages.home.cta.button"), new_registration_path`

For each one, wrap with `if signups_open?` (or set the path conditionally if it's a partial parameter). Concretely:

For the hero block, change:

```erb
<%= render "shared/hero",
           cta_primary: t("pages.home.hero.cta_primary"),
           cta_primary_path: new_registration_path,
           cta_secondary: ...,
           cta_secondary_path: ... %>
```

to:

```erb
<%= render "shared/hero",
           cta_primary: signups_open? ? t("pages.home.hero.cta_primary") : nil,
           cta_primary_path: signups_open? ? new_registration_path : nil,
           cta_secondary: ...,
           cta_secondary_path: ... %>
```

(If `shared/hero` already handles `nil` cta_primary by hiding the button, this works directly. If not, you may need a small partial update — keep changes minimal.)

For the bottom CTA section, wrap the entire `link_to` block:

```erb
<% if signups_open? %>
  <%= link_to t("pages.home.cta.button"),
              new_registration_path,
              class: "inline-flex items-center px-6 py-3 rounded-md bg-interactive hover:bg-interactive-hover ..." %>
<% end %>
```

Use the actual existing class string from the file — don't introduce new classes.

- [ ] **Step 11.4: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/pages_spec.rb`

Expected: All three tests pass.

- [ ] **Step 11.5: Manually verify**

Run `bin/dev` in one terminal, then in another:

```bash
curl -s http://localhost:3000/ | grep -c "/sign_up"  # should be 0 for invite_only (default)
SIGNUP_MODE=open bin/dev  # restart in open mode
curl -s http://localhost:3000/ | grep -c "/sign_up"  # should be > 0
```

Stop both servers when done.

- [ ] **Step 11.6: Commit**

```bash
git add app/views/pages/home.html.erb spec/requests/pages_spec.rb
git commit -m "feat(signup): hide Sign up CTA on landing page when invite-only

Sign in CTA stays visible in all modes — existing users
must always be able to reach the sign-in flow."
```

---

## Task 12: Document `SIGNUP_MODE` in `.env.example`

**Files:**

- Modify: `.env.example`

- [ ] **Step 12.1: Add the documentation block**

Open `.env.example`. After the existing `# === Kamal deployment ===` section (after the `KAMAL_REGISTRY_PASSWORD` line), append:

```bash

# === Signup gating ===

# Controls public signup behavior.
# - "invite_only" (default): /registrations/new is closed unless visitor
#   has a valid invitation token in session
# - "open": anyone can sign up at /registrations/new
# SIGNUP_MODE=invite_only
```

- [ ] **Step 12.2: Commit**

```bash
git add .env.example
git commit -m "docs(env): document SIGNUP_MODE env var"
```

---

## Task 13: End-to-end system spec

**Files:**

- Create: `spec/system/invite_only_signup_spec.rb`

- [ ] **Step 13.1: Create the system spec**

Create `spec/system/invite_only_signup_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Invite-only signup flow", type: :system, js: true do
  let(:admin) { create(:user) }
  let(:workspace) { create(:workspace, owner: admin) }

  before do
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
  end

  scenario "invited user signs up successfully" do
    invitation = create(:invitation,
                        invitable: workspace,
                        email: "newuser@example.com",
                        invited_by: admin)

    visit accept_invitation_path(token: invitation.token)

    # Token now in session; the closed page must NOT be shown.
    expect(page).not_to have_content(I18n.t("registrations.closed.title"))
    expect(page).to have_field("user_email_address")

    fill_in "user_email_address", with: "newuser@example.com"
    fill_in "user_first_name", with: "Invited"
    fill_in "user_last_name", with: "User"
    fill_in "user_password", with: "supersecret123"
    fill_in "user_password_confirmation", with: "supersecret123"
    click_button I18n.t("registrations.new.submit")

    expect(page).to have_current_path(root_path)
    expect(invitation.reload).to be_accepted

    new_user = User.find_by(email_address: "newuser@example.com")
    expect(new_user).to be_present
    expect(new_user.workspaces).to include(workspace)
  end

  scenario "uninvited visitor sees the closed page with no Sign-up CTA on landing" do
    visit root_path

    expect(page).not_to have_link(I18n.t("pages.home.hero.cta_primary"))
    expect(page).to have_link(I18n.t("pages.home.hero.cta_secondary"))

    visit new_registration_path
    expect(page).to have_content(I18n.t("registrations.closed.title"))
    expect(page).to have_link(I18n.t("registrations.closed.sign_in_link"),
                              href: new_session_path)

    # AAA accessibility scan
    expect(page).to be_axe_clean.according_to(:wcag22aaa)
  end

  scenario "axe-core AAA scan on the closed page passes" do
    visit new_registration_path
    expect(page).to have_content(I18n.t("registrations.closed.title"))
    expect(page).to be_axe_clean.according_to(:wcag22aaa)
  end
end
```

> If the project's axe matcher uses a different DSL (e.g., `expect_axe_audit_to_pass`), substitute. Grep `spec/` for existing axe usage to find the right matcher: `grep -rn "axe" spec/system/`.

- [ ] **Step 13.2: Run the system spec**

Run: `bundle exec rspec spec/system/invite_only_signup_spec.rb`

Expected: All three scenarios pass.

Common issues:

- If "uninvited visitor" scenario fails on the landing-page CTA assertion, the home page partial may render the CTA via a path other than `new_registration_path` — adjust the assertion to match the actual link text.
- If the axe scan fails on AAA, inspect the specific violation and fix the offending markup in `closed.html.erb`.

- [ ] **Step 13.3: Run the full test suite for regressions**

Run: `bundle exec rspec`

Expected: All tests pass. SimpleCov reports ≥40% coverage.

- [ ] **Step 13.4: Manual screen-reader walkthrough (acceptance criterion)**

Open the closed page in a browser with a screen reader active (VoiceOver on macOS — Cmd+F5; or NVDA on Windows). Tab through the page and listen for:

1. The heading reads first ("Sign-ups are by invitation only").
2. The body paragraph reads coherently with `app_name` interpolated.
3. The "Sign in to an existing account" link is announced as a link, not a button.
4. Tab order is heading → body → sign-in link (no traps, no surprises).

If any of these fail, fix `closed.html.erb` before committing.

- [ ] **Step 13.5: Commit**

```bash
git add spec/system/invite_only_signup_spec.rb
git commit -m "test(signup): end-to-end system spec for invite-only flow

Covers happy path (invited user completes signup) plus
the closed page rendering and a WCAG 2.2 AAA axe scan."
```

---

## Task 14: Final integration verification

- [ ] **Step 14.1: Run full test suite**

Run: `bundle exec rspec`

Expected: All tests pass.

- [ ] **Step 14.2: Run Lefthook pre-push checks locally**

Run: `lefthook run pre-push`

Expected: Clean pass. Per project memory, never bypass with `LEFTHOOK=0`; fix any issues that arise.

- [ ] **Step 14.3: Manual smoke test**

In one terminal:

```bash
bin/dev  # boots with SIGNUP_MODE=invite_only by default
```

In a browser, verify:

1. Visit `http://localhost:3000/` — no "Sign up" CTA visible.
2. Visit `http://localhost:3000/registrations/new` — closed page renders.
3. Visit any unused invitation acceptance link (create one via `bin/rails console`) — registration form renders.
4. Restart with `SIGNUP_MODE=open bin/dev` — verify CTA is visible and `/registrations/new` renders the form.

- [ ] **Step 14.4: Final commit (if any cleanup needed)**

If any small fixes surfaced during smoke testing, commit them with a clear message. Otherwise, this task has no commit.

---

## Notes for the implementer

1. **The race-condition test in Task 9 uses `allow_any_instance_of`**, which is generally a smell. Per the panel review (Joël Quenneville), prefer a more specific mock if you can isolate the invitation instance: `allow(Invitation).to receive(:find_by).with(token: invitation.token).and_return(invitation); allow(invitation).to receive(:accept!).and_raise(...)`.

2. **The `accept_pending_invitation!` rename** in Task 9 changes existing code semantics — the helper previously did not raise. Search for other callers via `grep -rn "accept_pending_invitation" app/ spec/` before the rename to make sure you catch them all.

3. **Mailer outside the transaction.** Per project memory: `Mailer.deliver_later` calls must be OUTSIDE database transactions. The verification email send in `#create` must happen after the `ApplicationRecord.transaction do ... end` block closes successfully.

4. **OAuth credentials structure is INTENTIONALLY UNCHANGED in this plan.** Credentials remain in flat `google:`/`github:` top-level keys. The migration to nested `oauth:` namespacing is a separate follow-up PR per the panel review (see spec section "Out-of-scope follow-ups").

5. **Don't bypass Lefthook.** Per project memory, never use `LEFTHOOK=0` to skip pre-push hooks. If a hook fails, fix the underlying issue.

6. **Commit message style.** Per project memory: lean, action-oriented Conventional Commits. No Co-Authored-By trailers.
