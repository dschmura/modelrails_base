# Verified OAuth Account Linking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the OAuth account-linking security gap where signed-in users can link providers without proof of email ownership. Add a token-based confirmation flow when OAuth-returned email differs from the user's primary email; auto-verify when emails match.

**Architecture:** The schema columns (`verification_token`, `verification_sent_at`, `verified_at`) already exist on `authentications`; this is mostly wiring. Add an `email` column to capture OAuth-returned email per row. Refactor `OmniauthCallbacksController#create` into named branches (existing auth, signed-in linking, new user). Add two new actions to `Account::ConnectedAccountsController` (`#verify`, `#resend_verification`). New mailer method, two view changes, comprehensive request specs, one happy-path system spec.

**Tech Stack:** Rails 8.1 + ActiveRecord migrations, RSpec request/model/mailer/system specs, OmniAuth, ActionMailer with letter_opener_web in dev, Solid Queue for `deliver_later`.

**Spec:** [docs/superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md](docs/superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md)

---

## File Map

| Path | Action |
| ---- | ------ |
| `db/migrate/<ts>_add_email_to_authentications.rb` | Create |
| `app/models/authentication.rb` | Modify (add ~25 lines: scopes, predicates, mutators) |
| `app/mailers/authentication_mailer.rb` | Modify (add `link_verification_email`) |
| `app/views/authentication_mailer/link_verification_email.html.erb` | Create |
| `app/views/authentication_mailer/link_verification_email.text.erb` | Create |
| `app/controllers/omniauth_callbacks_controller.rb` | Refactor `#create` into named branches |
| `app/controllers/account/connected_accounts_controller.rb` | Add `#verify`, `#resend_verification`; fix `#destroy` last-method check |
| `app/views/account/connected_accounts/index.html.erb` | Modify (pending row + post-OAuth banner) |
| `config/routes.rb` | Add `:resend_verification` member + `verify/:token` collection routes |
| `config/locales/en/account.en.yml` | Add new keys, replace one |
| `config/locales/en/oauth.en.yml` | Add new keys for callback flash messages |
| `config/locales/en/mailers.en.yml` | Add `authentication_mailer.link_verification_email.*` keys |
| `config/initializers/filter_parameter_logging.rb` | Add `:token` to filter list (verify first) |
| `spec/models/authentication_spec.rb` | Modify (new method specs) |
| `spec/mailers/authentication_mailer_spec.rb` | Modify (new method spec) |
| `spec/requests/omniauth_callbacks_spec.rb` | Modify (new branch coverage) |
| `spec/requests/account/connected_accounts_spec.rb` | Modify (verify, resend, destroy edge cases) |
| `spec/system/oauth_link_verification_spec.rb` | Create (one happy-path system spec) |

---

## Task 1 — Migration: add `email` column to authentications

**Files:**

- Create: `db/migrate/<ts>_add_email_to_authentications.rb`

- [ ] **Step 1.1: Generate migration**

Run: `mise exec -- bin/rails generate migration AddEmailToAuthentications email:string`

- [ ] **Step 1.2: Verify migration body matches spec**

Open the generated file. It should be exactly:

```ruby
class AddEmailToAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :authentications, :email, :string
  end
end
```

If Rails generated something different, replace with the above.

- [ ] **Step 1.3: Run the migration**

Run: `mise exec -- bin/rails db:migrate`

Expected: migration runs successfully, `db/schema.rb` regenerates with new schema version + the `email` column on `authentications`.

- [ ] **Step 1.4: Confirm column added**

Run: `grep -A 15 'create_table "authentications"' db/schema.rb | grep email`

Expected output: `t.string "email"` appearing in the authentications table definition.

- [ ] **Step 1.5: Run full suite for regression**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1033+ examples, 0 failures.

- [ ] **Step 1.6: Commit**

```bash
git add db/migrate/*_add_email_to_authentications.rb db/schema.rb
git commit -m "feat: add email column to authentications for verification linking"
```

---

## Task 2 — Authentication model: predicates, scopes, mutators (TDD)

**Files:**

- Modify: `app/models/authentication.rb`
- Modify: `spec/models/authentication_spec.rb`

- [ ] **Step 2.1: Write failing model specs**

In `spec/models/authentication_spec.rb`, append (or merge into existing describe block):

```ruby
RSpec.describe Authentication, type: :model do
  describe "verification state" do
    let(:auth) { build(:authentication) }

    describe "#verified?" do
      it "is true when verified_at is present" do
        auth.verified_at = Time.current
        expect(auth.verified?).to be true
      end

      it "is false when verified_at is nil" do
        auth.verified_at = nil
        expect(auth.verified?).to be false
      end
    end

    describe "#pending?" do
      it "is true when verified_at is nil and verification_token is present" do
        auth.verified_at = nil
        auth.verification_token = "tok"
        expect(auth.pending?).to be true
      end

      it "is false when verified_at is set" do
        auth.verified_at = Time.current
        auth.verification_token = "tok"
        expect(auth.pending?).to be false
      end

      it "is false when verification_token is nil" do
        auth.verified_at = nil
        auth.verification_token = nil
        expect(auth.pending?).to be false
      end
    end

    describe "#token_expired?" do
      it "is true when verification_sent_at is older than 24 hours" do
        auth.verification_sent_at = 25.hours.ago
        expect(auth.token_expired?).to be true
      end

      it "is false when within 24 hours" do
        auth.verification_sent_at = 1.hour.ago
        expect(auth.token_expired?).to be false
      end

      it "is false when verification_sent_at is nil" do
        auth.verification_sent_at = nil
        expect(auth.token_expired?).to be false
      end
    end

    describe "#generate_verification_token!" do
      let(:auth) { create(:authentication, verified_at: Time.current, verification_token: nil) }

      it "sets a new token" do
        auth.generate_verification_token!
        expect(auth.verification_token).to be_present
        expect(auth.verification_token.length).to be >= 32
      end

      it "sets verification_sent_at to now" do
        freeze_time do
          auth.generate_verification_token!
          expect(auth.verification_sent_at).to eq(Time.current)
        end
      end

      it "clears verified_at (token regeneration invalidates prior verification)" do
        auth.generate_verification_token!
        expect(auth.verified_at).to be_nil
      end
    end

    describe "#verify!" do
      let(:auth) do
        create(:authentication,
          verified_at: nil,
          verification_token: "abc123",
          verification_sent_at: 1.hour.ago)
      end

      it "sets verified_at to now" do
        freeze_time do
          auth.verify!
          expect(auth.verified_at).to eq(Time.current)
        end
      end

      it "clears verification_token" do
        auth.verify!
        expect(auth.verification_token).to be_nil
      end

      it "clears verification_sent_at" do
        auth.verify!
        expect(auth.verification_sent_at).to be_nil
      end
    end
  end

  describe "scopes" do
    let!(:verified) { create(:authentication, verified_at: Time.current, verification_token: nil) }
    let!(:pending)  { create(:authentication, verified_at: nil, verification_token: "tok", verification_sent_at: 1.hour.ago) }

    it ".verified returns rows with verified_at set" do
      expect(Authentication.verified).to include(verified)
      expect(Authentication.verified).not_to include(pending)
    end

    it ".pending returns rows with verified_at nil and token present" do
      expect(Authentication.pending).to include(pending)
      expect(Authentication.pending).not_to include(verified)
    end
  end
end
```

