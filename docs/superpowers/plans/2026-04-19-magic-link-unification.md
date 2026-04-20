# Magic Link Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the dual magic-link implementation by routing all flows through `MagicLinkToken` model. Merge two callback controllers into one. Remove `magic_link_token`/`magic_link_sent_at` columns from users. Delete 3 User methods, 2 controllers, and 1 view file.

**Architecture:** `MagicLinkToken.create_for_email(email)` becomes the single token creation path. A new `MagicLinkCallbacksController` replaces both `MagicLinkSessionsController` (sign-in) and `MagicLinkRegistrationsController` (registration) with a runtime dispatch: user exists → sign in, user doesn't exist → show registration form. Three callers (`SessionsController#lookup`, `MagicLinksController#create`, `PasswordsController#create`) switch from `user.generate_magic_link_token!` to `MagicLinkToken.create_for_email`.

**Tech Stack:** Rails 8.1, RSpec TDD, Active Record migrations

**Spec:** `docs/superpowers/specs/2026-04-19-magic-link-unification-design.md`

**Important:** All commands use `mise exec --` prefix.

---

## File Structure

### Files to create

- `app/controllers/magic_link_callbacks_controller.rb` — unified callback controller
- `app/views/magic_link_callbacks/new_registration.html.erb` — registration form (moved from magic_link_registrations)
- `spec/requests/magic_link_callbacks_spec.rb` — request specs for the new controller
- `db/migrate/TIMESTAMP_remove_magic_link_columns_from_users.rb` — drop columns

### Files to delete

- `app/controllers/magic_link_sessions_controller.rb`
- `app/controllers/magic_link_registrations_controller.rb`
- `app/views/magic_link_registrations/show.html.erb`
- `spec/requests/magic_link_sessions_spec.rb`
- `spec/requests/magic_link_registrations_spec.rb`
- `spec/models/user_magic_link_spec.rb`

### Files to modify

- `config/routes.rb` — swap routes
- `app/models/user.rb` — remove 3 magic link methods
- `app/mailers/magic_link_mailer.rb` — update `sign_in_link` signature
- `app/views/magic_link_mailer/sign_in_link.html.erb` — use `@link_url` (no `@user.magic_link_token`)
- `app/views/magic_link_mailer/sign_in_link.text.erb` — same
- `app/controllers/sessions_controller.rb` — update lookup
- `app/controllers/magic_links_controller.rb` — update create
- `app/controllers/passwords_controller.rb` — update create
- `spec/mailers/magic_link_mailer_spec.rb` — update sign_in_link tests
- `spec/system/magic_link_sign_in_spec.rb` — update for new route
- `spec/system/magic_link_registration_spec.rb` — update for new route
- `config/locales/` — add callback controller keys

---

### Task 1: Create MagicLinkCallbacksController + routes + request specs (TDD)

**Files:**
- Create: `app/controllers/magic_link_callbacks_controller.rb`
- Create: `app/views/magic_link_callbacks/new_registration.html.erb`
- Create: `spec/requests/magic_link_callbacks_spec.rb`
- Modify: `config/routes.rb`
- Modify: locale files

This task creates the NEW controller and routes alongside the old ones. Both work simultaneously until Task 2 switches callers.

- [ ] **Step 1: Write failing request specs**

