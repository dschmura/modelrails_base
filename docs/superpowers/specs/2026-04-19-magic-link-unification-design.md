# Magic Link Unification — Design Spec

**Goal:** Eliminate the dual magic-link implementation (User columns + MagicLinkToken model) by routing ALL magic link flows through `MagicLinkToken`. Remove `magic_link_token` and `magic_link_sent_at` columns from `users`. Merge two callback controllers into one `MagicLinkCallbacksController`.

**Scope:** Migration (drop columns), controller consolidation, mailer signature update, model method removal, test updates. No UI changes — the user-facing email templates stay the same.

---

## Current State (two parallel implementations)

| Aspect | User columns (sign-in) | MagicLinkToken model (registration) |
|--------|----------------------|-------------------------------------|
| Storage | `users.magic_link_token` + `users.magic_link_sent_at` | `magic_link_tokens` table |
| Audit | Token erased on use (no trail) | `consumed_at` timestamp retained |
| Expiry | Computed: `sent_at > 15.min.ago` | Hard: `expires_at` column |
| Multi-token | No (overwritten) | Yes (multiple rows per email) |
| Callback | `MagicLinkSessionsController` | `MagicLinkRegistrationsController` |

## After: one implementation

Everything flows through `MagicLinkToken`:

1. **Token creation:** `MagicLinkToken.create_for_email(email)` — same for sign-in and registration
2. **Email sending:** `MagicLinkMailer.sign_in_link(email, token)` or `.registration_link(email, token)` — two methods, both take `(email, token)` now
3. **Callback:** ONE route (`GET /magic_link_callback/:token`) → `MagicLinkCallbacksController#show`
   - Token valid? → look up user by email
   - User exists? → consume token, start session, redirect (sign in)
   - User doesn't exist? → render registration form (name entry)
4. **Registration submit:** `POST /magic_link_callback/:token` → `MagicLinkCallbacksController#create`
   - Re-validate token, create user, consume token, start session

---

## New Controller: `MagicLinkCallbacksController`

Replaces BOTH `MagicLinkSessionsController` and `MagicLinkRegistrationsController`.

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
      first_name: params[:first_name],
      last_name: params[:last_name]
    )

    if @user.save
      @user.authentications.create!(
        provider: "email",
        uid: token_record.email,
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

One controller, two actions, clear runtime dispatch.

---

## Route Changes

Remove:
```ruby
get "magic_link_session/:token", to: "magic_link_sessions#show", as: :magic_link_session
get "magic_link_registration/:token", to: "magic_link_registrations#show", as: :magic_link_registration
post "magic_link_registration/:token", to: "magic_link_registrations#create"
```

Add:
```ruby
get "magic_link_callback/:token", to: "magic_link_callbacks#show", as: :magic_link_callback
post "magic_link_callback/:token", to: "magic_link_callbacks#create"
```

---

## Mailer Changes

### `MagicLinkMailer#sign_in_link`

Change from `sign_in_link(user)` (reads `user.magic_link_token`) to `sign_in_link(email, token)`:

```ruby
def sign_in_link(email, token)
  @url = magic_link_callback_url(token: token)
  mail(to: email, subject: t(".subject"))
end
```

### `MagicLinkMailer#registration_link`

Change from `registration_link(email, token)` with `magic_link_registration_url` to use the new callback URL:

```ruby
def registration_link(email, token)
  @url = magic_link_callback_url(token: token)
  mail(to: email, subject: t(".subject"))
end
```

Both methods now use the same URL pattern — `magic_link_callback_url(token:)`.

---

## Caller Changes

### `SessionsController#lookup`

Currently has two branches:
- User exists + no password → `user.generate_magic_link_token!` + `MagicLinkMailer.sign_in_link(user)`
- User not found → `MagicLinkToken.create_for_email(email)` + `MagicLinkMailer.registration_link(email, token)`

After: both branches use `MagicLinkToken.create_for_email`:

```ruby
# User exists, no password — magic link sign-in
token = MagicLinkToken.create_for_email(user.email_address)
MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later

# User not found — magic link registration
token = MagicLinkToken.create_for_email(email)
MagicLinkMailer.registration_link(email, token).deliver_later
```

### `MagicLinksController#create`

Currently: `user.generate_magic_link_token!` + `MagicLinkMailer.sign_in_link(user)`

After:
```ruby
token = MagicLinkToken.create_for_email(user.email_address)
MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
```

---

## User Model Cleanup

Remove these methods from `app/models/user.rb`:
- `generate_magic_link_token!`
- `magic_link_token_valid?`
- `clear_magic_link_token!`

---

## Migration

```ruby
class RemoveMagicLinkColumnsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :magic_link_token
    remove_column :users, :magic_link_token, :string
    remove_column :users, :magic_link_sent_at, :datetime
  end
end
```

---

## View Changes

The registration form currently at `app/views/magic_link_registrations/show.html.erb` moves to `app/views/magic_link_callbacks/new_registration.html.erb`. Same content, new path. The form's `action` changes from `POST magic_link_registration_path(token:)` to `POST magic_link_callback_path(token:)`.

---

## Files Deleted

- `app/controllers/magic_link_sessions_controller.rb`
- `app/controllers/magic_link_registrations_controller.rb`
- `app/views/magic_link_registrations/show.html.erb`
- `spec/requests/magic_link_sessions_spec.rb` (replaced by callbacks spec)
- `spec/requests/magic_link_registrations_spec.rb` (replaced by callbacks spec)
- `spec/models/user_magic_link_spec.rb` (methods deleted)

## Files Created

- `app/controllers/magic_link_callbacks_controller.rb`
- `app/views/magic_link_callbacks/new_registration.html.erb`
- `spec/requests/magic_link_callbacks_spec.rb`
- Migration: `TIMESTAMP_remove_magic_link_columns_from_users.rb`

## Files Modified

- `config/routes.rb` — swap routes
- `app/models/user.rb` — remove 3 methods
- `app/mailers/magic_link_mailer.rb` — update `sign_in_link` signature
- `app/views/magic_link_mailer/sign_in_link.html.erb` — use `@url` instead of reading from user
- `app/controllers/sessions_controller.rb` — update lookup branches
- `app/controllers/magic_links_controller.rb` — update to use MagicLinkToken
- `spec/mailers/magic_link_mailer_spec.rb` — update sign_in_link tests
- `spec/system/magic_link_sign_in_spec.rb` — update for new route
- `spec/system/magic_link_registration_spec.rb` — update for new route
- `config/locales/` — add `magic_link_callbacks.*` keys, remove old controller keys

---

## Testing Strategy

- **Request specs:** New `magic_link_callbacks_spec.rb` covering: valid token + existing user → sign in, valid token + new user → show registration form, registration form submit → create user, expired token → redirect, consumed token → redirect, invalid token → redirect
- **Mailer specs:** Update `sign_in_link` to use `(email, token)` signature
- **System specs:** Update existing sign-in and registration system specs for the new URL pattern
- **Model specs:** Delete `user_magic_link_spec.rb` (methods removed from User). Keep `magic_link_token_spec.rb` (unchanged).
- **Full suite after each task**

## What this does NOT change

- `MagicLinkToken` model — unchanged (it's the winner)
- `MagicLinksController` — stays as the entry point for requesting a magic link (POST /magic_link)
- `CheckGravatarJob` — unrelated
- Rate limiting on `MagicLinksController` — unchanged