- [ ] **Step 2.2: Run model specs to verify they fail**

Run: `mise exec -- bundle exec rspec spec/models/authentication_spec.rb 2>&1 | tail -15`

Expected: at least 12 new failures with "undefined method" errors (or NoMethodError on `pending?`, `token_expired?`, `generate_verification_token!`, `verify!`, `Authentication.verified`, `Authentication.pending`). Existing specs still pass.

- [ ] **Step 2.3: Add the methods + scopes to the model**

In `app/models/authentication.rb`, add inside the class body (preserve existing code):

```ruby
TOKEN_LIFETIME = 24.hours

scope :verified, -> { where.not(verified_at: nil) }
scope :pending,  -> { where(verified_at: nil).where.not(verification_token: nil) }

def verified?
  verified_at.present?
end

def pending?
  verified_at.nil? && verification_token.present?
end

def token_expired?
  verification_sent_at.present? && verification_sent_at < TOKEN_LIFETIME.ago
end

def generate_verification_token!
  update!(
    verification_token: SecureRandom.urlsafe_base64(32),
    verification_sent_at: Time.current,
    verified_at: nil
  )
end

def verify!
  update!(
    verified_at: Time.current,
    verification_token: nil,
    verification_sent_at: nil
  )
end
```

If `scope :email` or any other scope already exists with conflicting name, leave it; the new ones use distinct names.

- [ ] **Step 2.4: Run model specs to verify pass**

Run: `mise exec -- bundle exec rspec spec/models/authentication_spec.rb 2>&1 | tail -5`

Expected: all examples pass.

- [ ] **Step 2.5: Run full suite for regression**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1033+ + 12 new = 1045+ examples, 0 failures.

- [ ] **Step 2.6: Commit**

```bash
git add app/models/authentication.rb spec/models/authentication_spec.rb
git commit -m "feat: add verification predicates and mutators to Authentication"
```

---

## Task 3 — Mailer: `link_verification_email` (TDD)

**Files:**

- Modify: `app/mailers/authentication_mailer.rb`
- Create: `app/views/authentication_mailer/link_verification_email.html.erb`
- Create: `app/views/authentication_mailer/link_verification_email.text.erb`
- Modify: `spec/mailers/authentication_mailer_spec.rb`
- Modify: `config/locales/en/mailers.en.yml`

- [ ] **Step 3.1: Add I18n keys for the email**

Open `config/locales/en/mailers.en.yml`. Inside `en:` → `authentication_mailer:` (create the key if absent), add:

```yaml
    link_verification_email:
      subject: "Confirm your %{provider} sign-in for %{app_name}"
      greeting: "Hi %{first_name},"
      body: "You added %{provider} as a sign-in method for %{app_name}. Confirm that %{email} belongs to you to activate it."
      cta: "Yes, this was me — finish linking"
      what_is_this: "We email you whenever a new sign-in method is added to your account. This protects your account from someone else linking it."
      footer: "If you didn't try to add this, ignore this email — your account stays untouched."
```

- [ ] **Step 3.2: Write failing mailer spec**

In `spec/mailers/authentication_mailer_spec.rb`, append:

```ruby
RSpec.describe AuthenticationMailer, type: :mailer do
  describe "#link_verification_email" do
    let(:user) { create(:user, first_name: "Alice", email_address: "alice@home.com") }
    let(:auth) do
      user.authentications.create!(
        provider: "google_oauth2",
        uid: "12345",
        email: "alice.work@gmail.com",
        verification_token: "abc-token-xyz",
        verification_sent_at: Time.current
      )
    end

    subject(:mail) { described_class.link_verification_email(auth) }

    it "addresses the OAuth-returned email, not the primary email" do
      expect(mail.to).to eq([ "alice.work@gmail.com" ])
    end

    it "names the provider in the subject" do
      expect(mail.subject).to include("Google Oauth2")
    end

    it "names the app in the subject" do
      expect(mail.subject).to include(I18n.t("application.name"))
    end

    it "includes the verification URL with the token in the body" do
      expect(mail.body.encoded).to include("verify/abc-token-xyz")
    end

    it "addresses the user by first name" do
      expect(mail.body.encoded).to include("Alice")
    end

    it "renders both HTML and text parts" do
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
    end
  end
end
```

- [ ] **Step 3.3: Run mailer spec to confirm it fails**

Run: `mise exec -- bundle exec rspec spec/mailers/authentication_mailer_spec.rb 2>&1 | tail -10`

