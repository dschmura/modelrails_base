# Secure Email Change with Re-verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require password confirmation and email re-verification when users change their email address, preventing account hijacking via stolen sessions.

**Architecture:** Three nullable columns on User (`pending_email`, `pending_email_token`, `pending_email_sent_at`) store the pending change. `initiate_email_change!` verifies the password and sets the pending state. `confirm_email_change!` validates the token and atomically updates `email_address` + the email `Authentication.uid`. Two new mailer methods send verification to the new address and notification to the old address. A new `Account::EmailConfirmationsController` handles token verification and cancellation.

**Tech Stack:** Rails 8.1, RSpec, TailwindFormBuilder, ActionMailer

**Spec:** `docs/superpowers/specs/2026-04-02-secure-email-change-design.md`

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `db/migrate/*_add_pending_email_to_users.rb` | Create | Add pending_email columns |
| `app/models/user.rb` | Modify | Pending email methods and validations |
| `app/controllers/account/profiles_controller.rb` | Modify | Split update for email vs non-email |
| `app/controllers/account/email_confirmations_controller.rb` | Create | Token verification and cancellation |
| `config/routes.rb` | Modify | Add email_confirmation resource |
| `app/mailers/authentication_mailer.rb` | Modify | Add email change mailer methods |
| `app/views/authentication_mailer/email_change_verification.html.erb` | Create | Verification email HTML |
| `app/views/authentication_mailer/email_change_verification.text.erb` | Create | Verification email text |
| `app/views/authentication_mailer/email_change_notification.html.erb` | Create | Notification email HTML |
| `app/views/authentication_mailer/email_change_notification.text.erb` | Create | Notification email text |
| `app/views/account/profiles/edit.html.erb` | Modify | Add password field, pending notice |
| `config/locales/en/account.en.yml` | Modify | Add I18n keys |
| `config/locales/en/authentication_mailer.en.yml` | Modify | Add mailer I18n keys |
| `spec/models/user_spec.rb` | Modify | Pending email method specs |
| `spec/requests/account/profiles_spec.rb` | Modify | Email change request specs |
| `spec/requests/account/email_confirmations_spec.rb` | Create | Token confirmation specs |
| `spec/system/email_change_spec.rb` | Create | End-to-end system specs |

---

### Task 1: Add Migration for Pending Email Columns

**Files:**

- Create: `db/migrate/*_add_pending_email_to_users.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddPendingEmailToUsers pending_email:string pending_email_token:string pending_email_sent_at:datetime
```

- [ ] **Step 2: Add unique index to the migration**

Edit the generated migration to add a unique index on `pending_email_token`:

```ruby
class AddPendingEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_email, :string
    add_column :users, :pending_email_token, :string
    add_column :users, :pending_email_sent_at, :datetime
    add_index :users, :pending_email_token, unique: true
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 4: Commit**

```bash
git add db/
git commit -m "feat: add pending_email columns to users table

Stores pending email change state: new address, verification token,
and sent timestamp. Unique index on token for lookup."
```

---

### Task 2: Add User Model Pending Email Methods (TDD)

**Files:**

- Modify: `spec/models/user_spec.rb`
- Modify: `app/models/user.rb`

- [ ] **Step 1: Write the failing specs**

Add to `spec/models/user_spec.rb` after the existing describe blocks:

```ruby
describe "#initiate_email_change!" do
  let(:user) { create(:user) }

  it "sets pending fields when password is correct" do
    result = user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    expect(result).to be true
    expect(user.reload.pending_email).to eq("new@example.com")
    expect(user.pending_email_token).to be_present
    expect(user.pending_email_sent_at).to be_present
  end

  it "returns false when password is wrong" do
    result = user.initiate_email_change!("new@example.com", "wrongpassword")
    expect(result).to be false
    expect(user.reload.pending_email).to be_nil
  end

  it "returns false when email format is invalid" do
    result = user.initiate_email_change!("notanemail", "SecureP@ssw0rd123!")
    expect(result).to be false
    expect(user.reload.pending_email).to be_nil
  end

  it "returns false when email is already taken" do
    create(:user, email_address: "taken@example.com")
    result = user.initiate_email_change!("taken@example.com", "SecureP@ssw0rd123!")
    expect(result).to be false
    expect(user.reload.pending_email).to be_nil
  end

  it "returns false when email is same as current" do
    result = user.initiate_email_change!(user.email_address, "SecureP@ssw0rd123!")
    expect(result).to be false
  end

  it "overwrites previous pending change" do
    user.initiate_email_change!("first@example.com", "SecureP@ssw0rd123!")
    user.initiate_email_change!("second@example.com", "SecureP@ssw0rd123!")
    expect(user.reload.pending_email).to eq("second@example.com")
  end

  it "returns false for passwordless user" do
    oauth_user = create(:user, password: nil, password_digest: nil)
    result = oauth_user.initiate_email_change!("new@example.com", "anything")
    expect(result).to be false
  end

  it "normalizes the pending email" do
    user.initiate_email_change!("  NEW@EXAMPLE.COM  ", "SecureP@ssw0rd123!")
    expect(user.reload.pending_email).to eq("new@example.com")
  end
