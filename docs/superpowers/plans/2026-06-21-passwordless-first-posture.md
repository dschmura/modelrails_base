# Passwordless-First Posture — Implementation Plan (Phase A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make magic-link (+ OAuth) the default and only signup/sign-in path, demote password to a settings-only opt-in (add/change/remove), and route all recovery — including a forgotten password — through the single hardened `MagicLinkToken` primitive.

**Architecture:** This is mostly *reshaping and removing*, not new plumbing. The email-first `SessionsController#lookup` becomes the only door; `lookup` always issues a magic-link and only offers a password form as a secondary link for opt-in users. `RegistrationsController` (password signup) and `PasswordsController` (reset-token flow) are deleted. The magic-link signup path already consumes pending invitations via `Signupable`; we add the missing open-link-join consumption there. Forgot-password becomes a magic-link carrying a server-side return-intent that lands the user on a password-change form.

**Tech Stack:** Rails 8.1, Ruby 4.0.4, RSpec + Capybara/Playwright (system specs), SQLite, custom Rails-8 session auth (`Current.user`), `MagicLinkToken`, `Authentication` (provider enum), Pundit, TailwindCSS 4 / modelrails_ui.

## Global Constraints

- Ruby **4.0.4**, Rails **8.1**; manage tools via `mise exec --` (e.g. `mise exec -- bundle exec rspec`).
- **TDD, no exceptions:** every task writes a failing spec first, runs it red, then implements. Behaviors/outcomes, not implementation details.
- **No password is ever required or surfaced at signup or sign-in.** Password exists only under `settings/password`.
- **One email-recovery primitive:** `MagicLinkToken`. Do not add a second reset-token system.
- **Return-intent is a server-side enum mapped to a fixed path — never a user-supplied URL** (open-redirect guard).
- All user-facing text uses **I18n locale keys** (no hardcoded strings). Reuse existing keys where possible; add new keys under the same files (`config/locales/en/auth.en.yml`, `config/locales/en/magic_links.en.yml`).
- **Pundit**: auth controllers here are `allow_unauthenticated_access` flows; no new policies needed. `settings/*` runs authenticated.
- **AAA** (WCAG 2.2 AAA) on all touched UI; proven in CI, verified in both light + dark themes. Use `UI::*` primitives / canonical classes already present in these views (`form_with`, `focus-ring`, `btn-primary`, `text-text-*`).
- **Full RSpec suite green (0 failures)** before every commit (`mise exec -- bundle exec rspec`). Never bypass Lefthook.
- Mailer `deliver_later` calls stay outside DB transactions.

---

## File Structure

**Modify:**
- `app/controllers/sessions_controller.rb` — reshape `lookup`; keep `new`/`create`/`destroy`.
- `app/controllers/magic_link_callbacks_controller.rb` — honor return-intent; repoint closed-redirect.
- `app/controllers/concerns/signupable.rb` — add `accept_pending_join_link!`.
- `app/controllers/settings/passwords_controller.rb` — add `edit`/`update` (change) and `destroy` (remove); route `new` for has-password users to `edit`.
- `app/models/magic_link_token.rb` — `create_for_email(email, intent: nil)`.
- `app/views/sessions/check_email.html.erb` — secondary "use password instead" link; fix sign-up link.
- `app/views/sessions/password_form.html.erb` — repoint "forgot password" link.
- `app/views/settings/passwords/new.html.erb` + new `edit.html.erb`; settings UI add/change/remove.
- `config/routes.rb` — add `password_reset`; `settings { resource :password, only: [:new,:create,:edit,:update,:destroy] }`; remove `resource :registration` and `resources :passwords`.
- `config/locales/en/auth.en.yml`, `config/locales/en/magic_links.en.yml` — new/renamed keys.
- Repoint `new_registration_path` callers: `app/views/shared/_header.html.erb`, `app/views/sessions/new.html.erb`, `app/views/invitation_accepts/show.html.erb`, `app/views/pages/home.html.erb`, `app/controllers/invitation_accepts_controller.rb`, `app/controllers/omniauth_callbacks_controller.rb`, `app/controllers/workspaces/joins_controller.rb`.

**Create:**
- `app/controllers/password_resets_controller.rb` — forgot-password → magic-link (intent: set_password).
- `app/views/sessions/closed.html.erb` — closed-signups state (relocated from `registrations/closed`).
- `db/migrate/<ts>_add_intent_to_magic_link_tokens.rb`.
- Specs per task (see tasks).

