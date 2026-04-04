# Secure Email Change with Re-verification — Design Spec

## Problem

The profile update action directly overwrites `email_address` with no verification of the new address, no password confirmation, no notification to the old address, and leaves the `Authentication` record's `uid` stale. An attacker with session access can silently hijack an account by changing the email to one they control.

## Solution

Require current password to initiate an email change. Store the new email as `pending_email` on the User model. Send a verification link to the new address and a notification to the old address. Only update `email_address` and `Authentication.uid` after the user clicks the verification link. Passwordless users must set a password before changing their email.

## Design Decisions

### Why require password for email changes?

Email is the account recovery channel. If an attacker can change it with just a session cookie (stolen via XSS, shared computer, or browser extension), they own the account permanently. Requiring the current password makes email changes a two-factor operation: something you have (session) + something you know (password). This is what GitHub, Google, and Stripe do.

### Why a pending_email column instead of a separate table?

A user can only have one pending email change at a time. Three nullable columns on the User model (`pending_email`, `pending_email_token`, `pending_email_sent_at`) are simpler than a separate table with a belongs_to. If a user initiates a second change before confirming the first, the new request overwrites the old one — correct behavior.

### Why notify the old email?

If an attacker initiates a change (even without completing it), the legitimate user should know. The notification to the old address says "someone requested an email change on your account" with instructions to change their password if it wasn't them.

### Why block passwordless users?

OAuth-only users have no password to confirm. The secure alternative (requiring fresh OAuth re-authentication) is significantly more complex. For now, passwordless users see their email as read-only with a message to set a password first. The existing account password flow (`/account/password/new`) already supports this.

## Architecture

### User Model Changes

Add three columns via migration:

```ruby
add_column :users, :pending_email, :string
add_column :users, :pending_email_token, :string
add_column :users, :pending_email_sent_at, :datetime
add_index :users, :pending_email_token, unique: true
```

New methods:

```ruby
def initiate_email_change!(new_email, password)
  # Returns false if password wrong, email invalid, or email taken
  # Sets pending_email, generates token, sets sent_at
  # Does NOT change email_address
end

def confirm_email_change!(token)
  # Validates token matches and not expired (24 hours)
  # Updates email_address
  # Updates the email-provider Authentication.uid (not OAuth authentications)
  # Clears pending fields
  # Returns true/false
end

def cancel_email_change!
  # Clears pending_email, pending_email_token, pending_email_sent_at
end

def pending_email_token_valid?
  # Token present and sent_at within 24 hours
end
```

Validations:

```ruby
validates :pending_email, format: { with: EMAIL_FORMAT }, allow_blank: true
validate :pending_email_not_taken, if: -> { pending_email.present? }
```

Normalization:

```ruby
normalizes :pending_email, with: ->(e) { e.strip.downcase }
```

### ProfilesController Changes

The update action splits into two paths:

1. **Email change requested** (email_address in params differs from current): require `current_password`, call `initiate_email_change!`, send mailers, flash "verification sent"
2. **No email change** (email_address absent or same): update name fields directly, no password needed

Strong params add `current_password` to permitted list (consumed by controller, not saved to model).

### New Controller: `Account::EmailConfirmationsController`

```ruby
class Account::EmailConfirmationsController < ApplicationController
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
```

Routes:

```ruby
namespace :account do
  resource :email_confirmation, only: [:show, :destroy]
end
```

The show route uses a token param: `GET /account/email_confirmation?token=abc123`

### Mailer Changes

Add to `AuthenticationMailer`:

```ruby
def email_change_verification(user)
  # Sent to user.pending_email
  # Contains link: account_email_confirmation_url(token: user.pending_email_token)
  # Expires in 24 hours
end

def email_change_notification(user)
  # Sent to user.email_address (current/old email)
  # Warning: "Someone requested an email change on your account"
  # Advice: "If this wasn't you, change your password immediately"
end
```

### Profile Form Changes

The edit profile form adds:

- `current_password` field below email (always visible — simplest approach)
- Help text: "Required when changing your email address"
- If `pending_email` is present, show an info notice: "Verification email sent to [pending_email]. Check your inbox." with a cancel link
- If user is passwordless (`!user.has_password?`), show email field as read-only with text: "Set a password to change your email address" and a link to `/account/password/new`

### Token Security

- Generated with `SecureRandom.urlsafe_base64(32)` (same as magic link tokens)
- Stored hashed? No — the token is short-lived (24 hours) and single-use. Hashing adds complexity without meaningful security benefit for this expiry window. (Magic link tokens use the same approach.)
- Unique index prevents collisions
- Cleared after use or expiry