end

describe "#confirm_email_change!" do
  let(:user) { create(:user) }

  before do
    user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    user.reload
  end

  it "updates email_address with valid token" do
    token = user.pending_email_token
    result = user.confirm_email_change!(token)
    expect(result).to be true
    expect(user.reload.email_address).to eq("new@example.com")
  end

  it "updates email Authentication uid" do
    email_auth = user.authentications.email.first
    token = user.pending_email_token
    user.confirm_email_change!(token)
    expect(email_auth.reload.uid).to eq("new@example.com")
  end

  it "does not touch OAuth authentications" do
    oauth_auth = user.authentications.create!(provider: "google", uid: "google123", verified_at: Time.current)
    token = user.pending_email_token
    user.confirm_email_change!(token)
    expect(oauth_auth.reload.uid).to eq("google123")
  end

  it "clears pending fields" do
    token = user.pending_email_token
    user.confirm_email_change!(token)
    user.reload
    expect(user.pending_email).to be_nil
    expect(user.pending_email_token).to be_nil
    expect(user.pending_email_sent_at).to be_nil
  end

  it "returns false for expired token" do
    user.update!(pending_email_sent_at: 25.hours.ago)
    result = user.confirm_email_change!(user.pending_email_token)
    expect(result).to be false
    expect(user.reload.email_address).not_to eq("new@example.com")
  end

  it "returns false for wrong token" do
    result = user.confirm_email_change!("wrong-token")
    expect(result).to be false
  end

  it "returns false for nil token" do
    result = user.confirm_email_change!(nil)
    expect(result).to be false
  end
end

describe "#cancel_email_change!" do
  let(:user) { create(:user) }

  it "clears all pending fields" do
    user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    user.cancel_email_change!
    user.reload
    expect(user.pending_email).to be_nil
    expect(user.pending_email_token).to be_nil
    expect(user.pending_email_sent_at).to be_nil
  end
end

describe "#pending_email_token_valid?" do
  let(:user) { create(:user) }

  it "returns true for fresh token" do
    user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    expect(user.pending_email_token_valid?).to be true
  end

  it "returns false for expired token" do
    user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    user.update!(pending_email_sent_at: 25.hours.ago)
    expect(user.pending_email_token_valid?).to be false
  end

  it "returns false when no token" do
    expect(user.pending_email_token_valid?).to be false
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/models/user_spec.rb -e "initiate_email_change\|confirm_email_change\|cancel_email_change\|pending_email_token_valid"`
Expected: FAIL — undefined methods

- [ ] **Step 3: Add the methods to User model**

Add to `app/models/user.rb` after the `normalizes :email_address` line:

```ruby
normalizes :pending_email, with: ->(e) { e&.strip&.downcase }

validates :pending_email, format: { with: EMAIL_FORMAT }, allow_blank: true
validate :pending_email_not_taken, if: -> { pending_email.present? }
```

Add these public methods after `has_password?`:

```ruby
def initiate_email_change!(new_email, password)
  return false unless has_password?
  return false unless authenticate(password)

  normalized = new_email.strip.downcase
  return false if normalized == email_address

  self.pending_email = new_email
  self.pending_email_token = SecureRandom.urlsafe_base64(32)
  self.pending_email_sent_at = Time.current

  save
end