**Delete:**
- `app/controllers/registrations_controller.rb`, `app/views/registrations/` (`new.html.erb`, `closed.html.erb`).
- `app/controllers/passwords_controller.rb`, `app/views/passwords/`.
- Their specs (replace, see Task 8).

---

### Task 1: MagicLinkToken return-intent

**Files:**
- Migrate: `db/migrate/<ts>_add_intent_to_magic_link_tokens.rb`
- Modify: `app/models/magic_link_token.rb`
- Test: `spec/models/magic_link_token_spec.rb`

**Interfaces:**
- Produces: `MagicLinkToken.create_for_email(email, intent: nil)` → returns token string; persists `intent` (string, nullable). `MagicLinkToken#intent` reads it back.

- [ ] **Step 1: Write the failing test**

Add to `spec/models/magic_link_token_spec.rb`:

```ruby
describe ".create_for_email with intent" do
  it "persists a server-side intent on the issued token" do
    token = MagicLinkToken.create_for_email("a@example.com", intent: "set_password")
    expect(MagicLinkToken.find_by(token: token).intent).to eq("set_password")
  end

  it "defaults intent to nil for ordinary sign-in/registration links" do
    token = MagicLinkToken.create_for_email("b@example.com")
    expect(MagicLinkToken.find_by(token: token).intent).to be_nil
  end
end
```

- [ ] **Step 2: Run it red**

Run: `mise exec -- bundle exec rspec spec/models/magic_link_token_spec.rb -e "with intent"`
Expected: FAIL (unknown keyword `intent:` / no `intent` column).

- [ ] **Step 3: Migration**

Create `db/migrate/<ts>_add_intent_to_magic_link_tokens.rb`:

```ruby
class AddIntentToMagicLinkTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :magic_link_tokens, :intent, :string
  end
end
```

Run: `mise exec -- bin/rails db:migrate`

- [ ] **Step 4: Accept the keyword**

In `app/models/magic_link_token.rb`, change the signature and the `create!`:

```ruby
def self.create_for_email(email, intent: nil)
  normalized_email = email.downcase
  token = SecureRandom.urlsafe_base64(32)

  transaction do
    where(email: normalized_email, consumed_at: nil).update_all(consumed_at: Time.current)
    create!(token: token, email: normalized_email, expires_at: 15.minutes.from_now, intent: intent)
  end
  token
rescue ActiveRecord::RecordNotUnique
  where(email: normalized_email, consumed_at: nil).order(created_at: :desc).first&.token
end
```

- [ ] **Step 5: Green + commit**

Run: `mise exec -- bundle exec rspec spec/models/magic_link_token_spec.rb`
Expected: PASS.

```bash
git add db/migrate db/schema.rb app/models/magic_link_token.rb spec/models/magic_link_token_spec.rb
git commit -m "feat(auth): add server-side intent to MagicLinkToken"
```

---

### Task 2: Settings password — add/change/remove lifecycle

**Files:**
- Modify: `app/controllers/settings/passwords_controller.rb`
- Create: `app/views/settings/passwords/edit.html.erb`
- Modify: `app/views/settings/passwords/new.html.erb` (no change needed beyond confirming) and the settings UI entry (`app/views/settings/connected_accounts/index.html.erb` or wherever "Add a password" links — grep `new_settings_password_path`)
- Modify: `config/routes.rb` (settings password route)
- Locale: `config/locales/en/auth.en.yml` (`settings.passwords.edit.*`, `settings.passwords.update.*`, `settings.passwords.destroy.*`)
- Test: `spec/requests/settings/passwords_spec.rb`

**Interfaces:**
- Produces: routes `edit_settings_password_path`, `settings_password_path` (PATCH update, DELETE destroy). `new` redirects has-password users to `edit`.

- [ ] **Step 1: Failing test**

Create `spec/requests/settings/passwords_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Settings::Passwords", type: :request do
  let(:user) { create(:user) } # factory user has a password

  before { sign_in(user) } # use the project's auth helper

  describe "PATCH /settings/password (change)" do
    it "updates the password for a user who already has one" do
      patch settings_password_path, params: { user: { password: "brand-new-passw0rd", password_confirmation: "brand-new-passw0rd" } }
      expect(user.reload.authenticate("brand-new-passw0rd")).to be_truthy
    end
  end

  describe "DELETE /settings/password (remove)" do
    it "removes the password and the email authentication, returning to passwordless" do
      delete settings_password_path
      expect(user.reload.has_password?).to be(false)
    end
  end

  describe "GET /settings/password/new for a user who already has a password" do
    it "routes them to the change form instead of add" do
      get new_settings_password_path
      expect(response).to redirect_to(edit_settings_password_path)
    end
  end
end
```