Create `spec/requests/magic_link_callbacks_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Magic Link Callbacks", type: :request do
  describe "GET /magic_link_callback/:token" do
    context "with a valid token for an existing user" do
      let(:user) { create(:user) }
      let(:token) { MagicLinkToken.create_for_email(user.email_address) }

      it "signs the user in and redirects to root" do
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(root_path)
        expect(controller.send(:authenticated?)).to be true
      end

      it "consumes the token" do
        get magic_link_callback_path(token: token)
        expect(MagicLinkToken.find_valid(token)).to be_nil
      end
    end

    context "with a valid token for a new email" do
      let(:token) { MagicLinkToken.create_for_email("newuser@example.com") }

      it "renders the registration form" do
        get magic_link_callback_path(token: token)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("newuser@example.com")
      end

      it "does not consume the token yet" do
        get magic_link_callback_path(token: token)
        expect(MagicLinkToken.find_valid(token)).not_to be_nil
      end
    end

    context "with an invalid or expired token" do
      it "redirects to sign in with an alert" do
        get magic_link_callback_path(token: "bogus")
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "with an already-consumed token" do
      let(:token) { MagicLinkToken.create_for_email("test@example.com") }

      before { MagicLinkToken.find_valid(token).consume! }

      it "redirects to sign in with an alert" do
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "POST /magic_link_callback/:token" do
    let(:token) { MagicLinkToken.create_for_email("newuser@example.com") }

    context "with valid registration params" do
      it "creates the user and signs them in" do
        expect {
          post magic_link_callback_path(token: token), params: {
            user: { first_name: "Jane", last_name: "Doe" }
          }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(root_path)
        user = User.find_by(email_address: "newuser@example.com")
        expect(user.first_name).to eq("Jane")
        expect(user.authentications.email.verified.count).to eq(1)
      end

      it "consumes the token" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        expect(MagicLinkToken.find_valid(token)).to be_nil
      end
    end

    context "with invalid registration params" do
      it "re-renders the form" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with an invalid token" do
      it "redirects to sign in" do
        post magic_link_callback_path(token: "bogus"), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests — should fail (no route)**

```bash
mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb --format documentation
```

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, after line 15 (the existing magic link routes), add:

```ruby
get "magic_link_callback/:token", to: "magic_link_callbacks#show", as: :magic_link_callback
post "magic_link_callback/:token", to: "magic_link_callbacks#create"
```

Keep the old routes for now — they'll be removed in Task 5.

- [ ] **Step 4: Create the controller**

Create `app/controllers/magic_link_callbacks_controller.rb`:

```ruby
class MagicLinkCallbacksController < ApplicationController
  allow_unauthenticated_access

  def show
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      redirect_to new_session_path, alert: t(".invalid")
      return
    end

    @user = User.find_by(email_address: token_record.email)
    if @user
      token_record.consume!
      start_new_session_for(@user)
      redirect_to root_path, notice: t(".signed_in")
    else
      @token = params[:token]
      @email = token_record.email
      @user = User.new(email_address: token_record.email)
      render :new_registration
    end
  end

  def create
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      redirect_to new_session_path, alert: t(".invalid")
      return
    end

    @user = User.new(
      email_address: token_record.email,
      first_name: params[:user][:first_name],
      last_name: params[:user][:last_name]
    )

    if @user.save
      @user.authentications.create!(
        provider: "email",
        uid: @user.email_address,
        verified_at: Time.current
      )
      token_record.consume!
      start_new_session_for(@user)
      redirect_to root_path, notice: t(".registered")
    else
      @token = params[:token]
      @email = token_record.email
      render :new_registration, status: :unprocessable_entity
    end
  end