def confirm_email_change!(token)
  return false if token.blank?
  return false if pending_email_token != token
  return false unless pending_email_token_valid?

  transaction do
    self.email_address = pending_email
    clear_pending_email_fields
    save!

    authentications.email.update_all(uid: email_address)
  end

  true
rescue ActiveRecord::RecordInvalid
  false
end

def cancel_email_change!
  clear_pending_email_fields
  save!
end

def pending_email_token_valid?
  pending_email_token.present? &&
    pending_email_sent_at.present? &&
    pending_email_sent_at > 24.hours.ago
end
```

Add to the private section:

```ruby
def pending_email_not_taken
  if User.where.not(id: id).exists?(email_address: pending_email)
    errors.add(:pending_email, :taken)
  end
end

def clear_pending_email_fields
  self.pending_email = nil
  self.pending_email_token = nil
  self.pending_email_sent_at = nil
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/models/user_spec.rb -e "initiate_email_change\|confirm_email_change\|cancel_email_change\|pending_email_token_valid"`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "feat: add pending email change methods to User model

initiate_email_change! verifies password, sets pending state.
confirm_email_change! validates token, updates email + auth uid.
cancel_email_change! clears pending state. Validates pending email
format and uniqueness. Passwordless users blocked."
```

---

### Task 3: Add I18n Keys and Mailer Methods (TDD)

**Files:**

- Modify: `config/locales/en/account.en.yml`
- Modify: `config/locales/en/authentication_mailer.en.yml` (or wherever mailer keys live)
- Modify: `app/mailers/authentication_mailer.rb`
- Create: `app/views/authentication_mailer/email_change_verification.html.erb`
- Create: `app/views/authentication_mailer/email_change_verification.text.erb`
- Create: `app/views/authentication_mailer/email_change_notification.html.erb`
- Create: `app/views/authentication_mailer/email_change_notification.text.erb`

- [ ] **Step 1: Add I18n keys to account locale**

Add to `config/locales/en/account.en.yml` under `account:profiles:`:

```yaml
      update:
        success: "Profile updated."
        verification_sent: "Verification email sent to %{email}. Check your inbox."
        wrong_password: "Current password is incorrect."
        email_unchanged: "That's already your email address."
        password_required: "Current password is required to change your email."
      edit:
        title: "Edit profile"
        first_name_label: "First name"
        last_name_label: "Last name"
        email_label: "Email address"
        current_password_label: "Current password"
        current_password_help: "Required when changing your email address"
        pending_email_notice: "Verification email sent to %{email}. Check your inbox."
        cancel_email_change: "Cancel email change"
        email_readonly_notice: "Set a password to change your email address."
        set_password: "Set password"
        submit: "Save changes"
```

Also add for email confirmations:

```yaml
    email_confirmations:
      show:
        success: "Email address updated successfully."
        invalid_or_expired: "This verification link is invalid or has expired."
      destroy:
        cancelled: "Email change cancelled."
```

- [ ] **Step 2: Find and add mailer I18n keys**

Find the authentication mailer locale file:

```bash
find config/locales -name "*.yml" | xargs grep -l "authentication_mailer"
```

Add to that file under `authentication_mailer:`:

```yaml
    email_change_verification:
      subject: "Verify your new email address"
      greeting: "Hi %{name},"
      body: "You requested to change your email address. Click the link below to verify your new address."
      action: "Verify new email"
      expiry_note: "This link will expire in 24 hours."
    email_change_notification:
      subject: "Email change requested on your account"
      greeting: "Hi %{name},"
      body: "Someone requested to change the email address on your account to %{new_email}."
      warning: "If this wasn't you, please change your password immediately."
```

- [ ] **Step 3: Add mailer methods**

Add to `app/mailers/authentication_mailer.rb`:

```ruby
def email_change_verification(user)
  @user = user
  @verification_url = account_email_confirmation_url(token: user.pending_email_token)

  mail(
    to: user.pending_email,
    subject: t("authentication_mailer.email_change_verification.subject")
  )
end

def email_change_notification(user)
  @user = user
  @new_email = user.pending_email

  mail(
    to: user.email_address,
    subject: t("authentication_mailer.email_change_notification.subject")
  )
end
```

- [ ] **Step 4: Create verification email templates**

Create `app/views/authentication_mailer/email_change_verification.html.erb`:

```erb
<h1><%= t("authentication_mailer.email_change_verification.greeting", name: @user.first_name) %></h1>

<p><%= t("authentication_mailer.email_change_verification.body") %></p>

<p>
  <%= link_to t("authentication_mailer.email_change_verification.action"), @verification_url %>
</p>

<p><%= t("authentication_mailer.email_change_verification.expiry_note") %></p>
```

Create `app/views/authentication_mailer/email_change_verification.text.erb`:

```erb
<%= t("authentication_mailer.email_change_verification.greeting", name: @user.first_name) %>

<%= t("authentication_mailer.email_change_verification.body") %>

<%= t("authentication_mailer.email_change_verification.action") %>: <%= @verification_url %>

<%= t("authentication_mailer.email_change_verification.expiry_note") %>
```

- [ ] **Step 5: Create notification email templates**

Create `app/views/authentication_mailer/email_change_notification.html.erb`:

```erb
<h1><%= t("authentication_mailer.email_change_notification.greeting", name: @user.first_name) %></h1>

<p><%= t("authentication_mailer.email_change_notification.body", new_email: @new_email) %></p>

<p><strong><%= t("authentication_mailer.email_change_notification.warning") %></strong></p>
```

Create `app/views/authentication_mailer/email_change_notification.text.erb`:

```erb
<%= t("authentication_mailer.email_change_notification.greeting", name: @user.first_name) %>

<%= t("authentication_mailer.email_change_notification.body", new_email: @new_email) %>

<%= t("authentication_mailer.email_change_notification.warning") %>
```

- [ ] **Step 6: Commit**

```bash
git add config/locales/ app/mailers/ app/views/authentication_mailer/
git commit -m "feat: add email change verification and notification mailers

Verification email sent to new address with 24-hour token link.
Notification email sent to current address warning about the change."
```

---

### Task 4: Add Route and EmailConfirmationsController (TDD)

**Files:**

- Modify: `config/routes.rb`
- Create: `app/controllers/account/email_confirmations_controller.rb`
- Create: `spec/requests/account/email_confirmations_spec.rb`

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `namespace :account do` block, add after `resource :avatar`:

```ruby
resource :email_confirmation, only: [:show, :destroy]
```

- [ ] **Step 2: Write the failing request specs**

Create `spec/requests/account/email_confirmations_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Account Email Confirmations", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /account/email_confirmation" do
    context "with valid token" do
      before do
        user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
        user.reload
      end

      it "updates the email address" do
        get account_email_confirmation_path(token: user.pending_email_token)
        expect(user.reload.email_address).to eq("new@example.com")
      end

      it "redirects with success notice" do
        get account_email_confirmation_path(token: user.pending_email_token)
        expect(response).to redirect_to(edit_account_profile_path)
        follow_redirect!
        expect(response.body).to include(I18n.t("account.email_confirmations.show.success"))
      end

      it "clears pending email" do
        get account_email_confirmation_path(token: user.pending_email_token)
        user.reload
        expect(user.pending_email).to be_nil
        expect(user.pending_email_token).to be_nil
      end
    end

    context "with expired token" do
      before do
        user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
        user.update!(pending_email_sent_at: 25.hours.ago)
        user.reload
      end

      it "rejects and redirects with alert" do
        get account_email_confirmation_path(token: user.pending_email_token)
        expect(response).to redirect_to(edit_account_profile_path)
        expect(user.reload.email_address).not_to eq("new@example.com")
      end
    end

    context "with invalid token" do
      it "rejects and redirects with alert" do
        get account_email_confirmation_path(token: "invalid-token")
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    context "with no token" do
      it "rejects and redirects" do
        get account_email_confirmation_path
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end

  describe "DELETE /account/email_confirmation" do
    before do
      user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    end

    it "clears pending email" do
      delete account_email_confirmation_path
      expect(user.reload.pending_email).to be_nil
    end

    it "redirects with notice" do
      delete account_email_confirmation_path
      expect(response).to redirect_to(edit_account_profile_path)
    end
  end
end
```

- [ ] **Step 3: Run specs to verify they fail**

Run: `bundle exec rspec spec/requests/account/email_confirmations_spec.rb`
Expected: FAIL — controller doesn't exist