Expected: 6 failures with "undefined method 'link_verification_email'" or template-not-found errors.

- [ ] **Step 3.4: Add the mailer method**

In `app/mailers/authentication_mailer.rb`, add inside the class body:

```ruby
def link_verification_email(authentication)
  @user = authentication.user
  @authentication = authentication
  @verify_url = verify_account_connected_accounts_url(token: authentication.verification_token)
  @app_name = I18n.t("application.name")
  @provider_name = authentication.provider.titleize

  mail(
    to: authentication.email,
    subject: I18n.t("authentication_mailer.link_verification_email.subject",
                    provider: @provider_name, app_name: @app_name)
  )
end
```

Note: the URL helper `verify_account_connected_accounts_url` doesn't exist yet — Task 4 adds the route. The spec will fail until then; that's expected.

- [ ] **Step 3.5: Create the HTML template**

Create `app/views/authentication_mailer/link_verification_email.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title><%= I18n.t("authentication_mailer.link_verification_email.subject", provider: @provider_name, app_name: @app_name) %></title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #1f2937; line-height: 1.5; max-width: 480px; margin: 24px auto; padding: 0 16px; }
      .button { display: inline-block; padding: 12px 24px; background: #1e40af; color: #fff; text-decoration: none; border-radius: 6px; font-weight: 600; }
      .what { color: #6b7280; font-size: 14px; margin-top: 24px; }
      .footer { color: #9ca3af; font-size: 13px; margin-top: 16px; border-top: 1px solid #e5e7eb; padding-top: 12px; }
    </style>
  </head>
  <body>
    <p><%= I18n.t("authentication_mailer.link_verification_email.greeting", first_name: @user.first_name) %></p>
    <p><%= I18n.t("authentication_mailer.link_verification_email.body", provider: @provider_name, app_name: @app_name, email: @authentication.email) %></p>
    <p><a class="button" href="<%= @verify_url %>"><%= I18n.t("authentication_mailer.link_verification_email.cta") %></a></p>
    <p class="what"><%= I18n.t("authentication_mailer.link_verification_email.what_is_this") %></p>
    <p class="footer"><%= I18n.t("authentication_mailer.link_verification_email.footer") %></p>
  </body>
</html>
```

- [ ] **Step 3.6: Create the text template**

Create `app/views/authentication_mailer/link_verification_email.text.erb`:

```erb
<%= I18n.t("authentication_mailer.link_verification_email.greeting", first_name: @user.first_name) %>

<%= I18n.t("authentication_mailer.link_verification_email.body", provider: @provider_name, app_name: @app_name, email: @authentication.email) %>

<%= I18n.t("authentication_mailer.link_verification_email.cta") %>:
<%= @verify_url %>

<%= I18n.t("authentication_mailer.link_verification_email.what_is_this") %>

---
<%= I18n.t("authentication_mailer.link_verification_email.footer") %>
```

- [ ] **Step 3.7: Mailer spec will still fail until Task 4 (routes)**

This is intentional — the mailer references a URL helper that's added in the next task. Don't run the spec yet; commit and move on.

- [ ] **Step 3.8: Commit**

```bash
git add app/mailers/authentication_mailer.rb app/views/authentication_mailer/link_verification_email.html.erb app/views/authentication_mailer/link_verification_email.text.erb spec/mailers/authentication_mailer_spec.rb config/locales/en/mailers.en.yml
git commit -m "feat: add AuthenticationMailer#link_verification_email + templates"
```

---

## Task 4 — Routes + `Account::ConnectedAccountsController#verify` action (TDD)

**Files:**

- Modify: `config/routes.rb`
- Modify: `app/controllers/account/connected_accounts_controller.rb`
- Modify: `spec/requests/account/connected_accounts_spec.rb`
- Modify: `config/locales/en/account.en.yml`

- [ ] **Step 4.1: Add I18n keys for the verify action**

Open `config/locales/en/account.en.yml`. Inside the `connected_accounts:` block, add:

```yaml
      verify:
        success: "%{provider} linked. You can sign in with it."
        success_signed_out: "%{provider} linked. Sign in to continue."
        invalid_or_expired: "This confirmation link is invalid or expired. Sign in and request a new one from your connected accounts."
```

- [ ] **Step 4.2: Add the route**

In `config/routes.rb`, change the existing line `resources :connected_accounts, only: [ :index, :destroy ]` (around line 27) to:

```ruby
    resources :connected_accounts, only: [ :index, :destroy ] do
      collection do
        get "verify/:token", action: :verify, as: :verify
      end
    end
```

- [ ] **Step 4.3: Verify the route helper exists**

Run: `mise exec -- bin/rails routes -g connected_accounts 2>&1 | grep verify`

Expected output: a `verify_account_connected_accounts_path` route showing `GET /account/connected_accounts/verify/:token`.

- [ ] **Step 4.4: Write failing request spec for #verify**

Open `spec/requests/account/connected_accounts_spec.rb` (create if needed with `require "rails_helper"` + a top describe). Add inside `RSpec.describe "Account::ConnectedAccounts", type: :request do`:

```ruby
  describe "GET /account/connected_accounts/verify/:token" do
    let(:user) { create(:user) }
    let(:auth) do
      user.authentications.create!(
        provider: "google_oauth2",
        uid: "uid-1",
        email: "alice.work@gmail.com",
        verification_token: "valid-token",
        verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end

    context "with a valid, unexpired token" do
      it "marks the authentication verified" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(auth.reload.verified_at).to be_present
        expect(auth.verification_token).to be_nil
      end

      context "when the user is signed in" do
        before { sign_in(user) }

        it "redirects to connected accounts with success" do
          get verify_account_connected_accounts_path(token: auth.verification_token)
          expect(response).to redirect_to(account_connected_accounts_path)
          expect(flash[:notice]).to include("linked")
        end
      end

      context "when the user is signed out" do
        it "redirects to sign-in with sign-in success message" do
          get verify_account_connected_accounts_path(token: auth.verification_token)
          expect(response).to redirect_to(new_session_path)
          expect(flash[:notice]).to include("Sign in to continue")
        end
      end
    end

    context "with an expired token" do
      before { auth.update!(verification_sent_at: 25.hours.ago) }

      it "does not mark the authentication verified" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(auth.reload.verified_at).to be_nil
      end

      it "redirects with an invalid-or-expired alert" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with an unknown token" do
      it "redirects with an invalid-or-expired alert" do
        get verify_account_connected_accounts_path(token: "nonexistent")
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with an already-consumed token" do
      before { auth.verify! }

      it "redirects with an invalid-or-expired alert" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(flash[:alert]).to include("invalid or expired")
      end
    end
  end
```

