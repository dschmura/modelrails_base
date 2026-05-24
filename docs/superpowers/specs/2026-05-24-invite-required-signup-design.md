# Invite-Required Signup — Design Spec

**Goal:** Gate new-user signup behind an invitation requirement, configurable per-deployment via env var (default: invite-only). The gate consults a single policy object from three callers — `RegistrationsController#new`, `RegistrationsController#create`, and the new-user branch of `OmniauthCallbacksController#create` — without adding routes or controllers. Existing users remain able to sign in via any verified method; only *creation of new accounts* is gated. The OAuth credentials file is migrated from a flat `google:`/`github:` structure to a namespaced `oauth:` parent at the same time, since both the OmniAuth initializer and the OAuth helper consult these credentials and a half-migrated state would be confusing.

**Scope:** One new POPO (`SignupPolicy` at `app/lib/`), state-based rendering in two existing `RegistrationsController` actions, a new sibling view (`closed.html.erb`), a guard in the OAuth callbacks controller, two env vars and a boot-time validation initializer, an `Invitation#acceptable?` method, a `signups_open?` view helper, credentials migration plus updates to two existing files that read credentials, locale keys for the closed page, and one unit + request-spec additions + one system spec.

---

## Motivation

Today, [app/controllers/registrations_controller.rb](app/controllers/registrations_controller.rb) accepts any registration request — the existing invitation system is an *onboarding convenience* (an invited user lands on the registration page with their workspace pre-selected), not a *gate*. There is no `before_action` enforcing invitation possession, and `OmniauthCallbacksController` in its new-user branch ([app/controllers/omniauth_callbacks_controller.rb](app/controllers/omniauth_callbacks_controller.rb)) creates accounts without consulting the invitation table at all.

For a template like `modelrails_base`, the invite-only deployment posture is more useful than fully-open signup: downstream apps that want open signup can opt-in with one env var; downstream apps that want closed signup get it as the safe default.

This spec also resolves a developer-experience gap. The OAuth buttons rendered by [app/views/shared/_oauth_buttons.html.erb](app/views/shared/_oauth_buttons.html.erb) are conditionally hidden by `oauth_enabled?` in [app/helpers/oauth_helper.rb](app/helpers/oauth_helper.rb), which checks for `Rails.application.credentials.dig(:google, :client_id).present?`. Without configured credentials, the buttons silently disappear — the current dev environment hits this case. Documented setup steps (Google + GitHub OAuth apps, per-environment credentials) ship with this work so manual OAuth testing is possible.

## Non-Goals

- **Database-backed signup_mode toggle.** Env vars are sufficient for a template; adding an `AppSetting` model + admin controller + policy + view + tests would be ~10× the code for a setting most deployments flip once and forget. Captured as a deferred follow-up.
- **"Request access" form / waitlist.** The friendly deny page tells uninvited visitors to ask their administrator. No `AccessRequest` model, no admin queue, no notification emails. Add later only if real demand surfaces — easier to add than to remove. (Jason Fried / DHH principle: build half a product, not a half-assed product.)
- **Admin UI for managing pending invitations.** Out of scope; existing invitation send/accept flow stays as-is.
- **Existing-user lockout when invite-only is enabled.** This spec gates *new-account creation* only. A user who already has an account in the system can always sign in via email/password or any verified OAuth provider, regardless of `SIGNUP_MODE`. A dedicated regression spec pins this.
- **`OauthCredentials` POPO refactor.** Identified during design but deferred — the initializer and helper both `dig(:oauth, :google/:github, ...)` after this work, which is duplication worth DRY-ing the next time we touch OAuth. Captured as a follow-up.

---

## Design decisions (locked during brainstorming)