> If the project lacks a `sign_in` request helper, use the existing pattern from a neighboring `spec/requests/settings/*_spec.rb` to authenticate; match that file's convention exactly.

- [ ] **Step 2: Run red**

Run: `mise exec -- bundle exec rspec spec/requests/settings/passwords_spec.rb`
Expected: FAIL (no `edit`/`update`/`destroy` routes/actions).

- [ ] **Step 3: Route**

In `config/routes.rb`, change:

```ruby
resource :password, only: [ :new, :create ]
```

to:

```ruby
resource :password, only: [ :new, :create, :edit, :update, :destroy ]
```

- [ ] **Step 4: Controller**

Replace `app/controllers/settings/passwords_controller.rb` body with:

```ruby
module Settings
  class PasswordsController < ApplicationController
    def new
      redirect_to edit_settings_password_path if Current.user.has_password?
    end

    def create
      if Current.user.has_password?
        redirect_to edit_settings_password_path, alert: t(".already_has_password")
        return
      end

      if Current.user.update(password_params)
        Current.user.authentications.create!(
          provider: "email",
          uid: Current.user.email_address,
          verified_at: Time.current
        )
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      redirect_to new_settings_password_path unless Current.user.has_password?
    end

    def update
      unless Current.user.has_password?
        redirect_to new_settings_password_path
        return
      end

      if Current.user.update(password_params)
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Current.user.authentications.email.destroy_all
      Current.user.update_columns(password_digest: nil)
      redirect_to settings_connected_accounts_path, notice: t(".success")
    end

    private

    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end
  end
end
```

