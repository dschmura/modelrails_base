# Verified OAuth Account Linking — Design Spec

**Goal:** Close the security gap where signed-in users can link OAuth providers (e.g., Google, GitHub) to their account without proving ownership of the OAuth-returned email. Add an email-confirmation flow for OAuth links where the provider's email differs from the user's primary email; auto-verify when emails match. Pending authentications cannot sign in. Users can resend the confirmation email or cancel the pending link. Communicate this through warm, action-oriented UX that reads as the system being careful, not as bureaucratic friction.

**Scope:** Schema add, model methods, OAuth callback flow refactor, two new controller actions, one new mailer method, one nullable column migration, view changes for pending state, route additions, locale keys, comprehensive request specs and one happy-path system spec. New-user OAuth signup flow is out of scope.

---

## Motivation

[app/controllers/omniauth_callbacks_controller.rb:14-22](app/controllers/omniauth_callbacks_controller.rb#L14-L22) currently creates a new authentication for a signed-in user with `verified_at: Time.current` immediately, regardless of whether the OAuth-returned email matches anything the user has proven they own. The threat:

- A user with primary email `alice@home.com` triggers OAuth via Google with `alice.work@example.com`
- The auth row is created verified instantly
- The user can now sign in via Google with an email they may not actually control

The vulnerability isn't theoretical: OAuth providers verify email-as-mailbox-ownership inconsistently. GitHub returns whatever's on the user's profile; Google verifies relatively well but stale data exists; smaller providers vary. Without our own confirmation step, we trust OAuth providers as the source of truth on mailbox ownership — and they don't all guarantee that.

The schema already has `verification_token`, `verification_sent_at`, and `verified_at` columns on `authentications` (verified at [db/schema.rb](db/schema.rb)) along with a unique index on `verification_token`. The infrastructure is half-built — the controller wiring is what's missing.

A panel of three security perspectives (DHH-pragmatic-Rails, Aaron-Patterson-adversarial, Chris-Oliver-production-experience) unanimously chose the strictest match policy: auto-verify only when OAuth email matches `user.email_address` (primary, registration-verified). Any other email — even one the user has previously verified via a *different* OAuth link — must be re-confirmed because OAuth verification is a snapshot, not ongoing ownership proof.

## Non-Goals

- **New-user OAuth signup verification.** When `Current.user` is nil and OAuth creates a new user, the OAuth email becomes that user's primary email by definition (Option-A-compliant trivially). Changing that flow's verification semantics is a separate threat-model question (do we trust OAuth providers as a source of identity for fresh users?).
- **Collision notification email** to legitimate owners when an attacker tries to link their OAuth identity. Tracked as a Scope C follow-up; this spec is Scope B.
- **Magic-link-style sign-in via verification tokens.** Tokens stay narrow: they verify, they don't authenticate. A signed-out user clicking a verification link consumes the token and is then redirected to sign-in with a success flash.
- **Real-time UI updates** (Turbo Stream broadcasts when verification completes from a different browser/tab). Reference app does this; we don't need it for v1. Page reload reveals the new state.
- **Migration of existing authentication records.** Authentications already on disk stay verified (grandfathered). Their `email` column stays null; UI handles that gracefully.

---

## Design decisions (locked during brainstorming)

| Decision | Choice | Reasoning |
| -------- | ------ | --------- |
| Scope | B: MVP + resend (no notification email) | Resend is the common recovery path; notification can follow as a separate spec. |
| Email-match policy | A: match `user.email_address` only | Unanimous panel: prior OAuth verification is a snapshot; primary email is the only stable trust anchor. |
| Pending sign-in | Blocked | Reference behavior; matches threat model. |
| Pending cancel | Allowed (divergence from reference) | Lets users back out without waiting 24h for token expiry. |
| Token expiry | 24 hours | Matches existing `AuthenticationMailer.verification_email` (registration). Magic-link is 15min — different threat. |
| Resend rate limit | 3 per 3 minutes | Matches existing `magic_links_controller#create` and `passwords_controller#create` rate limits. |
| Resend regenerates token | Yes | Old token immediately invalid; new token, new 24h window. |
| Sign-out + re-OAuth on pending provider | Refuse sign-in, auto-resend verification | Friendly recovery without making user navigate menus. |
| UI for pending in connected-accounts list | Inline status + actions per row | Single list, status varies per row, recovery actions adjacent. |
| Pending visual treatment | `bg-info-surface` + `text-info` (soft) | Pending isn't an error; matches the envelope-circle on `sessions/check_email`. |
| Token sign-in vector | Narrow-purpose only — no auto sign-in | Reduces blast radius if a verification email is intercepted. |
| Post-OAuth banner | One-time prominent banner with embedded Resend | Reduces friction for the common "didn't receive email" recovery. |

---

## Architecture

### Authentication state machine

Three logical states (the third is derived from the others; not a distinct column):

```text
                    ┌────────────────┐
        signup /    │   verified     │  ← steady state; today's behavior
        match ───→  │ verified_at:T  │     after this change too, just narrower
                    └─────┬──────────┘
                          │ (unchanged)
                          │
                          │
        OAuth link +     ┌▼────────────────────┐
        email differs ──→│  pending            │
                         │  verified_at: nil   │
                         │  verification_token │
                         │  sent_at: T         │
                         └─┬───────────────┬───┘
                           │               │
                  user clicks            user
                  email link            cancels (destroy)
                           │               │
                  ┌────────▼────────┐     │   24h elapsed
                  │ verify! → vrfd  │     ▼  ───────────→  pending + token_expired?
                  └─────────────────┘    DELETED            no resend yet ⇒ still pending
                                                            on resend ⇒ token regenerates
```

### Request flow (signed-in user, OAuth callback, email differs)

```text
1. POST /auth/google/callback
   → OmniauthCallbacksController#create
2. Branch: Current.user present, no existing auth for (provider, uid)
3. Compare auth_hash.info.email vs current_user.email_address
4. Differs → build authentication with:
       email: auth_hash.info.email
       verification_token: SecureRandom.urlsafe_base64(32)
       verification_sent_at: Time.current
       verified_at: nil
       oauth_token / oauth_refresh_token / oauth_expires_at: persisted
       (Tokens persist on pending rows so post-verification sign-in
       works without a re-OAuth roundtrip. Cleared by destroy.)
5. AuthenticationMailer.link_verification_email(auth).deliver_later
6. Redirect to account_connected_accounts_path
   Flash: "Almost there — we sent a confirmation link to <oauth-email>.
           Click it to finish linking your <Provider> account."
7. Connected accounts page renders pending row + dismissible banner.

8. (Async) User clicks email link
   → GET /account/connected_accounts/verify/:token
9. Find authentication by verification_token (unique index)
10. Check token_expired?
    → if expired, redirect to connected accounts with alert
       "This confirmation link expired. We can send you a new one."
11. authentication.verify!  (sets verified_at, clears token + sent_at)
12. If user signed in already → redirect to connected accounts, success flash
    If user signed out → redirect to new_session_path, success flash
       "<Provider> linked. Sign in to continue."
```

### Request flow (sign-out + re-OAuth on pending provider)

```text
1. User signs out, then taps "Sign in with Google" on /session/new
2. POST /auth/google/callback (Current.user nil)
3. Branch: existing authentication found by (provider, uid)
4. Authentication is pending (verified_at nil)
5. authentication.generate_verification_token!  (new token, fresh 24h)
6. AuthenticationMailer.link_verification_email(auth).deliver_later
7. Redirect to new_session_path with notice
   "We sent a fresh confirmation link to <auth.email>."
   (Refuse sign-in. User must click link.)
```

---

## Schema

One additive migration:

```ruby
class AddEmailToAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :authentications, :email, :string
  end
end
```

`email` is nullable. Existing authentications have null email; we don't backfill because the original OAuth email isn't recoverable, and these auths are already verified — the column isn't needed for them.

The existing unique compound indexes are preserved unchanged:

- `index_authentications_on_provider_and_uid` — prevents the same OAuth identity (e.g., a specific Google account) from being linked to two app users
- `index_authentications_on_user_id_and_provider` — prevents the same user from linking the same provider twice

These two indexes make Aaron Patterson's TOCTOU concern moot at the DB layer: any race between callback validation and create resolves to a `RecordNotUnique` exception, which our controller distinguishes by which constraint fired.

## Model — `Authentication`

Add a few small methods. Total new code: ~25 lines. No new dependencies.

```ruby
class Authentication < ApplicationRecord
  belongs_to :user

  scope :verified, -> { where.not(verified_at: nil) }
  scope :pending,  -> { where(verified_at: nil).where.not(verification_token: nil) }

  TOKEN_LIFETIME = 24.hours

  def pending?
    verified_at.nil? && verification_token.present?
  end

  def verified?
    verified_at.present?
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
end
```

Existing methods (`scope :email`, etc.) are unchanged.

## Controller — `OmniauthCallbacksController#create` rewrite

Refactor from one big `if/elsif/else` into named branches. Pseudocode:

```ruby
def create
  auth_hash = request.env["omniauth.auth"]
  resume_session
  existing = Authentication.find_by(provider: auth_hash.provider, uid: auth_hash.uid)

  if existing
    handle_existing_auth(existing, auth_hash)
  elsif Current.user
    handle_signed_in_link(Current.user, auth_hash)
  else
    handle_new_user_oauth(auth_hash)  # unchanged from today
  end
rescue ActiveRecord::RecordNotUnique
  # Defensive backstop for races between our pre-checks and create.
  # The pre-check covers the common cases with proper error messages;
  # this rescue is the safety net.
  redirect_to fallback_path, alert: t(".linking_failed")
end

private

def handle_existing_auth(auth, auth_hash)
  if auth.pending?
    # Refuse sign-in, regenerate token, resend verification, redirect.
    auth.generate_verification_token!
    AuthenticationMailer.link_verification_email(auth).deliver_later
    redirect_to new_session_path,
      notice: t(".pending_resent", email: auth.email)
  elsif Current.user.present? && Current.user.id != auth.user_id
    # Cross-user collision: someone else's verified OAuth identity. Block.
    redirect_to account_connected_accounts_path,
      alert: t(".collision_other_user", provider: auth_hash.provider.titleize)
  else
    auth.update!(oauth_attrs(auth_hash))
    start_new_session_for(auth.user)
    redirect_to root_path, notice: t("sessions.create.success")
  end
end

def handle_signed_in_link(user, auth_hash)
  # Cross-user duplicate-provider check: did Current.user already link this provider?
  # The DB unique index `(user_id, provider)` would catch this on save, but a
  # pre-check produces a clearer error message and avoids relying on parsing
  # exception text.
  if user.authentications.exists?(provider: auth_hash.provider)
    redirect_to account_connected_accounts_path,
      alert: t(".already_linked", provider: auth_hash.provider.titleize)
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
      notice: t(".linked", provider: auth_hash.provider.titleize)
  else
    auth.save!
    auth.generate_verification_token!
    AuthenticationMailer.link_verification_email(auth).deliver_later
    redirect_to account_connected_accounts_path,
      flash: { confirming_email_for: auth.id }  # triggers banner on next render
  end
end
```

(`fallback_path` = `new_session_path` if signed out, `account_connected_accounts_path` if signed in.)

## Controller — `Account::ConnectedAccountsController` additions

Two new actions plus a fix to `destroy`. No new sub-controllers (per project convention "no sub-resource controllers for single actions").

### `#verify` — token-based, allow_unauthenticated_access

```ruby
allow_unauthenticated_access only: :verify

def verify
  auth = Authentication.find_by(verification_token: params[:token])
  if auth.nil? || auth.token_expired?
    redirect_to fallback_path,
      alert: t(".invalid_or_expired")
    return
  end

  auth.verify!

  if Current.user.present?
    redirect_to account_connected_accounts_path,
      notice: t(".success", provider: auth.provider.titleize)
  else
    redirect_to new_session_path,
      notice: t(".success_signed_out", provider: auth.provider.titleize)
  end
end
```

`fallback_path` here is `new_session_path` if signed out, `account_connected_accounts_path` if signed in.

### `#resend_verification` — rate-limited, signed-in only

```ruby
rate_limit to: 3, within: 3.minutes, only: :resend_verification,
  with: -> {
    redirect_to account_connected_accounts_path,
      alert: t(".resend_rate_limited")
  }

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

### `#destroy` — counting-bug fix

Change the "last method" check from counting all auths to counting verified only. Pending auths can always be cancelled because they don't grant sign-in privileges:

```ruby
def destroy
  auth = Current.user.authentications.find(params[:id])

  if auth.verified? && Current.user.authentications.verified.count <= 1
    redirect_to account_connected_accounts_path,
      alert: t(".cannot_remove_last_verified")
  else
    auth.destroy!
    redirect_to account_connected_accounts_path,
      notice: t(".unlinked", provider: auth.provider.titleize)
  end
end
```

## Mailer — `AuthenticationMailer#link_verification_email`

Method signature: `link_verification_email(authentication)` — the auth has the token, sent timestamp, recipient email, and provider. Subject: `Confirm your <Provider> sign-in for <App>`. Templates HTML + text.

The HTML body has, in order:

1. Greeting using user's first name.
2. Single sentence explaining: "You added `{{provider}}` as a sign-in method for `{{app_name}}`. Confirm that `{{oauth_email}}` belongs to you to activate it."
3. Big primary button: "Yes, this was me — finish linking" → links to `verify_account_connected_accounts_url(token: auth.verification_token, host: …)`.
4. Subtle "What is this?" line: "We email you whenever a new sign-in method is added to your account. This protects your account from someone else linking it."
5. Footer: "If you didn't try to add this, ignore this email — your account stays untouched."

The text version mirrors this structure with the URL inline rather than a button.

Both versions name the provider, the email address, and the app explicitly. No corporate jargon. No marketing.

## Routes

Add to existing `namespace :account` block:

```ruby
namespace :account do
  resources :connected_accounts, only: [:index, :destroy] do
    member do
      post :resend_verification
    end
    collection do
      get "verify/:token", action: :verify, as: :verify
    end
  end
end
```

The collection-level `get "verify/:token"` produces the URL helper `verify_account_connected_accounts_path(token: …)`. This is intentionally a flat URL (no nested resource ID) because the token alone identifies the auth, and an unauthenticated user clicking the email link doesn't have the auth ID handy.

## Views

### `account/connected_accounts/index.html.erb`

For each authentication, conditional rendering:

- **Verified row** — unchanged from current. Provider icon, email, "Last used" timestamp, Unlink action.
- **Pending row** — soft `bg-info-surface` background, info icon, label "Confirming *<auth.email>*", small text "Check your email for a confirmation link." Two inline actions: "Resend confirmation" (POST `resend_verification_account_connected_account_path`), "Cancel link" (DELETE `account_connected_account_path`).

### Post-OAuth one-time banner

Triggered by `flash[:confirming_email_for]` (an auth ID set by the linking branch). On the connected-accounts page, when present, render a dismissible banner above the list:

> "Almost there — we sent a confirmation link to `alice.work@gmail.com` to make sure that's really you. Click the link to finish linking Google. Didn't receive it? **Resend**"

The "Resend" action posts to `resend_verification_account_connected_account_path(id: flash[:confirming_email_for])`. Banner uses the existing toast/dismissible-card pattern from `_toast_card.html.erb` to stay visually coherent.

### Verification email templates

`app/views/authentication_mailer/link_verification_email.html.erb` and `.text.erb`. Follow the structure described in the Mailer section.

## I18n keys

New keys under three namespaces:

- `omniauth_callbacks.create.linked` (existing — keep)
- `omniauth_callbacks.create.pending_resent`
- `omniauth_callbacks.create.collision_other_user`
- `omniauth_callbacks.create.already_linked`
- `account.connected_accounts.verify.success`
- `account.connected_accounts.verify.success_signed_out`
- `account.connected_accounts.verify.invalid_or_expired`
- `account.connected_accounts.resend_verification.resent`
- `account.connected_accounts.resend_verification.not_pending`
- `account.connected_accounts.resend_verification.resend_rate_limited`
- `account.connected_accounts.destroy.cannot_remove_last_verified` (replaces existing message)
- `account.connected_accounts.destroy.unlinked` (existing)
- `account.connected_accounts.index.confirming_banner` (the post-OAuth banner)
- `account.connected_accounts.index.pending_label`
- `account.connected_accounts.index.resend_action`
- `account.connected_accounts.index.cancel_action`
- `mailers.authentication_mailer.link_verification_email.subject`
- `mailers.authentication_mailer.link_verification_email.greeting`
- `mailers.authentication_mailer.link_verification_email.body`
- `mailers.authentication_mailer.link_verification_email.cta`
- `mailers.authentication_mailer.link_verification_email.what_is_this`
- `mailers.authentication_mailer.link_verification_email.footer`

All copy is the action-oriented language locked during brainstorming.

---

## Edge cases captured

| Case | Handling |
| ---- | -------- |
| OAuth provider returns no email | Treat as differs-from-primary → pending. UI says "Sent to (email unknown)". User can cancel and try again with a corrected provider config. |
| User changes primary email between callback and create | The DB unique index `(user_id, provider)` raises `RecordNotUnique` if the OAuth re-arrives in a race; otherwise the row gets the OAuth email captured at callback-time, which is what the user is confirming, not the primary. Independent. |
| Token leakage in logs | Add `:token` to `config.filter_parameters` in `config/initializers/filter_parameter_logging.rb`. |
| Token reuse after verification | Token is cleared in `verify!`. A second click on the same email link will hit the "invalid or expired" branch. |
| User initiates two pending links in parallel | Two pending rows allowed (different providers). Each has its own token. Independent. |
| Pending row exists, user signs out, attacker steals device, signs in as user | Existing session security applies; pending row alone doesn't grant new privileges. Verified-count protection on `destroy` prevents the attacker from removing the last verified method to lock the user out. |
| Pending email expired (24h+ no click) | Pending row remains in DB. UI shows "Expired — Resend" affordance. Resend regenerates the token + sent_at. |
| User cancels pending link | Row destroyed. Future OAuth attempt with the same provider+uid creates a fresh pending row. |
| Mailer delivery fails | `deliver_later` retries via Solid Queue. UI shows the pending row regardless; Resend is the user's recovery if they suspect non-delivery. |

## Tests

### Request specs

`spec/requests/omniauth_callbacks_spec.rb` adds:

- Signed-in user, OAuth email matches primary → auth created verified
- Signed-in user, OAuth email differs → pending auth + verification email enqueued
- Signed-in user, provider+uid collision with another user → redirect with `collision_other_user` alert
- Signed-in user, user_id+provider collision (already linked, repeat OAuth) → redirect with `already_linked` notice
- Signed-out user, existing auth pending → token regenerated, fresh email sent, refuse sign-in
- Signed-out user, existing auth verified → sign in (unchanged from today)

`spec/requests/account/connected_accounts_spec.rb` adds:

- `#verify` with valid token → auth verified, redirect with success
- `#verify` with expired token → redirect with `invalid_or_expired` alert
- `#verify` with already-consumed token → same alert
- `#verify` with unknown token → same alert
- `#verify` while signed out → success flash redirects to sign-in
- `#resend_verification` on pending auth → token regenerated, email sent
- `#resend_verification` on verified auth → `not_pending` alert
- `#resend_verification` rate limit (4 calls in 3 min) → 4th rate-limited
- `#destroy` on last verified auth → `cannot_remove_last_verified` alert
- `#destroy` on pending auth + only verified auth exists → row destroyed (pending doesn't count)
- `#destroy` on one of two verified auths → row destroyed

### Model specs

`spec/models/authentication_spec.rb` adds:

- `pending?` true when verified_at nil + token present, false otherwise
- `token_expired?` true after 24h, false within
- `generate_verification_token!` sets token + sent_at, clears verified_at
- `verify!` sets verified_at, clears token + sent_at
- `verified` and `pending` scopes return correct rows

### Mailer specs

`spec/mailers/authentication_mailer_spec.rb` adds:

- `link_verification_email` renders to the right recipient
- Subject names provider and app
- Body contains the verification URL with the token
- Both HTML and text parts present

### System spec (one)

`spec/system/oauth_link_verification_spec.rb`:

- Sign in as user with primary email `alice@home.com`
- Trigger Google OAuth (via OmniAuth test mode) returning `alice.work@gmail.com`
- Land on connected accounts; see pending row and post-OAuth banner
- Open letter_opener, click verification link
- Auth verified; banner gone; row shows as verified

## Files Touched

| Path | Action |
| ---- | ------ |
| `db/migrate/<ts>_add_email_to_authentications.rb` | Create |
| [app/models/authentication.rb](app/models/authentication.rb) | Modify (~25 new lines) |
| [app/controllers/omniauth_callbacks_controller.rb](app/controllers/omniauth_callbacks_controller.rb) | Refactor `#create` into named branches; new `handle_signed_in_link`, `handle_existing_auth`, `handle_collision` |
| `app/controllers/account/connected_accounts_controller.rb` | Add `#verify`, `#resend_verification`; fix `#destroy` last-method check |
| `app/mailers/authentication_mailer.rb` | Add `link_verification_email(authentication)` |
| `app/views/authentication_mailer/link_verification_email.html.erb` | Create |
| `app/views/authentication_mailer/link_verification_email.text.erb` | Create |
| `app/views/account/connected_accounts/index.html.erb` | Modify (pending row treatment + post-OAuth banner) |
| [config/routes.rb](config/routes.rb) | Add `:resend_verification` member + `verify/:token` collection routes |
| `config/locales/en/account.en.yml` | Add new keys (and replace one) |
| `config/locales/en/mailers.en.yml` | Add `authentication_mailer.link_verification_email.*` keys |
| `config/initializers/filter_parameter_logging.rb` | Add `:token` to filter list (if not already present) |
| `spec/...` | New + modified specs (see Tests section) |

Net: 4 new files + ~10 modified, ~400 lines.

## Rollout

- Migration is purely additive (nullable column). No data loss, no downtime.
- Existing OAuth links remain verified (grandfathered). Their `email` column stays nil — UI handles that case gracefully (no "Sent to ..." line for null email).
- Feature is not flag-gated. Deploy is the activation. The new code paths only fire on *new* OAuth-link attempts; existing auths and the email/password flows are unaffected.
- Reversible: revert the controller and view changes, drop the email column. Pending rows on disk become orphaned but harmless (still findable by token until 24h elapses; cleanup is a nice-to-have but not required).

## Open Questions

None. All scope, behavior, and copy decisions locked during brainstorming and the security panel.

## Follow-up — deferred work tracked for future specs

Two follow-ups, both deferred to keep this spec focused:

1. **Collision notification email (Scope C from brainstorming).** When a `provider+uid` collision is detected (someone else's OAuth attached to a third party's account is being attached to *another* user), email the legitimate owner: "Someone tried to link their Google account to a different ModelRails account. If that wasn't you, your account is unaffected — but here's what we noticed." Defense-in-depth, low scope (~50 lines). Trigger: ship after this spec lands and stabilizes.

2. **Per-recipient verification-email rate limit.** A signed-in attacker could spam an arbitrary inbox with verification emails by OAuth-linking with that email address (e.g., adding `victim@example.com` to their own GitHub profile). Current mitigations: per-user resend rate limit (3/3min), provider-level OAuth rate limits, "if you didn't try this, ignore" footer in the email. Future hardening: cap verification emails sent to the same recipient address (e.g., 5/hour across all attempters). Trigger: if abuse is observed, or as part of a broader "transactional email rate-limit" pass.