| Decision | Choice | Reasoning |
| -------- | ------ | --------- |
| Gate scope | App-level (signup creation), with workspace-level already enforced structurally by absence of self-join | Existing code has no "join workspace X" path — invitation is the only way in. Adding an app-level gate completes the picture. |
| Personal workspace on invited signup | Config-driven via `CREATE_PERSONAL_WORKSPACE` env var | Some B2B deployments want users to only belong to inviting workspace; others want personal scratchpads. Template should support both. |
| Rejected/uninvited UX | Friendly deny page, no request-access form | Jason Fried / DHH principle: build only what you'll process. Upgrade path to a form exists if demand emerges. |
| Config mechanism | Env var + initializer with boot-time validation | 12-factor, simple, fails fast on typos. No new schema. |
| Default for `SIGNUP_MODE` | `invite_only` | Safe default: a forgotten flag should not accidentally open public signups. |
| Default for `CREATE_PERSONAL_WORKSPACE` | `true` | Matches dominant SaaS template pattern (Jumpstart Pro, etc.). |
| Gate enforcement architecture | POPO at `app/lib/signup_policy.rb` (class-method API) | Matches the existing `app/lib/` POPO pattern in the codebase (`EmailRecipientThrottle`, `OmniauthAdapters`). One rule, three callers, one unit test file. |
| Routing | Reuse `GET /registrations/new` and `POST /registrations`; render `closed.html.erb` based on policy state | RESTful per project rules — no custom actions, no new routes. The "new registration" resource has one state-dependent representation. |
| OAuth dev setup | Real Google + GitHub OAuth apps, per-environment credentials | OmniAuth `developer` strategy can't exercise `oauth_email_verified?` paths; real apps catch real bugs. |
| Credentials structure | Namespaced under `oauth:` (e.g., `oauth.google.client_id`) | Avoids collision with future top-level `google:` (Maps/GCS) or `github:` (Actions) credentials. |

---

## Architecture

### Policy and callers

```text
                      ┌──────────────────────────────────┐
                      │      SignupPolicy.open?          │
                      │  (Rails.configuration.x.signup,  │
                      │   session[:pending_invitation_…])│
                      └─────────────┬────────────────────┘
                                    │
            ┌───────────────────────┼──────────────────────────┐
            ▼                       ▼                          ▼
  RegistrationsController   RegistrationsController   OmniauthCallbacksController
        #new                       #create                    #create
  (render :new or          (proceed with create or    (proceed with new-user
   render :closed)          render :closed, 403)       creation, or 303 to
                                                       new_registration_path)
                                                              │
                                                              ▼
                                              gate also consulted in views:
                                              signups_open? helper hides
                                              landing-page "Sign up" CTA
```

### Decision logic

```text
SignupPolicy.open?(invitation_token:) returns true when ANY of:

  1. Rails.configuration.x.signup.mode == :open
     (deployment is fully-open signup)

  2. invitation_token is a non-blank string AND
     Invitation.find_by(token:) is non-nil AND
     that Invitation#acceptable? returns true
     (visitor possesses a valid, unexpired, unconsumed invitation)

Returns false otherwise → closed page rendered.
```

### Token possession semantics

The session-stashed `pending_invitation_token` is set today by [app/controllers/invitation_accepts_controller.rb](app/controllers/invitation_accepts_controller.rb) when an anonymous visitor clicks a workspace invitation link. That flow is unchanged. The new policy treats *possession of a valid token* as sufficient gate bypass — same rule applied at registration time, no duplication of acceptance logic. The full transactional acceptance (`Invitation#accept!`) still runs in `RegistrationsController#create` after user creation, so a token that expires *between* page load and form submit fails at acceptance with the existing error path, not at the gate.

---

## Implementation

### `SignupPolicy` (new — `app/lib/signup_policy.rb`)

```ruby
class SignupPolicy
  def self.open?(invitation_token: nil)
    globally_open? || invitation_valid?(invitation_token)
  end

  def self.globally_open?
    Rails.configuration.x.signup.mode == :open
  end

  def self.invitation_valid?(token)
    return false if token.blank?

    Invitation.find_by(token: token)&.acceptable? || false
  end
end
```

Class-method API (no instance state). Pure function of `(Rails.configuration, token, Invitation table)`. Three callers, no per-call state worth instantiating; refactor to an instance later if per-request fields (rate-limiting, A/B) need to be threaded in.

### `Invitation#acceptable?` (new method on existing model)

Wraps existing expiry + consumption checks so the policy doesn't duplicate them. The exact internals match whatever the existing `Invitation#accept!` transaction checks for; concretely:

```ruby
# app/models/invitation.rb
def acceptable?
  !expired? && accepted_at.nil? && declined_at.nil?
end
```

If `expired?`, `accepted_at`, `declined_at` aren't the exact existing column names, the planner will reconcile during implementation. The semantic is: "this invitation is in a state where `accept!` would succeed."

### `RegistrationsController` (modify)