- [ ] **Step 4.5: Run spec to verify it fails**

Run: `mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb 2>&1 | tail -15`

Expected: failures referring to undefined `#verify` action or unknown route path.

- [ ] **Step 4.6: Implement `#verify`**

Open `app/controllers/account/connected_accounts_controller.rb`. Add at the top of the class body:

```ruby
    allow_unauthenticated_access only: :verify
```

Then add the action:

```ruby
    def verify
      auth = Authentication.find_by(verification_token: params[:token])

      if auth.nil? || auth.token_expired?
        redirect_to(authenticated? ? account_connected_accounts_path : new_session_path,
                    alert: t(".invalid_or_expired"))
        return
      end

      auth.verify!

      if authenticated?
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: auth.provider.titleize)
      else
        redirect_to new_session_path,
          notice: t(".success_signed_out", provider: auth.provider.titleize)
      end
    end
```

The `authenticated?` helper comes from the `Authenticatable` concern. `account_connected_accounts_path` requires sign-in, so the redirect of an unauthenticated already-consumed-token user goes to `new_session_path` instead.

- [ ] **Step 4.7: Run spec to verify it passes**

Run: `mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb 2>&1 | tail -5`

Expected: all new examples pass.

- [ ] **Step 4.8: Run mailer spec (now that route exists)**

Run: `mise exec -- bundle exec rspec spec/mailers/authentication_mailer_spec.rb 2>&1 | tail -5`

Expected: all 6 mailer specs from Task 3 now pass.

- [ ] **Step 4.9: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1057+ examples, 0 failures.

- [ ] **Step 4.10: Commit**

```bash
git add config/routes.rb app/controllers/account/connected_accounts_controller.rb spec/requests/account/connected_accounts_spec.rb config/locales/en/account.en.yml
git commit -m "feat: token-based verify action for OAuth account links"
```

---

## Task 5 — `#resend_verification` action with rate limit (TDD)

**Files:**

- Modify: `config/routes.rb`
- Modify: `app/controllers/account/connected_accounts_controller.rb`
- Modify: `spec/requests/account/connected_accounts_spec.rb`
- Modify: `config/locales/en/account.en.yml`

- [ ] **Step 5.1: Add I18n keys**

In `config/locales/en/account.en.yml`, inside `connected_accounts:`, add:

```yaml
      resend_verification:
        resent: "We sent a fresh confirmation link to %{email}."
        not_pending: "That sign-in method is already verified."
        rate_limited: "Please wait a moment before requesting another confirmation email."
```

- [ ] **Step 5.2: Add route member action**

In `config/routes.rb`, extend the `connected_accounts` resource block:

```ruby
    resources :connected_accounts, only: [ :index, :destroy ] do
      member do
        post :resend_verification
      end
      collection do
        get "verify/:token", action: :verify, as: :verify
      end
    end
```

- [ ] **Step 5.3: Write failing request spec**

Append inside the same describe block in `spec/requests/account/connected_accounts_spec.rb`:

```ruby
  describe "POST /account/connected_accounts/:id/resend_verification" do
    let(:user) { create(:user) }
    let(:pending_auth) do
      user.authentications.create!(
        provider: "google_oauth2",
        uid: "uid-2",
        email: "pending@example.com",
        verification_token: "old-token",
        verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end
    let(:verified_auth) do
      user.authentications.create!(
        provider: "github",
        uid: "uid-3",
        email: "verified@example.com",
        verified_at: Time.current
      )
    end

    before { sign_in(user) }

    context "with a pending authentication" do
      it "regenerates the token" do
        old_token = pending_auth.verification_token
        post resend_verification_account_connected_account_path(pending_auth)
        expect(pending_auth.reload.verification_token).not_to eq(old_token)
      end

      it "enqueues a fresh verification email" do
        expect {
          post resend_verification_account_connected_account_path(pending_auth)
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with success" do
        post resend_verification_account_connected_account_path(pending_auth)
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:notice]).to include("pending@example.com")
      end
    end

    context "with an already-verified authentication" do
      it "does not change the auth" do
        original_verified_at = verified_auth.verified_at
        post resend_verification_account_connected_account_path(verified_auth)
        expect(verified_auth.reload.verified_at).to eq(original_verified_at)
      end

      it "redirects with not_pending alert" do
        post resend_verification_account_connected_account_path(verified_auth)
        expect(flash[:alert]).to include("already verified")
      end
    end

    context "rate limit" do
      it "blocks the 4th request within 3 minutes" do
        3.times { post resend_verification_account_connected_account_path(pending_auth) }
        post resend_verification_account_connected_account_path(pending_auth)
        expect(flash[:alert]).to include("wait a moment")
      end
    end
  end
```

- [ ] **Step 5.4: Run spec to verify it fails**

Run: `mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb -e "resend_verification" 2>&1 | tail -10`

Expected: failures around undefined route or action.

- [ ] **Step 5.5: Implement the action with rate limit**

In `app/controllers/account/connected_accounts_controller.rb`, add at the top of the class (after `allow_unauthenticated_access`):

```ruby
    rate_limit to: 3, within: 3.minutes, only: :resend_verification,
      with: -> {
        redirect_to account_connected_accounts_path,
          alert: t("account.connected_accounts.resend_verification.rate_limited")
      }
```