## I18n Keys

Add to `config/locales/en/account.en.yml`:

```yaml
en:
  account:
    profiles:
      update:
        verification_sent: "Verification email sent to %{email}. Check your inbox."
        wrong_password: "Current password is incorrect"
        email_unchanged: "That's already your email address"
    email_confirmations:
      show:
        success: "Email address updated successfully"
        invalid_or_expired: "This verification link is invalid or has expired"
      destroy:
        cancelled: "Email change cancelled"
```

## Files Changed

| File | Action | Purpose |
| ---- | ------ | ------- |
| `db/migrate/*_add_pending_email_to_users.rb` | Create | Add pending_email columns |
| `app/models/user.rb` | Modify | Add pending email methods, validations, normalization |
| `app/controllers/account/profiles_controller.rb` | Modify | Split update for email vs non-email changes |
| `app/controllers/account/email_confirmations_controller.rb` | Create | Token verification and cancellation |
| `config/routes.rb` | Modify | Add email_confirmation resource |
| `app/views/account/profiles/edit.html.erb` | Modify | Add current_password field, pending notice |
| `app/mailers/authentication_mailer.rb` | Modify | Add email_change_verification and notification |
| `app/views/authentication_mailer/email_change_verification.html.erb` | Create | Verification email template |
| `app/views/authentication_mailer/email_change_verification.text.erb` | Create | Plain text version |
| `app/views/authentication_mailer/email_change_notification.html.erb` | Create | Notification email template |
| `app/views/authentication_mailer/email_change_notification.text.erb` | Create | Plain text version |
| `config/locales/en/account.en.yml` | Modify | Add I18n keys |
| `spec/models/user_spec.rb` | Modify | Pending email method specs |
| `spec/requests/account/profiles_spec.rb` | Modify | Email change request specs |
| `spec/requests/account/email_confirmations_spec.rb` | Create | Token confirmation specs |
| `spec/mailers/authentication_mailer_spec.rb` | Modify | Email change mailer specs |
| `spec/system/email_change_spec.rb` | Create | End-to-end system specs |

## Testing Strategy

**Model specs (User):**

- `initiate_email_change!` with correct password sets pending_email, token, sent_at
- `initiate_email_change!` with wrong password returns false, sets no pending fields
- `initiate_email_change!` with invalid email format returns false
- `initiate_email_change!` with already-taken email returns false
- `initiate_email_change!` with same-as-current email returns false
- `initiate_email_change!` overwrites previous pending change
- `initiate_email_change!` for passwordless user returns false
- `confirm_email_change!` with valid token updates email_address
- `confirm_email_change!` with valid token updates email Authentication.uid (not OAuth)
- `confirm_email_change!` with valid token clears pending fields
- `confirm_email_change!` with expired token (> 24 hours) returns false
- `confirm_email_change!` with wrong token returns false
- `confirm_email_change!` with nil token returns false
- `cancel_email_change!` clears all pending fields
- `pending_email_token_valid?` returns true for fresh token
- `pending_email_token_valid?` returns false for expired token
- `pending_email_token_valid?` returns false when no token
- `pending_email` validation rejects invalid format
- `pending_email` normalization strips and downcases

**Request specs (ProfilesController):**

- PATCH with new email + correct password → sets pending, sends verification, redirects with notice
- PATCH with new email + wrong password → rejects, re-renders form with error
- PATCH with new email + missing password → rejects
- PATCH without email change → updates name without password, no pending set
- PATCH with same email → no change initiated, name updates normally
- Passwordless user → email field ignored, name updates normally

**Request specs (EmailConfirmationsController):**

- GET with valid token → updates email, clears pending, redirects with notice
- GET with expired token → rejects, redirects with alert
- GET with invalid token → rejects, redirects with alert
- GET with no token → rejects
- DELETE → clears pending, redirects with notice

**Mailer specs:**

- `email_change_verification` sent to pending_email with correct token URL
- `email_change_notification` sent to current email_address with warning text

**System specs:**

- End-to-end: enter new email + password → receive verification email → click link → email updated
- Wrong password: shows inline error, email not changed
- Pending notice: shows "verification sent" on profile page after initiation
- Cancel: clicking cancel clears pending state
- Expired token: shows error flash after 24 hours

## Out of Scope

- OAuth re-authentication for passwordless users (future — complex)
- Rate limiting on email change attempts (inherits existing profile update rate limiting)
- Admin-initiated email changes
- Email change history/audit log