end
```

- [ ] **Step 5: Create the registration view**

Create `app/views/magic_link_callbacks/new_registration.html.erb`:

```erb
<% content_for(:title) { t("magic_link_callbacks.new_registration.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("magic_link_callbacks.new_registration.title") %>
  </h1>

  <p class="mt-2 text-text-muted">
    <%= t("magic_link_callbacks.new_registration.subtitle", email: @email) %>
  </p>

  <%= form_with model: @user, url: magic_link_callback_path(token: @token), method: :post, class: "mt-8 space-y-6" do |form| %>
    <%= form.error_summary %>

    <%= form.text_field :first_name,
          label: t("magic_link_callbacks.new_registration.first_name_label"),
          required: true,
          autofocus: true,
          name: "user[first_name]" %>

    <%= form.text_field :last_name,
          label: t("magic_link_callbacks.new_registration.last_name_label"),
          required: true,
          name: "user[last_name]" %>

    <%= form.submit t("magic_link_callbacks.new_registration.submit"), class: "w-full" %>
  <% end %>
</div>
```

- [ ] **Step 6: Add locale keys**

Add to the appropriate locale file (check which file has magic link keys — likely `config/locales/en.yml` or a specific file). Add:

```yaml
magic_link_callbacks:
  show:
    invalid: "This magic link is invalid or has expired."
    signed_in: "You're now signed in."
    registered: "Welcome! Your account has been created."
  create:
    invalid: "This magic link is invalid or has expired."
    registered: "Welcome! Your account has been created."
  new_registration:
    title: "Complete your registration"
    subtitle: "Just need your name to finish setting up %{email}"
    first_name_label: "First name"
    last_name_label: "Last name"
    submit: "Create account"
```

Check `config/locales/` for where `magic_link_registrations` and `magic_link_sessions` keys live. Mirror the locale file structure.

- [ ] **Step 7: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 8: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass (old routes still work, new routes added alongside).

- [ ] **Step 9: Commit**

```bash
git add app/controllers/magic_link_callbacks_controller.rb app/views/magic_link_callbacks/ spec/requests/magic_link_callbacks_spec.rb config/routes.rb config/locales/
git commit -m "feat: add MagicLinkCallbacksController for unified magic link flow"
```

---

### Task 2: Switch callers to MagicLinkToken + update mailer

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/magic_links_controller.rb`
- Modify: `app/controllers/passwords_controller.rb`
- Modify: `app/mailers/magic_link_mailer.rb`
- Modify: `app/views/magic_link_mailer/sign_in_link.html.erb`
- Modify: `app/views/magic_link_mailer/sign_in_link.text.erb`

All three callers that use `user.generate_magic_link_token!` switch to `MagicLinkToken.create_for_email`. The mailer's `sign_in_link` changes signature from `(user)` to `(email, token)`.

- [ ] **Step 1: Update the mailer**

In `app/mailers/magic_link_mailer.rb`, replace `sign_in_link`:

```ruby
def sign_in_link(email, token)
  @email = email
  @user = User.find_by(email_address: email)
  @link_url = magic_link_callback_url(token: token)

  mail(
    to: email,
    subject: t("magic_link_mailer.sign_in_link.subject")
  )
end
```

Keep `@user` for the email template greeting (`@user.first_name`). If the user doesn't exist (shouldn't happen for sign-in, but defensive), the template can handle nil.

Also update `registration_link` to use the new callback URL:

```ruby
def registration_link(email, token)
  @email = email
  @link_url = magic_link_callback_url(token: token)

  mail(
    to: email,
    subject: t("magic_link_mailer.registration_link.subject")
  )
end
```

- [ ] **Step 2: Update the sign_in_link email template**

In `app/views/magic_link_mailer/sign_in_link.html.erb`, change any reference to `@user.magic_link_token` to use `@link_url` (which is already set). The template should already use `@link_url` — verify and fix if needed.

Check the `.text.erb` version too.

- [ ] **Step 3: Update SessionsController#lookup**

In `app/controllers/sessions_controller.rb`, replace lines 41-51:

```ruby
elsif user
  token = MagicLinkToken.create_for_email(user.email_address)
  MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
  @email_address = email
  render :check_email
else
  token = MagicLinkToken.create_for_email(email)
  MagicLinkMailer.registration_link(email, token).deliver_later
  @email_address = email
  render :check_email
end
```

- [ ] **Step 4: Update MagicLinksController#create**

In `app/controllers/magic_links_controller.rb`, replace the body of `create`:

```ruby
def create
  email = params[:email_address]&.downcase&.strip
  user = User.find_by(email_address: email)

  if user
    token = MagicLinkToken.create_for_email(user.email_address)
    MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
  end

  redirect_to new_session_path, notice: t(".check_email")
end
```

- [ ] **Step 5: Update PasswordsController#create**

In `app/controllers/passwords_controller.rb`, replace lines 14-17:

```ruby
else
  token = MagicLinkToken.create_for_email(user.email_address)
  MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
end
```

- [ ] **Step 6: Update mailer spec**

In `spec/mailers/magic_link_mailer_spec.rb`, find the `sign_in_link` examples. They currently do `user.generate_magic_link_token!` before calling the mailer. Replace with `MagicLinkToken.create_for_email`:

Change test setup from:
```ruby
before { user.generate_magic_link_token! }
let(:mail) { described_class.sign_in_link(user) }
```

To:
```ruby
let(:token) { MagicLinkToken.create_for_email(user.email_address) }
let(:mail) { described_class.sign_in_link(user.email_address, token) }
```

Update assertions: the mailer URL should now contain `magic_link_callback` instead of `magic_link_session`.

- [ ] **Step 7: Run tests**

```bash
mise exec -- bundle exec rspec spec/mailers/magic_link_mailer_spec.rb spec/requests/sessions_spec.rb spec/requests/magic_links_spec.rb --format documentation
```

Expected: PASS (callers now use MagicLinkToken, old controllers still exist for old routes).

- [ ] **Step 8: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

- [ ] **Step 9: Commit**

```bash
git add app/controllers/sessions_controller.rb app/controllers/magic_links_controller.rb app/controllers/passwords_controller.rb app/mailers/magic_link_mailer.rb app/views/magic_link_mailer/ spec/mailers/
git commit -m "refactor: switch all magic link callers to MagicLinkToken"
```

---

### Task 3: Remove User magic link methods + drop columns

**Files:**
- Modify: `app/models/user.rb`
- Create: migration to drop columns
- Delete: `spec/models/user_magic_link_spec.rb`

- [ ] **Step 1: Remove the three methods from User**

In `app/models/user.rb`, delete `generate_magic_link_token!`, `magic_link_token_valid?`, and `clear_magic_link_token!` (around lines 71-84).

- [ ] **Step 2: Delete the model spec**

```bash
rm spec/models/user_magic_link_spec.rb
```

- [ ] **Step 3: Create the migration**

```bash
mise exec -- bin/rails generate migration RemoveMagicLinkColumnsFromUsers
```

Edit:

```ruby
class RemoveMagicLinkColumnsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :magic_link_token
    remove_column :users, :magic_link_token, :string
    remove_column :users, :magic_link_sent_at, :datetime
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
mise exec -- bin/rails db:migrate
```

- [ ] **Step 5: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: Some old magic link specs may fail if they reference the removed columns or methods. Note failures — Task 4 cleans those up.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb db/migrate/ db/schema.rb
git rm spec/models/user_magic_link_spec.rb
git commit -m "feat: remove magic link columns from users (unified under MagicLinkToken)"
```

---

### Task 4: Delete old controllers + update system specs

**Files:**
- Delete: `app/controllers/magic_link_sessions_controller.rb`
- Delete: `app/controllers/magic_link_registrations_controller.rb`
- Delete: `app/views/magic_link_registrations/show.html.erb`
- Delete: `spec/requests/magic_link_sessions_spec.rb`
- Delete: `spec/requests/magic_link_registrations_spec.rb`
- Modify: `config/routes.rb` — remove old routes
- Modify: `spec/system/magic_link_sign_in_spec.rb` — update for new route
- Modify: `spec/system/magic_link_registration_spec.rb` — update for new route

- [ ] **Step 1: Remove old routes**

In `config/routes.rb`, delete:

```ruby
get "magic_link_session/:token", to: "magic_link_sessions#show", as: :magic_link_session
get "magic_link_registration/:token", to: "magic_link_registrations#show", as: :magic_link_registration
post "magic_link_registration/:token", to: "magic_link_registrations#create"
```

- [ ] **Step 2: Delete old controllers and views**

```bash
rm app/controllers/magic_link_sessions_controller.rb
rm app/controllers/magic_link_registrations_controller.rb
rm -rf app/views/magic_link_registrations/
```

- [ ] **Step 3: Delete old request specs**

```bash
rm spec/requests/magic_link_sessions_spec.rb
rm spec/requests/magic_link_registrations_spec.rb
```

- [ ] **Step 4: Update magic link sign-in system spec**

Read `spec/system/magic_link_sign_in_spec.rb`. Find all references to `magic_link_session_path` and replace with `magic_link_callback_path`. The spec likely:
- Creates a user
- Generates a token (this needs to switch from `user.generate_magic_link_token!` / `user.magic_link_token` to `MagicLinkToken.create_for_email`)
- Visits the callback URL
- Asserts sign-in success

Update the setup to use `MagicLinkToken.create_for_email(user.email_address)` and visit `magic_link_callback_path(token: token)`.

- [ ] **Step 5: Update magic link registration system spec**

Read `spec/system/magic_link_registration_spec.rb`. Find all references to `magic_link_registration_path` and replace with `magic_link_callback_path`. The spec should already use `MagicLinkToken.create_for_email` — just update the path.

Also update any text assertions if the locale keys changed (e.g., the page title may now come from `magic_link_callbacks.new_registration.title` instead of `magic_link_registrations.new.title`).

- [ ] **Step 6: Run all system specs**

```bash
mise exec -- bundle exec rspec spec/system/magic_link_sign_in_spec.rb spec/system/magic_link_registration_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 7: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass. The test count will drop (deleted old request specs) but the new callbacks spec + updated system specs cover the same flows.

- [ ] **Step 8: Commit**

```bash
git rm app/controllers/magic_link_sessions_controller.rb app/controllers/magic_link_registrations_controller.rb app/views/magic_link_registrations/show.html.erb spec/requests/magic_link_sessions_spec.rb spec/requests/magic_link_registrations_spec.rb
git add config/routes.rb spec/system/
git commit -m "chore: delete old magic link controllers and update system specs"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass.

- [ ] **Step 2: Verify no references to old patterns remain**

```bash
grep -rn "magic_link_session_path\|magic_link_session_url\|magic_link_registration_path\|magic_link_registration_url\|generate_magic_link_token\|clear_magic_link_token\|magic_link_token_valid" app/ spec/ config/
```

Expected: ZERO matches.

- [ ] **Step 3: Verify no references to deleted files**

```bash
grep -rn "MagicLinkSessionsController\|MagicLinkRegistrationsController" app/ spec/ config/
```

Expected: ZERO matches.

- [ ] **Step 4: Count deleted lines**

```bash
git diff --stat main..HEAD
```

Expected: net negative lines (more deleted than added).

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|---|---|
| New MagicLinkCallbacksController (show + create) | Task 1 ✓ |
| New route (`magic_link_callback/:token`) | Task 1 ✓ |
| Registration view moved | Task 1 ✓ |
| Locale keys for new controller | Task 1 ✓ |
| SessionsController#lookup updated | Task 2 ✓ |
| MagicLinksController#create updated | Task 2 ✓ |
| PasswordsController#create updated | Task 2 ✓ |
| Mailer sign_in_link signature change | Task 2 ✓ |
| Mailer templates use @link_url | Task 2 ✓ |
| User model methods removed | Task 3 ✓ |
| Columns dropped from users | Task 3 ✓ |
| Old controllers deleted | Task 4 ✓ |
| Old routes removed | Task 4 ✓ |
| System specs updated | Task 4 ✓ |
| Old request/model specs deleted | Task 3 + 4 ✓ |

### Placeholder scan

No TBD, TODO, or vague instructions. Task 4 step 4-5 say "read the spec and update" — but include specific guidance on what to change (paths + token setup).

### Type consistency

- `MagicLinkToken.create_for_email(email)` returns a string token — consistent across all callers
- `MagicLinkMailer.sign_in_link(email, token)` — new signature used in Tasks 2 (callers) and 2 (mailer spec)
- `magic_link_callback_path(token:)` — consistent route helper across Task 1 (controller), Task 1 (view), Task 2 (mailer), Task 4 (system specs)