Then add the action:

```ruby
    def resend_verification
      auth = Current.user.authentications.find(params[:id])

      if auth.pending?
        auth.generate_verification_token!
        AuthenticationMailer.link_verification_email(auth).deliver_later
        redirect_to account_connected_accounts_path,
          notice: t(".resent", email: auth.email)
      else
        redirect_to account_connected_accounts_path,
          alert: t(".not_pending")
      end
    end
```

- [ ] **Step 5.6: Run spec to verify pass**

Run: `mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb -e "resend_verification" 2>&1 | tail -5`

Expected: all 6 examples pass.

- [ ] **Step 5.7: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1063+ examples, 0 failures.

- [ ] **Step 5.8: Commit**

```bash
git add config/routes.rb app/controllers/account/connected_accounts_controller.rb spec/requests/account/connected_accounts_spec.rb config/locales/en/account.en.yml
git commit -m "feat: rate-limited resend_verification action for pending auths"
```

---

## Task 6 — Refactor `OmniauthCallbacksController#create` for signed-in linking (TDD)

This is the security-critical task. It introduces the email-match check and pending-state creation.

**Files:**

- Modify: `app/controllers/omniauth_callbacks_controller.rb`
- Modify: `spec/requests/omniauth_callbacks_spec.rb`
- Modify: `config/locales/en/oauth.en.yml`

- [ ] **Step 6.1: Add I18n keys for callback flash messages**

In `config/locales/en/oauth.en.yml`, inside the `omniauth_callbacks.create:` block (create if absent), add:

```yaml
      linked: "%{provider} linked successfully."
      pending: "Almost there — we sent a confirmation link to %{email}. Click it to finish linking your %{provider} account."
      pending_resent: "We sent a fresh confirmation link to %{email}. Click the link to finish signing in."
      collision_other_user: "That %{provider} account is already linked to a different user."
      already_linked: "Your account is already linked to %{provider}."
      linking_failed: "We couldn't link that account. Please try again."
```

- [ ] **Step 6.2: Write failing request specs**

Open `spec/requests/omniauth_callbacks_spec.rb`. Inside the existing `RSpec.describe "OmniauthCallbacks", type: :request do`, add:

```ruby
  describe "signed-in user linking a new provider" do
    let(:user) { create(:user, email_address: "alice@home.com") }
    before do
      sign_in(user)
      OmniAuth.config.test_mode = true
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    context "when OAuth email matches user's primary email" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google_oauth2", uid: "google-1",
          info: { email: "alice@home.com", name: "Alice" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "creates the auth as verified immediately" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google_oauth2")
        expect(auth).to be_verified
        expect(auth.verification_token).to be_nil
      end

      it "redirects to connected accounts with linked notice" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:notice]).to include("linked")
      end
    end

    context "when OAuth email differs from user's primary email" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google_oauth2", uid: "google-1",
          info: { email: "alice.work@gmail.com", name: "Alice" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "creates the auth as pending (verified_at nil)" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google_oauth2")
        expect(auth.verified_at).to be_nil
        expect(auth.verification_token).to be_present
      end

      it "captures the OAuth email on the auth row" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google_oauth2")
        expect(auth.email).to eq("alice.work@gmail.com")
      end

      it "enqueues the verification email" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with pending banner flash" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:notice]).to include("alice.work@gmail.com")
      end
    end

    context "when user already has an authentication for this provider" do
      before do
        user.authentications.create!(provider: "google_oauth2", uid: "old-uid",
          email: "alice@home.com", verified_at: Time.current)
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google_oauth2", uid: "google-different-uid",
          info: { email: "alice@home.com" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
        )
      end

      it "does not create a second authentication" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { user.authentications.count }
      end

      it "redirects with already_linked alert" do
        get "/auth/google_oauth2/callback"
        expect(flash[:alert]).to include("already linked")
      end
    end
  end
```

- [ ] **Step 6.3: Run specs to verify they fail**

Run: `mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb 2>&1 | tail -15`

Expected: failures showing the new spec expectations don't pass yet (auth is created verified instead of pending; no email sent; etc).

- [ ] **Step 6.4: Refactor `OmniauthCallbacksController#create`**

Replace the entire contents of `app/controllers/omniauth_callbacks_controller.rb` with:

```ruby
class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access

  def create
    auth_hash = request.env["omniauth.auth"]
    resume_session
    existing = Authentication.find_by(provider: auth_hash.provider, uid: auth_hash.uid)

    if existing
      handle_existing_auth(existing, auth_hash)
    elsif Current.user
      handle_signed_in_link(Current.user, auth_hash)
    else
      handle_new_user_oauth(auth_hash)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    redirect_to fallback_path,
      alert: t("omniauth_callbacks.create.linking_failed")
  end

  def failure
    redirect_to new_session_path,
      alert: t("sessions.create.oauth_failure")
  end

  private

  def handle_existing_auth(auth, auth_hash)
    if auth.pending?
      auth.generate_verification_token!
      AuthenticationMailer.link_verification_email(auth).deliver_later
      redirect_to new_session_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: auth.email)
    elsif Current.user.present? && Current.user.id != auth.user_id
      redirect_to account_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user",
                 provider: auth_hash.provider.titleize)
    else
      auth.update!(oauth_attrs(auth_hash))
      start_new_session_for(auth.user)
      redirect_to root_path, notice: t("sessions.create.success")
    end
  end

  def handle_signed_in_link(user, auth_hash)
    if user.authentications.exists?(provider: auth_hash.provider)
      redirect_to account_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked",
                 provider: auth_hash.provider.titleize)
      return
    end

    oauth_email = auth_hash.info.email
    email_matches = oauth_email.present? && oauth_email == user.email_address

    auth = user.authentications.build(
      provider: auth_hash.provider,
      uid: auth_hash.uid,
      email: oauth_email,
      **oauth_attrs(auth_hash)
    )

    if email_matches
      auth.verified_at = Time.current
      auth.save!
      redirect_to account_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: auth_hash.provider.titleize)
    else
      auth.save!
      auth.generate_verification_token!
      AuthenticationMailer.link_verification_email(auth).deliver_later
      flash[:confirming_email_for] = auth.id
      redirect_to account_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending",
                  email: oauth_email, provider: auth_hash.provider.titleize)
    end
  end

  def handle_new_user_oauth(auth_hash)
    user = find_verified_user_by_email(auth_hash.info.email) || create_user_from_oauth(auth_hash)
    user.authentications.create!(
      provider: auth_hash.provider,
      uid: auth_hash.uid,
      email: auth_hash.info.email,
      verified_at: Time.current,
      **oauth_attrs(auth_hash)
    )
    start_new_session_for(user)
    redirect_to root_path, notice: t("sessions.create.success")
  end

  def fallback_path
    Current.user.present? ? account_connected_accounts_path : new_session_path
  end

  def oauth_attrs(auth_hash)
    attrs = {
      oauth_token: auth_hash.credentials.token,
      oauth_refresh_token: auth_hash.credentials.refresh_token,
      oauth_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil
    }
    attrs[:avatar_url] = auth_hash.info.image if auth_hash.info.image.present?
    attrs
  end

  def find_verified_user_by_email(email)
    user = User.find_by(email_address: email)
    return nil unless user
    return user if user.authentications.email.where.not(verified_at: nil).exists?
    nil
  end

  def create_user_from_oauth(auth_hash)
    User.create!(
      email_address: auth_hash.info.email,
      first_name: auth_hash.info.first_name.presence || auth_hash.info.name&.split&.first || "User",
      last_name: auth_hash.info.last_name.presence || auth_hash.info.name&.split&.last || "User"
    )
  end
end
```

- [ ] **Step 6.5: Run spec to verify it passes**

Run: `mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb 2>&1 | tail -5`

Expected: all examples pass (existing + new).

- [ ] **Step 6.6: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1071+ examples, 0 failures.

- [ ] **Step 6.7: Commit**

```bash
git add app/controllers/omniauth_callbacks_controller.rb spec/requests/omniauth_callbacks_spec.rb config/locales/en/oauth.en.yml
git commit -m "feat: require email verification when OAuth-linking with mismatched email"
```

---

## Task 7 — Existing-pending re-OAuth + cross-user collision (TDD)

These two paths are already wired in Task 6's controller code (`handle_existing_auth` covers both: pending → resend, cross-user → block). This task adds the request specs that prove they work.

**Files:**

- Modify: `spec/requests/omniauth_callbacks_spec.rb`

- [ ] **Step 7.1: Write request specs**

Append to the same describe block in `spec/requests/omniauth_callbacks_spec.rb`:

```ruby
  describe "re-OAuth on existing pending authentication" do
    let(:user) { create(:user, email_address: "bob@example.com") }
    let!(:pending_auth) do
      user.authentications.create!(
        provider: "google_oauth2", uid: "google-pending",
        email: "bob.work@gmail.com",
        verification_token: "old-token", verification_sent_at: 2.hours.ago,
        verified_at: nil
      )
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2", uid: "google-pending",
        info: { email: "bob.work@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "regenerates the verification token" do
      old_token = pending_auth.verification_token
      get "/auth/google_oauth2/callback"
      expect(pending_auth.reload.verification_token).not_to eq(old_token)
    end

    it "enqueues a fresh verification email" do
      expect {
        get "/auth/google_oauth2/callback"
      }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
    end

    it "refuses to sign in (does NOT create a session)" do
      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to include("fresh confirmation link")
    end
  end

  describe "cross-user collision" do
    let(:alice) { create(:user, email_address: "alice@example.com") }
    let(:eve)   { create(:user, email_address: "eve@example.com") }

    before do
      alice.authentications.create!(provider: "google_oauth2", uid: "shared-uid",
        email: "alice@example.com", verified_at: Time.current)
      sign_in(eve)
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2", uid: "shared-uid",
        info: { email: "alice@example.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "does not transfer Alice's auth to Eve" do
      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change { alice.authentications.find_by(provider: "google_oauth2").user_id }
    end

    it "redirects Eve with collision_other_user alert" do
      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to include("already linked")
    end
  end
```

- [ ] **Step 7.2: Run specs**

Run: `mise exec -- bundle exec rspec spec/requests/omniauth_callbacks_spec.rb 2>&1 | tail -5`

Expected: all examples pass (the controller from Task 6 already handles both cases).

- [ ] **Step 7.3: Commit**

```bash
git add spec/requests/omniauth_callbacks_spec.rb
git commit -m "test: cover existing-pending re-OAuth and cross-user collision flows"
```

---

## Task 8 — Fix `#destroy` last-method counting bug (TDD)

**Files:**

- Modify: `app/controllers/account/connected_accounts_controller.rb`
- Modify: `spec/requests/account/connected_accounts_spec.rb`
- Modify: `config/locales/en/account.en.yml`

- [ ] **Step 8.1: Update I18n keys**

In `config/locales/en/account.en.yml`, find the `connected_accounts.destroy:` block and replace with:

```yaml
      destroy:
        success: "%{provider} unlinked."
        cannot_remove_last_verified: "You can't remove your last verified sign-in method."
```

(The existing key may be named `last_method` or `success`; replace whichever exists with the above.)

- [ ] **Step 8.2: Write failing specs**

Append to `spec/requests/account/connected_accounts_spec.rb`:

```ruby
  describe "DELETE /account/connected_accounts/:id (last verified method protection)" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    context "user has only one verified auth and one pending auth" do
      let!(:verified) { user.authentications.create!(provider: "email", uid: user.email_address,
        email: user.email_address, verified_at: Time.current) }
      let!(:pending) { user.authentications.create!(provider: "google_oauth2", uid: "g-1",
        email: "alice.work@gmail.com",
        verification_token: "tok", verification_sent_at: 1.hour.ago, verified_at: nil) }

      it "blocks removal of the verified auth" do
        delete account_connected_account_path(verified)
        expect(verified.reload).to be_persisted
        expect(flash[:alert]).to include("last verified")
      end

      it "allows cancellation of the pending auth" do
        delete account_connected_account_path(pending)
        expect(Authentication.exists?(pending.id)).to be false
      end
    end

    context "user has two verified auths" do
      let!(:auth1) { user.authentications.create!(provider: "email", uid: user.email_address,
        email: user.email_address, verified_at: Time.current) }
      let!(:auth2) { user.authentications.create!(provider: "google_oauth2", uid: "g-1",
        email: user.email_address, verified_at: Time.current) }

      it "allows removal of one" do
        delete account_connected_account_path(auth1)
        expect(Authentication.exists?(auth1.id)).to be false
      end
    end
  end
```

- [ ] **Step 8.3: Run specs to verify they fail**

Run: `mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb -e "last verified method" 2>&1 | tail -10`

Expected: at least one failure (the "allows cancellation of pending" test fails because current code counts all auths, blocks pending-cancel when only 1 verified + 1 pending exists).

- [ ] **Step 8.4: Fix `#destroy`**

In `app/controllers/account/connected_accounts_controller.rb`, replace the existing `destroy` method:

```ruby
    def destroy
      auth = Current.user.authentications.find(params[:id])

      if auth.verified? && Current.user.authentications.verified.count <= 1
        redirect_to account_connected_accounts_path,
          alert: t(".cannot_remove_last_verified")
      else
        auth.destroy!
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: auth.provider.titleize)
      end
    end
```

- [ ] **Step 8.5: Run specs to verify pass**

Run: `mise exec -- bundle exec rspec spec/requests/account/connected_accounts_spec.rb -e "last verified method" 2>&1 | tail -5`

Expected: all examples pass.

- [ ] **Step 8.6: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1077+ examples, 0 failures.

- [ ] **Step 8.7: Commit**

```bash
git add app/controllers/account/connected_accounts_controller.rb spec/requests/account/connected_accounts_spec.rb config/locales/en/account.en.yml
git commit -m "fix: count only verified auths in last-method protection"
```

---

## Task 9 — Views: pending row + post-OAuth banner

**Files:**

- Modify: `app/views/account/connected_accounts/index.html.erb`
- Modify: `config/locales/en/account.en.yml`

- [ ] **Step 9.1: Add I18n keys for the view**

In `config/locales/en/account.en.yml`, inside `connected_accounts.index:`, add:

```yaml
        pending_label: "Confirming %{email}"
        pending_help: "Check your email for a confirmation link."
        resend_action: "Resend confirmation"
        cancel_action: "Cancel link"
        confirming_banner_html: "Almost there — we sent a confirmation link to <strong>%{email}</strong> to make sure that's really you. Click the link to finish linking %{provider}."
```

- [ ] **Step 9.2: Read current index template**

Run: `cat app/views/account/connected_accounts/index.html.erb`

Note the current structure. The plan modifies it; if it diverges significantly from typical "loop over @authentications, render row" structure, ASK before editing.

- [ ] **Step 9.3: Modify the index template**

In `app/views/account/connected_accounts/index.html.erb`, before the list of authentications add the post-OAuth banner. Around the loop, conditionally render rows differently for pending vs verified:

```erb
<% if (auth_id = flash[:confirming_email_for]) && (pending = @authentications.find { |a| a.id == auth_id }) %>
  <%= render "shared/toast_card",
        type: :info,
        message: t("account.connected_accounts.index.confirming_banner_html",
                   email: pending.email,
                   provider: pending.provider.titleize).html_safe %>
<% end %>

<ul class="space-y-3">
  <% @authentications.each do |authentication| %>
    <li class="flex items-center gap-4 p-4 rounded-lg border <%= authentication.pending? ? "bg-info-surface border-info-border" : "bg-surface border-border" %>">
      <%= icon(:envelope, class: "w-6 h-6 #{authentication.pending? ? "text-info" : "text-text-muted"}") %>

      <div class="flex-1">
        <div class="text-sm font-semibold text-text-heading">
          <%= authentication.provider.titleize %>
        </div>
        <% if authentication.pending? %>
          <div class="text-xs text-info">
            <%= t(".pending_label", email: authentication.email) %>
          </div>
          <div class="text-xs text-text-muted mt-1">
            <%= t(".pending_help") %>
          </div>
        <% else %>
          <div class="text-xs text-text-muted">
            <%= authentication.email %>
          </div>
        <% end %>
      </div>

      <div class="flex items-center gap-3 text-sm">
        <% if authentication.pending? %>
          <%= button_to t(".resend_action"),
                resend_verification_account_connected_account_path(authentication),
                method: :post,
                class: "text-interactive hover:text-interactive-hover underline focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded",
                form: { class: "inline" } %>
          <%= button_to t(".cancel_action"),
                account_connected_account_path(authentication),
                method: :delete,
                class: "text-text-muted hover:text-danger underline focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded",
                form: { class: "inline" } %>
        <% else %>
          <%= button_to t("account.connected_accounts.destroy.action", default: "Unlink"),
                account_connected_account_path(authentication),
                method: :delete,
                data: { turbo_confirm: t("account.connected_accounts.destroy.confirm", default: "Remove this sign-in method?") },
                class: "text-text-muted hover:text-danger underline focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
        <% end %>
      </div>
    </li>
  <% end %>
</ul>
```

The exact existing structure may differ; preserve any wrapping markup, page headings, navigation, etc., that's already there. The KEY changes are:
1. Top of page (or just above the auth list): the conditional banner.
2. Per-row: conditional pending vs verified treatment.
3. Per-row: pending shows Resend + Cancel; verified shows Unlink.