```ruby
def new
  if SignupPolicy.open?(invitation_token: session[:pending_invitation_token])
    @user = User.new
    # renders new.html.erb (default)
  else
    render :closed
  end
end

def create
  unless SignupPolicy.open?(invitation_token: session[:pending_invitation_token])
    render :closed, status: :forbidden
    return
  end

  # existing create logic — unchanged
end
```

State-based rendering on the standard 7 RESTful actions. No new routes, no new actions.

### `OmniauthCallbacksController` (modify — new-user branch only)

In the existing branch that handles "no current user, no existing auth identity match":

```ruby
unless SignupPolicy.open?(invitation_token: session[:pending_invitation_token])
  redirect_to new_registration_path,
              alert: t("registrations.closed.oauth_blocked"),
              status: :see_other
  return
end

# existing new-user OAuth creation logic — unchanged
```

The gate must NOT wrap the entire `#create` action — existing-identity sign-in and signed-in-user-linking branches stay reachable. Dedicated regression spec enforces this.

### `signups_open?` view helper (new — `app/helpers/signup_helper.rb`)

```ruby
module SignupHelper
  def signups_open?
    SignupPolicy.open?(invitation_token: session[:pending_invitation_token])
  end
end
```

Used in landing-page partial to hide the "Sign up" CTA when closed. The "Sign in" CTA stays visible at all times.

### `closed.html.erb` (new — `app/views/registrations/closed.html.erb`)

Sibling template to `new.html.erb`. Follows existing auth view structure (shared auth header, container-page wrapper, design-token classes).

```erb
<div class="container-page">
  <%= render "shared/auth_header" %>

  <h1 class="text-heading-1"><%= t("registrations.closed.title") %></h1>

  <p class="text-body mt-4">
    <%= safe_html(t("registrations.closed.body_html")) %>
  </p>

  <div class="mt-8">
    <%= link_to t("registrations.closed.sign_in_link"),
                new_session_path,
                class: "btn-primary" %>
  </div>
</div>
```

`safe_html` per project convention (not `raw`) to satisfy herb-lint.

### i18n keys (new — `config/locales/en.yml`)

```yaml
en:
  registrations:
    closed:
      title: "Sign-ups are by invitation only"
      body_html: |
        If your team uses ModelRails, ask your workspace administrator
        to send you an invitation. Already have an invitation email?
        Click the link in that message to get started.
      sign_in_link: "Sign in to an existing account"
      oauth_blocked: "Sign-ups are by invitation only. Please ask your workspace administrator for an invitation."
```

### Configuration (new — `config/application.rb` + initializer)

In `config/application.rb` (inside the application class body):

```ruby
config.x.signup.mode = ENV.fetch("SIGNUP_MODE", "invite_only").to_sym
config.x.signup.create_personal_workspace = ENV.fetch("CREATE_PERSONAL_WORKSPACE", "true") == "true"
```

In `config/initializers/signup.rb` (new file):

```ruby
valid_modes = %i[open invite_only]
unless valid_modes.include?(Rails.configuration.x.signup.mode)
  raise "Invalid SIGNUP_MODE: #{Rails.configuration.x.signup.mode.inspect}. " \
        "Must be one of: #{valid_modes.join(', ')}"
end
```

Fail-fast at boot — typo'd `SIGNUP_MODE=opn` raises instead of silently defaulting to invite-only.

### `.env.example` additions

```bash
# === Signup gating ===

# Controls public signup behavior.
# - "invite_only" (default): /registrations/new is closed unless visitor has a valid invitation token in session
# - "open": anyone can sign up at /registrations/new
# SIGNUP_MODE=invite_only

# Whether new users get a personal workspace IN ADDITION to any invited workspace.
# - "true"  (default): every user gets a personal workspace, may also belong to others
# - "false": invited users only join the inviting workspace; open-mode signups still
#            get a personal workspace (toggle is ignored when user would otherwise
#            have no workspace)
# Only the literal strings "true" and "false" are recognized; other values are
# treated as "false".
# CREATE_PERSONAL_WORKSPACE=true
```

### OAuth credentials migration (modify — `omniauth.rb` and `oauth_helper.rb`)

**Credentials structure** (per-environment, e.g., `config/credentials/development.yml.enc`):