- [ ] **Step 4: Create the controller**

Create `app/controllers/account/email_confirmations_controller.rb`:

```ruby
module Account
  class EmailConfirmationsController < ApplicationController
    def show
      if Current.user.confirm_email_change!(params[:token])
        redirect_to edit_account_profile_path, notice: t(".success")
      else
        redirect_to edit_account_profile_path, alert: t(".invalid_or_expired")
      end
    end

    def destroy
      Current.user.cancel_email_change!
      redirect_to edit_account_profile_path, notice: t(".cancelled")
    end
  end
end
```

- [ ] **Step 5: Run specs to verify they pass**

Run: `bundle exec rspec spec/requests/account/email_confirmations_spec.rb`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/account/email_confirmations_controller.rb spec/requests/account/email_confirmations_spec.rb
git commit -m "feat: add EmailConfirmationsController for email change verification

GET with valid token confirms the change. GET with invalid/expired
token rejects. DELETE cancels the pending change."
```

---

### Task 5: Update ProfilesController for Secure Email Change (TDD)

**Files:**

- Modify: `spec/requests/account/profiles_spec.rb`
- Modify: `app/controllers/account/profiles_controller.rb`

- [ ] **Step 1: Rewrite the profile request specs**

Replace the full contents of `spec/requests/account/profiles_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Account Profiles", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/profile/edit to sign in" do
      get edit_account_profile_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "GET /account/profile/edit" do
      it "renders the edit form" do
        get edit_account_profile_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /account/profile" do
      context "name change only (no email change)" do
        it "updates the name without requiring password" do
          patch account_profile_path, params: {
            user: { first_name: "Updated", last_name: "Name" }
          }
          expect(user.reload.first_name).to eq("Updated")
          expect(response).to redirect_to(edit_account_profile_path)
        end
      end

      context "email change with correct password" do
        it "sets pending email and sends verification" do
          expect {
            patch account_profile_path, params: {
              user: { email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
            }
          }.to have_enqueued_mail(AuthenticationMailer, :email_change_verification)

          expect(user.reload.pending_email).to eq("new@example.com")
          expect(user.email_address).not_to eq("new@example.com")
        end

        it "sends notification to old email" do
          expect {
            patch account_profile_path, params: {
              user: { email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
            }
          }.to have_enqueued_mail(AuthenticationMailer, :email_change_notification)
        end

        it "redirects with verification notice" do
          patch account_profile_path, params: {
            user: { email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
          }
          expect(response).to redirect_to(edit_account_profile_path)
        end

        it "also updates name if included" do
          patch account_profile_path, params: {
            user: { first_name: "New", email_address: "new@example.com", current_password: "SecureP@ssw0rd123!" }
          }
          expect(user.reload.first_name).to eq("New")
          expect(user.pending_email).to eq("new@example.com")
        end
      end

      context "email change with wrong password" do
        it "rejects and re-renders form" do
          patch account_profile_path, params: {
            user: { email_address: "new@example.com", current_password: "wrongpassword" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(user.reload.pending_email).to be_nil
        end
      end

      context "email change with missing password" do
        it "rejects and re-renders form" do
          patch account_profile_path, params: {
            user: { email_address: "new@example.com" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "email change with same email" do
        it "ignores email change, updates other fields" do
          patch account_profile_path, params: {
            user: { first_name: "Updated", email_address: user.email_address }
          }
          expect(user.reload.first_name).to eq("Updated")
          expect(user.pending_email).to be_nil
          expect(response).to redirect_to(edit_account_profile_path)
        end
      end

      context "passwordless user" do
        let(:user) { create(:user, password: nil, password_digest: nil) }

        it "updates name without email change" do
          patch account_profile_path, params: {
            user: { first_name: "Updated" }
          }
          expect(user.reload.first_name).to eq("Updated")
        end
      end

      context "invalid params" do
        it "returns unprocessable entity for blank first_name" do
          patch account_profile_path, params: { user: { first_name: "" } }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run specs to verify failures**

Run: `bundle exec rspec spec/requests/account/profiles_spec.rb`
Expected: Several failures — controller doesn't handle email change logic yet

- [ ] **Step 3: Update the ProfilesController**

Replace the full contents of `app/controllers/account/profiles_controller.rb`:

```ruby
module Account
  class ProfilesController < ApplicationController
    def edit
      @user = Current.user
    end

    def update
      @user = Current.user

      if email_change_requested?
        handle_email_change
      else
        handle_profile_update
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email_address, :current_password)
    end

    def email_change_requested?
      new_email = profile_params[:email_address]
      new_email.present? && new_email.strip.downcase != @user.email_address
    end

    def handle_email_change
      current_password = profile_params[:current_password]
      new_email = profile_params[:email_address]

      if current_password.blank?
        @user.errors.add(:current_password, t(".password_required"))
        render :edit, status: :unprocessable_entity
        return
      end

      # Update name fields if included
      @user.assign_attributes(profile_params.except(:email_address, :current_password))

      if @user.initiate_email_change!(new_email, current_password)
        @user.save! if @user.changed?
        AuthenticationMailer.email_change_verification(@user).deliver_later
        AuthenticationMailer.email_change_notification(@user).deliver_later
        redirect_to edit_account_profile_path, notice: t(".verification_sent", email: @user.pending_email)
      else
        @user.errors.add(:current_password, t(".wrong_password")) unless @user.errors.any?
        render :edit, status: :unprocessable_entity
      end
    end

    def handle_profile_update
      if @user.update(profile_params.except(:email_address, :current_password).merge(
        email_address: @user.email_address
      ))
        redirect_to edit_account_profile_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/requests/account/profiles_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/controllers/account/profiles_controller.rb spec/requests/account/profiles_spec.rb
git commit -m "feat: secure email change with password confirmation in ProfilesController

Email changes require current_password, set pending_email, and send
verification + notification emails. Name changes work without password.
Passwordless users can update name but not email."
```

---

### Task 6: Update Profile Edit Form

**Files:**

- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Rewrite the profile form**

Replace the full contents of `app/views/account/profiles/edit.html.erb`:

```erb
<% content_for(:title) { t("account.profiles.edit.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("account.profiles.edit.title") %>
  </h1>

  <%= form_with model: @user, url: account_profile_path, method: :patch, class: "mt-8 space-y-6" do |form| %>
    <%= form.error_summary %>

    <%= form.text_field :first_name,
          label: t("account.profiles.edit.first_name_label"),
          required: true,
          autocomplete: "given-name" %>

    <%= form.text_field :last_name,
          label: t("account.profiles.edit.last_name_label"),
          required: true,
          autocomplete: "family-name" %>

    <% if @user.has_password? %>
      <%= form.email_field :email_address,
            label: t("account.profiles.edit.email_label"),
            required: true,
            autocomplete: "email" %>

      <%= form.password_field :current_password,
            label: t("account.profiles.edit.current_password_label"),
            help: t("account.profiles.edit.current_password_help"),
            autocomplete: "current-password" %>
    <% else %>
      <div class="space-y-2">
        <p class="block text-sm font-medium text-text-body"><%= t("account.profiles.edit.email_label") %></p>
        <p class="text-text-heading"><%= @user.email_address %></p>
        <p class="text-sm text-text-muted">
          <%= t("account.profiles.edit.email_readonly_notice") %>
          <%= link_to t("account.profiles.edit.set_password"), new_account_password_path,
                class: "text-interactive underline hover:no-underline" %>
        </p>
      </div>
    <% end %>

    <% if @user.pending_email.present? %>
      <div class="rounded-lg border border-info-border bg-info-surface p-4">
        <div class="flex items-start gap-3">
          <%= icon(:information_circle, size: :md, class: "text-info-icon shrink-0 mt-0.5") %>
          <div>
            <p class="text-sm text-info">
              <%= t("account.profiles.edit.pending_email_notice", email: @user.pending_email) %>
            </p>
            <p class="mt-2">
              <%= link_to t("account.profiles.edit.cancel_email_change"),
                    account_email_confirmation_path,
                    data: { turbo_method: :delete },
                    class: "text-sm text-interactive underline hover:no-underline" %>
            </p>
          </div>
        </div>
      </div>
    <% end %>

    <%= form.submit t("account.profiles.edit.submit"), class: "w-full" %>
  <% end %>
</div>
```

- [ ] **Step 2: Run profile specs**

Run: `bundle exec rspec spec/requests/account/profiles_spec.rb spec/requests/account/email_confirmations_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/views/account/profiles/edit.html.erb config/locales/en/account.en.yml
git commit -m "feat: update profile form with current password field and pending notice

Password users see email + current_password fields. Passwordless
users see email as read-only with link to set password. Pending
email changes show info banner with cancel link."
```

---

### Task 7: Add End-to-End System Specs

**Files:**

- Create: `spec/system/email_change_spec.rb`

- [ ] **Step 1: Create system specs**

Create `spec/system/email_change_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Email change", type: :system do
  let(:user) { create(:user) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  describe "initiating an email change" do
    before do
      sign_in_via_form(user)
      visit edit_account_profile_path
    end

    it "shows verification sent notice with correct password" do
      fill_in I18n.t("account.profiles.edit.email_label"), with: "new@example.com"
      fill_in I18n.t("account.profiles.edit.current_password_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("account.profiles.edit.submit")

      expect(page).to have_text("new@example.com")
      expect(page).to have_text(I18n.t("account.profiles.edit.cancel_email_change"))
    end

    it "shows error with wrong password" do
      fill_in I18n.t("account.profiles.edit.email_label"), with: "new@example.com"
      fill_in I18n.t("account.profiles.edit.current_password_label"), with: "wrongpassword"
      click_button I18n.t("account.profiles.edit.submit")

      expect(page).to have_css("[role='alert']")
    end

    it "updates name without password when email unchanged" do
      fill_in I18n.t("account.profiles.edit.first_name_label"), with: "NewName"
      click_button I18n.t("account.profiles.edit.submit")

      expect(user.reload.first_name).to eq("NewName")
    end
  end

  describe "confirming email change" do
    before do
      sign_in_via_form(user)
      user.initiate_email_change!("confirmed@example.com", "SecureP@ssw0rd123!")
      user.reload
    end

    it "updates email when clicking verification link" do
      visit account_email_confirmation_path(token: user.pending_email_token)

      expect(page).to have_text(I18n.t("account.email_confirmations.show.success"))
      expect(user.reload.email_address).to eq("confirmed@example.com")
    end

    it "rejects expired token" do
      user.update!(pending_email_sent_at: 25.hours.ago)
      visit account_email_confirmation_path(token: user.pending_email_token)

      expect(page).to have_text(I18n.t("account.email_confirmations.show.invalid_or_expired"))
      expect(user.reload.email_address).not_to eq("confirmed@example.com")
    end
  end

  describe "cancelling email change" do
    before do
      sign_in_via_form(user)
      user.initiate_email_change!("cancel@example.com", "SecureP@ssw0rd123!")
      visit edit_account_profile_path
    end

    it "clears pending email" do
      click_link I18n.t("account.profiles.edit.cancel_email_change")

      expect(user.reload.pending_email).to be_nil
      expect(page).not_to have_text("cancel@example.com")
    end
  end
end
```

- [ ] **Step 2: Run system specs**

Run: `bundle exec rspec spec/system/email_change_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add spec/system/email_change_spec.rb
git commit -m "test: add end-to-end system specs for secure email change

Covers initiation with correct/wrong password, name-only updates,
token verification, expired token rejection, and cancellation."
```

---

### Task 8: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec --order defined`
Expected: All specs pass (770+), 0 failures

- [ ] **Step 2: Verify the old "direct email update" test was replaced**

The old test (`"updates the user's email"` in profiles_spec.rb) that directly changed email should no longer exist. The new specs verify that email changes go through the pending flow.

---

## Verification

After all tasks are complete:

1. **Full suite:** `bundle exec rspec --order defined` — all specs green
2. **Happy path:** Sign in → Edit profile → Change email + enter password → Check letter_opener for verification email → Click link → Email updated
3. **Wrong password:** Enter new email + wrong password → error message, email unchanged
4. **No password:** Enter new email, leave password blank → error message
5. **Notification:** Check letter_opener for notification to old email address
6. **Cancel:** Initiate change → see pending notice → click cancel → pending cleared
7. **Expired token:** Initiate change → wait (or manually expire) → click link → rejected
8. **Passwordless user:** OAuth-only user sees email as read-only with "set a password" link
9. **Name-only update:** Change name without touching email → works without password