If the existing template uses a partial for the row (e.g., `_authentication_row.html.erb`), make the modifications to that partial instead.

- [ ] **Step 9.4: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1077+ examples, 0 failures. (Existing tests don't depend on view structure beyond presence of unlink buttons; verify nothing broke.)

- [ ] **Step 9.5: Commit**

```bash
git add app/views/account/connected_accounts/index.html.erb config/locales/en/account.en.yml
git commit -m "feat: pending state UI for connected accounts (banner + row treatment)"
```

---

## Task 10 — System spec: full happy-path flow

**Files:**

- Create: `spec/system/oauth_link_verification_spec.rb`

- [ ] **Step 10.1: Write the system spec**

Create `spec/system/oauth_link_verification_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Verified OAuth account linking", type: :system do
  let(:user) { create(:user, email_address: "alice@home.com", first_name: "Alice") }

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-system-1",
      info: { email: "alice.work@gmail.com", name: "Alice", first_name: "Alice", last_name: "Smith" },
      credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
    )
  end
  after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

  it "links Google with mismatched email via email verification" do
    sign_in(user)
    visit account_connected_accounts_path

    # Trigger Google OAuth link
    page.driver.with_playwright_page do |pw_page|
      pw_page.goto("#{Capybara.app_host}/auth/google_oauth2/callback")
    end

    # Land on connected accounts; pending row visible
    expect(page).to have_text("alice.work@gmail.com")
    expect(page).to have_text(I18n.t("account.connected_accounts.index.pending_label",
                                     email: "alice.work@gmail.com"))

    # Email was sent to letter_opener inbox
    delivered = ActionMailer::Base.deliveries.last
    expect(delivered.to).to eq([ "alice.work@gmail.com" ])

    # Extract token + click verification link
    auth = user.authentications.find_by(provider: "google_oauth2")
    visit verify_account_connected_accounts_path(token: auth.verification_token)

    # Verified, redirected to connected accounts
    expect(page).to have_current_path(account_connected_accounts_path)
    expect(page).to have_text("Google Oauth2")
    expect(auth.reload).to be_verified
    expect(page).not_to have_text(I18n.t("account.connected_accounts.index.pending_label",
                                         email: "alice.work@gmail.com"))
  end
end
```

Note: the `page.driver.with_playwright_page` approach is consistent with how other system specs in this project execute browser-level navigation. If `Capybara.app_host` isn't configured in the test environment, use the standard `visit` URL.

If the existing spec suite uses different conventions for OmniAuth + system specs, adapt to match those patterns. The intent is: sign in, trigger callback, see pending state, click verify, see verified state.

- [ ] **Step 10.2: Run the system spec**

Run: `mise exec -- bundle exec rspec spec/system/oauth_link_verification_spec.rb 2>&1 | tail -15`

Expected: the spec passes. If it fails because of a Playwright-vs-direct-navigation issue (the OAuth callback route is server-side), you may need to use `visit "/auth/google_oauth2/callback"` directly instead of going through the Playwright page; both work.

- [ ] **Step 10.3: Run full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -3`

Expected: 1078+ examples, 0 failures.

- [ ] **Step 10.4: Commit**

```bash
git add spec/system/oauth_link_verification_spec.rb
git commit -m "test: system spec for OAuth linking + verification happy path"
```

---

## Task 11 — Verify token filtering, final suite, commit design artifacts

**Files:**

- Verify: `config/initializers/filter_parameter_logging.rb`
- Commit: design docs

- [ ] **Step 11.1: Verify token is in filtered params**

Run: `grep -n "token" config/initializers/filter_parameter_logging.rb`

Expected: at least one entry like `:token` or a regex matching token-like params. If `:token` is NOT present, add it:

```ruby
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn
]
```

(Append `:token` if not present.)

- [ ] **Step 11.2: Run full suite one final time**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: 1078+ examples, 0 failures. Coverage steady or up.

- [ ] **Step 11.3: Verify branch state is clean**

Run: `git status --short`

Expected:

```text
?? docs/superpowers/plans/2026-04-25-verified-oauth-account-linking.md
?? docs/superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md
```

If `config/initializers/filter_parameter_logging.rb` was modified in 11.1, it'll show too — commit it with the design docs.

- [ ] **Step 11.4: Commit design artifacts**

```bash
git add docs/superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md \
        docs/superpowers/plans/2026-04-25-verified-oauth-account-linking.md
# include filter_parameter_logging.rb if modified
git status --short | grep filter_parameter_logging && git add config/initializers/filter_parameter_logging.rb
git commit -m "docs: verified OAuth account linking spec and implementation plan"
```

- [ ] **Step 11.5: Review branch commit history**

Run: `git log --oneline $(git merge-base HEAD main)..HEAD`

Expected (newest last):

```text
feat: add email column to authentications for verification linking
feat: add verification predicates and mutators to Authentication
feat: add AuthenticationMailer#link_verification_email + templates
feat: token-based verify action for OAuth account links
feat: rate-limited resend_verification action for pending auths
feat: require email verification when OAuth-linking with mismatched email
test: cover existing-pending re-OAuth and cross-user collision flows
fix: count only verified auths in last-method protection
feat: pending state UI for connected accounts (banner + row treatment)
test: system spec for OAuth linking + verification happy path
docs: verified OAuth account linking spec and implementation plan
```

Eleven commits, each a clean independent unit, all bisect-safe.

---

## Deferred (post-merge, with triggers)

| Item | Trigger |
| ---- | ------- |
| Collision notification email (Scope C from spec) | After this lands and stabilizes; tracked in [project_oauth_linking_followups](~/.claude/projects/.../memory/project_oauth_linking_followups.md) |
| Per-recipient verification-email rate limit | If abuse observed, or as part of broader transactional email rate-limit pass |
| New-user OAuth signup verification reconsideration | Separate threat-model question; if/when fresh-user OAuth verification policy needs revision |

## Open Questions

None. All scope and behavior decided during brainstorming with three-perspective security panel input.