```yaml
oauth:
  google:
    client_id: 1234567890-abc.apps.googleusercontent.com
    client_secret: GOCSPX-...
  github:
    client_id: Iv1.abc123
    client_secret: ghp_...
```

**Initializer reads update** ([config/initializers/omniauth.rb](config/initializers/omniauth.rb)):

```ruby
google_id     = Rails.application.credentials.dig(:oauth, :google, :client_id)
google_secret = Rails.application.credentials.dig(:oauth, :google, :client_secret)
# ...
github_id     = Rails.application.credentials.dig(:oauth, :github, :client_id)
github_secret = Rails.application.credentials.dig(:oauth, :github, :client_secret)
```

**Helper reads update** ([app/helpers/oauth_helper.rb:11, 13](app/helpers/oauth_helper.rb#L11)):

```ruby
when :google_oauth2
  Rails.application.credentials.dig(:oauth, :google, :client_id).present?
when :github
  Rails.application.credentials.dig(:oauth, :github, :client_id).present?
```

### Personal workspace toggle integration

`Rails.configuration.x.signup.create_personal_workspace` is consulted only when a signing-up user **would otherwise have no workspace**. Behavior matrix:

| Signup path | `CREATE_PERSONAL_WORKSPACE=true` | `CREATE_PERSONAL_WORKSPACE=false` |
| ----------- | -------------------------------- | --------------------------------- |
| Open-mode signup (no invitation) | Personal workspace created | **Personal workspace created** (toggle ignored — would otherwise be a broken zero-workspace account) |
| Invitation-driven signup | Personal workspace **and** invited workspace membership | Only invited workspace membership |
| OAuth-driven new-user signup with no invitation (`:open` mode only — invite_only blocks this path entirely) | Personal workspace created | **Personal workspace created** (same reasoning as open-mode signup) |

In short: the toggle is a "do users get a personal workspace *in addition to* their invited workspaces?" flag. It is never allowed to leave a user with zero workspaces.

The exact integration point depends on where today's user-creation flow handles default workspace setup (`User#after_create` callback vs. controller-level service call vs. explicit method). The planner resolves this during implementation; the design contract is the matrix above.

---

## OAuth dev environment setup

Documented separately so it can be referenced by future contributors hitting "the OAuth buttons aren't showing in dev."

### Step 1 — Google OAuth client

1. Visit [console.cloud.google.com](https://console.cloud.google.com) → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID — type: **Web application**
3. Authorized redirect URI: `http://localhost:3000/auth/google_oauth2/callback`
4. Copy the client ID and client secret

### Step 2 — GitHub OAuth app

1. Visit `github.com/settings/developers` → OAuth Apps → New OAuth App
2. Homepage URL: `http://localhost:3000`
3. Authorization callback URL: `http://localhost:3000/auth/github/callback`
4. Generate and copy the client secret

### Step 3 — Store in per-environment credentials

```bash
bin/rails credentials:edit --environment=development
```

```yaml
oauth:
  google:
    client_id: ...
    client_secret: ...
  github:
    client_id: ...
    client_secret: ...
```

Add `config/credentials/development.key` to `.gitignore`. Share the dev key via team password manager, not git.

### Step 4 — Restart `bin/dev`

The initializer reads credentials at boot.

---

## Testing strategy

### `spec/lib/signup_policy_spec.rb` (new — pure unit)

```text
describe SignupPolicy do
  describe ".open?" do
    context "when SIGNUP_MODE is :open" do
      it "returns true with no token"
      it "returns true with any token (valid or not)"
    end

    context "when SIGNUP_MODE is :invite_only" do
      it "returns false with no token"
      it "returns false with a non-matching token string"
      it "returns false with an expired invitation token"
      it "returns false with an already-accepted invitation token"
      it "returns false with a declined invitation token"
      it "returns true with a valid, pending invitation token"
    end
  end
end
```

Runs in <50ms total. Stub `Rails.configuration.x.signup.mode` via `allow(Rails.configuration.x.signup).to receive(:mode).and_return(...)`. No request stack.

### `spec/requests/registrations_spec.rb` (additions to existing file)

- `GET /registrations/new` in `:invite_only` with no token → renders `:closed`, status 200
- `GET /registrations/new` in `:invite_only` with valid token in session → renders `:new`
- `GET /registrations/new` in `:open` → renders `:new` (regression)
- `POST /registrations` in `:invite_only` with no token → renders `:closed`, status **403**, no `User` created
- `POST /registrations` in `:invite_only` with valid token → creates user, consumes invitation, signs in

### `spec/requests/omniauth_callbacks_spec.rb` (additions to existing file)

- New-user OAuth callback in `:invite_only` with no token → 303 to `new_registration_path`, no `User` created, no `Authentication` created
- New-user OAuth callback in `:invite_only` with valid token in session → creates `User`, attaches OAuth `Authentication`, signs in
- **Existing-user OAuth callback (identity match) in `:invite_only` → signs in normally** ← critical regression spec
- **Signed-in-user OAuth linking in `:invite_only` → links normally** ← critical regression spec
- New-user OAuth callback in `:open` → creates user (regression)

### `spec/system/invite_only_signup_spec.rb` (new — end-to-end)

```text
scenario "invited user signs up successfully and uninvited visitor sees closed page" do
  # Admin sends invitation
  # (Switch session) Anonymous visitor clicks invitation acceptance link
  # Verify NOT redirected to closed page (token in session)
  # Fill registration form, submit
  # Verify signed in
  # Verify workspace membership created with invited role
  # Verify invitation marked accepted
  # Verify session[:pending_invitation_token] is cleared
  # Sign out
  # Visit /registrations/new directly (no token)
  # Verify closed page IS shown
  # axe-core AAA scan on closed page
end
```

### Edge cases pinned by explicit specs

1. **Existing user OAuth is NOT blocked when SIGNUP_MODE=invite_only.** Prevents future contributors from "simplifying" the gate into a broader `before_action` that locks out paying users.
2. **`session[:pending_invitation_token]` is cleared after successful acceptance.** A one-shot token should not linger; prevents a stale browser session being used to bypass the gate later.
3. **Tampered/non-matching token strings in session do not pass the gate.** `Invitation.find_by(token: "garbage")` returns `nil`, `&.acceptable?` short-circuits, policy returns `false`. Spec pins this behavior so a future "let's add a fallback" change can't silently weaken it.
4. **Initializer fails fast on invalid SIGNUP_MODE.** Boot-time validation prevents silent fallback to a wrong mode on typo.

---

## Out-of-scope follow-ups (captured for later)

- **`OauthCredentials` POPO refactor.** DRY the `Rails.application.credentials.dig(:oauth, ...)` lookups that will live in both `omniauth.rb` and `oauth_helper.rb`. Trigger: next OAuth schema change or new provider addition.
- **Database-backed signup_mode setting.** If a deployment needs to flip invite-only without redeploying, build an `AppSetting` model with admin UI. Trigger: real demand from a downstream template user.
- **"Request access" form.** Adds an `AccessRequest` model collecting email + optional message, admin queue, notification email. Trigger: real waitlist demand; manual emails asking for access.
- **Admin UI for managing pending/expired/sent invitations.** Bulk send, resend, revoke. Trigger: workspace admins reporting friction managing invites via the existing UI.
- **Bot/abuse protection on the closed page.** If the closed page becomes a high-traffic discovery point, add rate limiting on hits and minor cache headers.

---

## Acceptance checklist

- `Rails.application.credentials.dig(:oauth, :google, :client_id)` and `dig(:oauth, :github, :client_id)` are the canonical credential lookups across initializer and helper.
- `SignupPolicy.open?` returns the correct boolean for all (mode × token-state) combinations covered in the unit spec.
- `GET /registrations/new` renders `:new` when the gate allows, `:closed` when it denies — same URL, two states.
- `POST /registrations` returns 403 with `:closed` when gate denies; user count does not change.
- OAuth new-user creation is blocked when gate denies; OAuth existing-user sign-in is unaffected.
- `signups_open?` view helper correctly reflects the gate state for landing-page CTA conditional rendering.
- Initializer fails fast at boot on invalid `SIGNUP_MODE`.
- No signup path can leave a new user with zero workspaces, regardless of `CREATE_PERSONAL_WORKSPACE` value. Open-mode signups always receive a personal workspace; the toggle only suppresses personal-workspace creation when an invitation is providing one.
- System spec passes end-to-end including axe-core AAA scan on the closed page.
- All new strings pass through I18n; no hardcoded copy.
- All policy and request specs pass; no regression in existing `RegistrationsController` or `OmniauthCallbacksController` specs.