> `destroy` uses `update_columns` to null the digest without re-running `has_secure_password` setters. Confirm `authentications.email` scope exists (it's used in `Authentication` per existing code); if the scope name differs, match it.

- [ ] **Step 5: Edit view**

Create `app/views/settings/passwords/edit.html.erb` (mirror `new.html.erb`, change copy + a Remove button):

```erb
<% content_for(:title) { t("settings.passwords.edit.title") } %>

<div class="space-y-6">
  <h1 class="text-2xl font-bold text-text-heading"><%= t("settings.passwords.edit.title") %></h1>

  <%= form_with url: settings_password_path, method: :patch, local: true, class: "space-y-6" do |form| %>
    <%= form.password_field :password,
          label: t("settings.passwords.edit.password_label"),
          required: true, autocomplete: "new-password" %>
    <%= form.password_field :password_confirmation,
          label: t("settings.passwords.edit.password_confirmation_label"),
          required: true, autocomplete: "new-password" %>
    <p class="text-sm text-text-muted"><%= t("settings.passwords.edit.password_hint") %></p>
    <%= form.submit t("settings.passwords.edit.submit"), class: "w-full" %>
  <% end %>

  <%= button_to t("settings.passwords.edit.remove"), settings_password_path,
        method: :delete, class: "btn-text-danger w-full" %>
</div>
```

- [ ] **Step 6: Locale keys**

Add under `settings.passwords` in `config/locales/en/auth.en.yml`:

```yaml
    edit:
      title: "Change your password"
      password_label: "New password"
      password_confirmation_label: "Confirm new password"
      password_hint: "Must be at least 12 characters."
      submit: "Update password"
      remove: "Remove password (use sign-in links instead)"
    update:
      success: "Password updated."
    destroy:
      success: "Password removed. You'll sign in with a link from now on."
```

- [ ] **Step 7: Green + commit**

Run: `mise exec -- bundle exec rspec spec/requests/settings/passwords_spec.rb`
Expected: PASS.

```bash
git add app/controllers/settings/passwords_controller.rb app/views/settings/passwords config/routes.rb config/locales/en/auth.en.yml spec/requests/settings/passwords_spec.rb
git commit -m "feat(auth): settings password add/change/remove lifecycle"
```

---

### Task 3: Forgot-password → magic-link (intent: set_password) → change form

**Files:**
- Create: `app/controllers/password_resets_controller.rb`
- Modify: `config/routes.rb` (add `resource :password_reset, only: [:create]`)
- Modify: `app/controllers/magic_link_callbacks_controller.rb` (`show` honors intent)
- Modify: `app/views/sessions/password_form.html.erb` ("forgot" link → `button_to password_reset_path`)
- Locale: reuse `sessions.new.forgot_password`; add `password_resets.create.*` if a distinct notice is wanted (else reuse `sessions.check_email`)
- Test: `spec/requests/password_resets_spec.rb`, add a case to `spec/requests/magic_link_callbacks_spec.rb`

**Interfaces:**
- Consumes: `MagicLinkToken.create_for_email(email, intent: "set_password")` (Task 1).
- Produces: `password_reset_path` (POST). Callback `show` redirects to `edit_settings_password_path` when `token_record.intent == "set_password"`.

- [ ] **Step 1: Failing tests**

Create `spec/requests/password_resets_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "PasswordResets", type: :request do
  let(:user) { create(:user) }

  it "issues a set_password magic link and shows the check-email screen" do
    expect {
      post password_reset_path, params: { email_address: user.email_address }
    }.to change { MagicLinkToken.where(email: user.email_address, intent: "set_password").count }.by(1)
    expect(response.body).to include(I18n.t("sessions.check_email.title")).or include("Check your email")
  end
end
```

Add to `spec/requests/magic_link_callbacks_spec.rb`:

```ruby
context "valid token with set_password intent" do
  let(:user) { create(:user) }
  let(:token) { MagicLinkToken.create_for_email(user.email_address, intent: "set_password") }

  it "signs in and lands on the change-password form" do
    get magic_link_callback_path(token: token)
    expect(response).to redirect_to(edit_settings_password_path)
  end
end
```

- [ ] **Step 2: Run red**

Run: `mise exec -- bundle exec rspec spec/requests/password_resets_spec.rb spec/requests/magic_link_callbacks_spec.rb -e "set_password"`
Expected: FAIL (no route/controller; callback ignores intent).

- [ ] **Step 3: Route + controller**

In `config/routes.rb` add (near the other auth routes):

```ruby
resource :password_reset, only: [ :create ]
```

Create `app/controllers/password_resets_controller.rb`:

```ruby
class PasswordResetsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

  def create
    email = params[:email_address].to_s.downcase.strip
    user = User.find_by(email_address: email)

    # Always show the same confirmation — never reveal whether the address
    # exists or has a password. Only a real password-holder gets a link.
    if user&.has_password?
      token = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
      MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
    end

    @email_address = email
    render "sessions/check_email"
  end
end
```

- [ ] **Step 4: Callback honors intent**

In `app/controllers/magic_link_callbacks_controller.rb#show`, replace the post-consume redirect for the existing-user branch:

```ruby
start_new_session_for(@user)
redirect_to magic_link_return_path(token_record), notice: t(".signed_in")
```

Add a private method to the controller:

```ruby
private

# Server-side intent → fixed path. Never trust a user-supplied URL here.
def magic_link_return_path(token_record)
  case token_record.intent
  when "set_password" then edit_settings_password_path
  else after_authentication_url
  end
end
```

- [ ] **Step 5: Repoint the "forgot" link**

In `app/views/sessions/password_form.html.erb`, replace the forgot-password `link_to ... new_registration_path` with:

```erb
<%= button_to t("sessions.new.forgot_password"), password_reset_path,
      params: { email_address: @email_address }, method: :post,
      class: "text-center text-sm text-interactive underline w-full" %>
```

- [ ] **Step 6: Green + commit**

Run: `mise exec -- bundle exec rspec spec/requests/password_resets_spec.rb spec/requests/magic_link_callbacks_spec.rb`
Expected: PASS.

```bash
git add app/controllers/password_resets_controller.rb app/controllers/magic_link_callbacks_controller.rb app/views/sessions/password_form.html.erb config/routes.rb spec/requests/password_resets_spec.rb spec/requests/magic_link_callbacks_spec.rb
git commit -m "feat(auth): forgot-password backed by magic-link (set_password intent)"
```

---

### Task 4: `lookup` reshape — magic-link first, password secondary, closed-gate

**Files:**
- Modify: `app/controllers/sessions_controller.rb#lookup`
- Modify: `app/views/sessions/check_email.html.erb`
- Create: `app/views/sessions/closed.html.erb` (relocate from `registrations/closed`)
- Test: `spec/requests/sessions_spec.rb` (or the existing sessions request spec)

**Interfaces:**
- Produces: `lookup` always issues a magic-link for existing users (sets `@has_password`); new email gated by `signups_open?` (renders `sessions/closed` when closed) then issues a registration link. No branch renders `password_form` directly.

- [ ] **Step 1: Failing tests**

Add to `spec/requests/sessions_spec.rb`:

```ruby
describe "POST /session/lookup (passwordless-first)" do
  it "sends a magic link to a password user instead of going straight to the password form" do
    user = create(:user) # has a password
    expect {
      post session_lookup_path, params: { email_address: user.email_address }
    }.to change { MagicLinkToken.where(email: user.email_address).count }.by(1)
    expect(response.body).to include(I18n.t("sessions.check_email.title"))
    expect(response.body).to include(I18n.t("sessions.check_email.use_password")) # secondary link present
  end

  it "blocks registration of a new email when signups are closed" do
    allow_any_instance_of(SessionsController).to receive(:signups_open?).and_return(false)
    expect {
      post session_lookup_path, params: { email_address: "newcomer@example.com" }
    }.not_to change(MagicLinkToken, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("registrations.closed.title"))
  end
end
```

- [ ] **Step 2: Run red**

Run: `mise exec -- bundle exec rspec spec/requests/sessions_spec.rb -e "passwordless-first"`
Expected: FAIL (password user gets `password_form`; new email not gated).

- [ ] **Step 3: Reshape `lookup`**

Replace `SessionsController#lookup` body (`app/controllers/sessions_controller.rb:28`):

```ruby
def lookup
  @email_lookup_form = EmailLookupForm.new(email_address: params[:email_address])

  unless @email_lookup_form.valid?
    render :email_error
    return
  end

  email = @email_lookup_form.email_address.downcase.strip
  user = User.find_by(email_address: email)

  if user
    token = MagicLinkToken.create_for_email(user.email_address)
    MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
    @email_address = email
    @has_password = user.has_password?
    render :check_email
  else
    unless signups_open?
      render :closed, status: :unprocessable_entity
      return
    end
    token = MagicLinkToken.create_for_email(email)
    MagicLinkMailer.registration_link(email, token).deliver_later
    @email_address = email
    render :check_email
  end
end
```

- [ ] **Step 4: check_email secondary link + relocate closed view**

In `app/views/sessions/check_email.html.erb`, replace the bottom `link_to ... new_registration_path` block with a conditional secondary password link:

```erb
<% if @has_password %>
  <p class="text-sm text-text-muted">
    <%= link_to t("sessions.check_email.use_password"),
          session_lookup_path(email_address: @email_address),
          data: { turbo_method: :post },
          class: "text-interactive underline hover:no-underline focus-ring rounded" %>
  </p>
<% end %>
```

> The secondary link re-POSTs lookup with the email; we need it to reach the password form. Simplest: have `check_email`'s "use password instead" link to a small GET that renders `password_form` for the email. If a GET entry to `password_form` doesn't exist, add `get "session/password", to: "sessions#password", as: :session_password` rendering `password_form` with `@email_address = params[:email_address]`, and point the link there. Pick the approach that keeps `password_form` reachable without re-issuing a magic link; document which you chose in the commit.

Create `app/views/sessions/closed.html.erb` by moving `app/views/registrations/closed.html.erb` content verbatim (it already links to `new_session_path` and renders `shared/oauth_buttons`).

Add locale key under `sessions.check_email` in `config/locales/en/auth.en.yml`:

```yaml
      use_password: "Prefer to use your password? Sign in with it instead."
```

- [ ] **Step 5: Green + commit**

Run: `mise exec -- bundle exec rspec spec/requests/sessions_spec.rb`
Expected: PASS.

```bash
git add app/controllers/sessions_controller.rb app/views/sessions config/locales/en/auth.en.yml spec/requests/sessions_spec.rb
git commit -m "feat(auth): lookup leads with magic-link, password secondary, gate closed signups"
```

---

### Task 5: Open-link-join consumption on the magic-link signup path

**Files:**
- Modify: `app/controllers/concerns/signupable.rb` (add `accept_pending_join_link!`)
- Test: `spec/system/passwordless_join_link_spec.rb` (system), and a request-level guard in `spec/requests/magic_link_callbacks_spec.rb`

**Interfaces:**
- Consumes: `session[:pending_join_token]`, `WorkspaceJoinLink.active.find_by(token:)`, `Workspace#admit(user, role:)`, `Workspace#default_self_join_role` (all exist; see `Authentication#claim_pending_join_link!`).
- Produces: `commit_signup_atomically` now also admits via a pending join link.

- [ ] **Step 1: Failing test (the gap)**

Add to `spec/requests/magic_link_callbacks_spec.rb`:

```ruby
context "registration via magic link with a pending open-link join token" do
  let(:workspace) { create(:workspace) } # ensure it is open_join? in setup
  let(:join_link) { create(:workspace_join_link, workspace: workspace) } # active link factory

  before do
    workspace.update!(join_policy: :open_link) # match the project's open-join setup
  end

  it "admits the brand-new magic-link user as a member" do
    token = MagicLinkToken.create_for_email("joiner@example.com")
    # Simulate the join-link landing having parked the token in session:
    post magic_link_callback_path(token: token),
         params: { user: { first_name: "Jo", last_name: "Iner" } },
         env: { "rack.session" => { pending_join_token: join_link.token } }

    user = User.find_by(email_address: "joiner@example.com")
    expect(user.memberships.kept.where(workspace: workspace)).to exist
  end
end
```

> Match the project's factory names and the exact way it makes a workspace `open_join?` — read `spec/factories` and `Workspace#open_join?` first; adjust the setup so `join_link.workspace.open_join?` is true. The behavioral assertion (membership exists) is the contract.

- [ ] **Step 2: Run red**

Run: `mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb -e "pending open-link join"`
Expected: FAIL (no membership — `Signupable` ignores the join token).

- [ ] **Step 3: Implement in Signupable**

In `app/controllers/concerns/signupable.rb`, call a new method inside the transaction in `commit_signup_atomically`, right after `accept_pending_invitation!(user)`:

```ruby
      accept_pending_invitation!(user)
      accept_pending_join_link!(user)
```

Add the method (mirrors `accept_pending_invitation!`; magic-link/OAuth users are already email-verified, so claim immediately):

```ruby
  # Consumes the session's pending open-link join token for a freshly-signed-up,
  # email-verified user. Stale link conditions (revoked, policy reverted) are
  # silent no-ops. Capacity errors surface as a flash but don't abort signup.
  def accept_pending_join_link!(user)
    token = session[:pending_join_token]
    return if token.blank?

    link = WorkspaceJoinLink.active.find_by(token: token)
    if link.nil? || !link.workspace.open_join?
      session.delete(:pending_join_token)
      return
    end

    begin
      link.workspace.admit(user, role: link.workspace.default_self_join_role)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.message.match?(/already a member/i)
    ensure
      session.delete(:pending_join_token)
    end
  end
```

> `admit` does its own locking/capacity. Calling it inside `commit_signup_atomically`'s transaction is acceptable (atomic with user creation). If a capacity `RecordInvalid` that is NOT "already a member" should block signup, let it propagate — but matching `Authentication#claim_pending_join_link!`, capacity there is surfaced post-hoc; keep parity by rescuing only the benign "already a member" and re-raising others (the outer `commit_signup_atomically` rescues `RecordInvalid` → returns false → form re-render). Confirm the desired behavior against the invitation path and keep them consistent.

- [ ] **Step 4: Green + add invitation regression guard**

Add an invitation-via-magic-link guard to the same spec file (proves the already-working path stays working once magic-link is the only signup):

```ruby
context "registration via magic link with a pending invitation" do
  it "accepts the invitation and creates the membership" do
    invitation = create(:invitation, email: "invitee@example.com") # match factory + role
    token = MagicLinkToken.create_for_email("invitee@example.com")
    post magic_link_callback_path(token: token),
         params: { user: { first_name: "In", last_name: "Vitee" } },
         env: { "rack.session" => { pending_invitation_token: invitation.token } }
    user = User.find_by(email_address: "invitee@example.com")
    expect(user.memberships.kept).to exist
  end
end
```

Run: `mise exec -- bundle exec rspec spec/requests/magic_link_callbacks_spec.rb`
Expected: PASS (both join-link and invitation).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/signupable.rb spec/requests/magic_link_callbacks_spec.rb
git commit -m "feat(auth): consume pending open-link join on magic-link signup"
```

---

### Task 6: Remove RegistrationsController (password signup)

**Files:**
- Delete: `app/controllers/registrations_controller.rb`, `app/views/registrations/new.html.erb`, `app/views/registrations/closed.html.erb`
- Modify: `config/routes.rb` (remove `resource :registration`)
- Repoint callers of `new_registration_path` → `new_session_path`: `app/views/shared/_header.html.erb`, `app/views/sessions/new.html.erb`, `app/views/invitation_accepts/show.html.erb`, `app/views/pages/home.html.erb`, `app/controllers/invitation_accepts_controller.rb`, `app/controllers/omniauth_callbacks_controller.rb`, `app/controllers/workspaces/joins_controller.rb`, `app/controllers/magic_link_callbacks_controller.rb` (closed-signups redirect)
- Delete/replace: `spec/requests/registrations_spec.rb` (and any registration system spec)
- Test: routing guard in `spec/routing/` or a request spec expecting 404

**Interfaces:**
- Produces: no `new_registration_path` / `registration_path` anywhere; the single email entry (`sessions#new`) is the only signup.

- [ ] **Step 1: Failing test**

Add to `spec/requests/sessions_spec.rb` (or a new `spec/requests/removed_routes_spec.rb`):

```ruby
it "no longer exposes the password registration route" do
  expect { new_registration_path }.to raise_error(NoMethodError)
end
```

- [ ] **Step 2: Run red**

Run: `mise exec -- bundle exec rspec spec/requests/sessions_spec.rb -e "registration route"`
Expected: FAIL (route still exists).

- [ ] **Step 3: Repoint all callers**

Grep and replace every `new_registration_path` with `new_session_path` (and remove redundant "Sign up" affordances on `sessions/new`, since that screen *is* signup). For `magic_link_callbacks_controller.rb#create` closed branch, change:

```ruby
redirect_to new_registration_path,
            alert: t("registrations.closed.oauth_blocked"),
            status: :see_other
```

to:

```ruby
redirect_to new_session_path,
            alert: t("registrations.closed.oauth_blocked"),
            status: :see_other
```

Verify with: `grep -rn "new_registration_path\|registration_path" app/ config/ spec/` → expect zero (except the failing-test line, which you'll update to confirm the route is gone).

- [ ] **Step 4: Delete controller/views/route**

```bash
git rm app/controllers/registrations_controller.rb app/views/registrations/new.html.erb app/views/registrations/closed.html.erb
git rm spec/requests/registrations_spec.rb # if present; replace coverage via Task 8
```

Remove `resource :registration, only: [ :new, :create ]` from `config/routes.rb`.

- [ ] **Step 5: Green + full suite + commit**

Run: `mise exec -- bundle exec rspec`
Expected: PASS (0 failures). Fix any spec that referenced registration signup by routing it through magic-link or settings-opt-in.

```bash
git add -A
git commit -m "refactor(auth): remove password registration; single email-first signup"
```

---

### Task 7: Remove PasswordsController (reset-token flow)

**Files:**
- Delete: `app/controllers/passwords_controller.rb`, `app/views/passwords/` (e.g. `new.html.erb`, `edit.html.erb`)
- Modify: `config/routes.rb` (remove `resources :passwords, param: :token`)
- Repoint any remaining `*password*_path` reset links (forgot already handled in Task 3) → none should remain
- Delete/replace: `spec/requests/passwords_spec.rb` (reset-token specs)

**Interfaces:**
- Produces: no public reset-token routes; recovery is magic-link only.

- [ ] **Step 1: Failing test**

Add to the removed-routes spec:

```ruby
it "no longer exposes the public password-reset routes" do
  expect { new_password_path }.to raise_error(NoMethodError)
end
```

- [ ] **Step 2: Run red**

Run: `mise exec -- bundle exec rspec spec/requests/sessions_spec.rb -e "password-reset routes"`
Expected: FAIL.

- [ ] **Step 3: Delete + remove route**

```bash
git rm app/controllers/passwords_controller.rb
git rm -r app/views/passwords
git rm spec/requests/passwords_spec.rb # if present
```

Remove `resources :passwords, param: :token` from `config/routes.rb`. Grep `grep -rn "\bpasswords_path\|new_password_path\|edit_password_path" app/ spec/` → zero.

- [ ] **Step 4: Green + full suite + commit**

Run: `mise exec -- bundle exec rspec`
Expected: PASS.

```bash
git add -A
git commit -m "refactor(auth): remove public password-reset; magic-link is the only recovery"
```

---

### Task 8: Full-flow system specs + AAA + final suite

**Files:**
- Create/Update: `spec/system/passwordless_auth_spec.rb`
- Test: full suite + (push triggers CI AAA)

**Interfaces:** none new — this task proves the end-to-end behaviors from the spec's testing section.

- [ ] **Step 1: Write the system specs**

Create `spec/system/passwordless_auth_spec.rb` covering (match the existing `spec/system/magic_link_sign_in_spec.rb` style — extract the token via `MagicLinkToken.where(email:).order(:created_at).last` and `visit magic_link_callback_path(token:)`):

```ruby
require "rails_helper"

RSpec.describe "Passwordless-first auth", type: :system do
  it "signs up a brand-new user via magic link, no password anywhere" do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: "newbie@example.com"
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))

    token = MagicLinkToken.where(email: "newbie@example.com").order(:created_at).last
    visit magic_link_callback_path(token: token.token)
    fill_in I18n.t("magic_link_callbacks.new_registration.first_name_label"), with: "New"
    fill_in I18n.t("magic_link_callbacks.new_registration.last_name_label"), with: "Bie"
    click_button I18n.t("magic_link_callbacks.new_registration.submit")

    expect(User.find_by(email_address: "newbie@example.com")).to be_present
    expect(User.find_by(email_address: "newbie@example.com").has_password?).to be(false)
  end

  it "lets a password user fall back to their password via the secondary link" do
    user = create(:user) # has password
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.use_password"))
    # follow the secondary link → password form → sign in
    click_link I18n.t("sessions.check_email.use_password")
    fill_in I18n.t("sessions.password_form.password_label"), with: "password123456" # match factory password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_current_path(root_path)
  end

  it "forgot-password emails a link that lands on the change-password form" do
    user = create(:user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    click_link I18n.t("sessions.check_email.use_password")
    click_button I18n.t("sessions.new.forgot_password")
    token = MagicLinkToken.where(email: user.email_address, intent: "set_password").order(:created_at).last
    visit magic_link_callback_path(token: token.token)
    expect(page).to have_current_path(edit_settings_password_path)
  end
end
```

> Use the factory's actual password value; read `spec/factories/users.rb`. If the project's system specs sign in differently, mirror that. Behaviors are the contract.

- [ ] **Step 2: Run the system specs**

Run: `mise exec -- bundle exec rspec spec/system/passwordless_auth_spec.rb`
Expected: PASS. Debug via `log/test.log` if a flow stalls (Turbo swallows 4xx/5xx).

- [ ] **Step 3: Full suite**

Run: `mise exec -- bundle exec rspec`
Expected: 0 failures. Investigate any pending.

- [ ] **Step 4: Commit**

```bash
git add spec/system/passwordless_auth_spec.rb
git commit -m "test(auth): end-to-end passwordless-first system specs"
```

- [ ] **Step 5: Branch verification (UI + AAA)**

Verify the touched screens (`sessions/new`, `check_email`, `password_form`, `sessions/closed`, `settings/passwords/new` + `edit`) render correctly in **both light and dark** themes via the implementation-verifier (bundled Playwright). AAA contrast is proven by CI on push — do not claim AAA from a local run. Then hand off via `superpowers:finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:**
- Single email-first entry → Task 4 (+ Task 6 removes the separate signup). ✓
- Magic-link default, password secondary → Task 4. ✓
- Signup = magic-link; remove RegistrationsController → Task 6. ✓
- Password add/remove (and change, needed for forgot landing) → Task 2. ✓
- Forgot-password backed by magic-link → Task 3. ✓
- Remove public reset flow → Task 7. ✓
- Move `signups_open?` gate → Task 4 (lookup) + callback already guards (Task 6 fixes its redirect). ✓
- Pending invitation claim (already works) → regression guard Task 5; open-link-join claim (the real gap) → Task 5. ✓
- Auto-verification preserved → unchanged (magic-link/OAuth set `verified_at`); no task needed. ✓
- Return-intent (server-side enum) → Task 1 + Task 3. ✓
- Tests (10 behaviors) → Tasks 2–8. ✓

**Placeholder scan:** Two steps intentionally instruct the implementer to *match existing conventions they must read* (sign-in request helper in Task 2; factory/open-join setup in Task 5/8). These are not placeholders — the behavioral assertion is concrete; only the project-specific test scaffolding must be matched. All code steps show real code.

**Type/name consistency:** `create_for_email(email, intent:)` (Task 1) used consistently in Tasks 3/4/5/8. `magic_link_return_path` (Task 3) is the only new private method. `accept_pending_join_link!` (Task 5) mirrors existing `accept_pending_invitation!`. Routes: `password_reset_path`, `edit_settings_password_path`, `settings_password_path` used consistently.

**Open risk flagged for the implementer:** the check_email "use password instead" link needs a GET entry to `password_form` (Task 4, Step 4 note) — decide GET route vs re-POST and keep `password_form` reachable without issuing a magic link.
