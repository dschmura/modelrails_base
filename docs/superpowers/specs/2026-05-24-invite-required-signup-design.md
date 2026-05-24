# Invite-Required Signup — Design Spec

**Goal:** Gate new-user signup behind an invitation requirement, configurable per-deployment via env var (default: invite-only). The gate consults a single policy object from three callers — `RegistrationsController#new`, `RegistrationsController#create`, and the new-user branch of `OmniauthCallbacksController#create` — without adding routes or controllers. Existing users remain able to sign in via any verified method; only *creation of new accounts* is gated.

**Scope:** One new POPO (`SignupPolicy` at `app/lib/`), state-based rendering in two existing `RegistrationsController` actions, a new sibling view (`closed.html.erb`), a guard in the OAuth callbacks controller, one env var (`SIGNUP_MODE`) and a boot-time validation initializer, an `Invitation#acceptable?` method, a `signups_open?` helper method on `ApplicationController`, locale keys for the closed page, OAuth dev environment setup documentation, OAuth credentials migration from flat (`google:`/`github:`) to nested (`oauth: google:`/`oauth: github:`) namespace, and one unit + request-spec additions + one system spec.

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
- **Optional personal workspace ("B2B-only deployment mode").** Initially considered as a `CREATE_PERSONAL_WORKSPACE` env var alongside `SIGNUP_MODE`. Audit of the codebase showed that three call sites assume every user has a personal workspace ([PersonalWorkspaceContext](app/controllers/concerns/personal_workspace_context.rb), [SettingsNavigationHelper](app/helpers/settings_navigation_helper.rb), and the post-login redirect logic in [Authenticatable](app/controllers/concerns/authenticatable.rb)). Making personal workspaces truly optional is a separate, cohesive piece of work (the env var plus three call-site fixes plus accompanying specs) deserving its own spec. This spec assumes every signup — open or invited — creates a personal workspace, matching the codebase's existing invariant. Captured as a follow-up.
- **`OauthCredentials` POPO refactor.** Identified during design but deferred — the initializer and helper both read OAuth credentials directly. Worth DRY-ing the next time we touch OAuth. Captured as a follow-up.

---

## Design decisions (locked during brainstorming)

| Decision | Choice | Reasoning |
| -------- | ------ | --------- |
| Gate scope | App-level (signup creation), with workspace-level already enforced structurally by absence of self-join | Existing code has no "join workspace X" path — invitation is the only way in. Adding an app-level gate completes the picture. |
| Personal workspace on signup | Always created (open or invited path) | Initially planned as a toggle; audit revealed 3 call sites assume every user has a personal workspace. Making it optional is a separate cohesive piece of work deferred to its own spec. |
| Rejected/uninvited UX | Friendly deny page, no request-access form | Jason Fried / DHH principle: build only what you'll process. Upgrade path to a form exists if demand emerges. |
| Config mechanism | Env var + initializer with boot-time validation | 12-factor, simple, fails fast on typos. No new schema. |
| Default for `SIGNUP_MODE` | `invite_only` | Safe default: a forgotten flag should not accidentally open public signups. |
| Gate enforcement architecture | POPO at `app/lib/signup_policy.rb` (class-method API) | This case is simple enough that a class method is sufficient; refactor to an instance if per-request state ever needs threading. |
| Public policy method name | `SignupPolicy.allows_signup?(token:)` | Renamed from `open?` per panel review — "open" conflated "the gate is open" with "this signup is allowed." Reads naturally at call sites: `if SignupPolicy.allows_signup?(...)`. |
| `POST /registrations` gate-deny status | `422 Unprocessable Entity` | Per Turbo Form adapter conventions: 4xx replaces page content with response body. 422 is the idiomatic "I refuse to process this request"; 403 confuses Turbo's "validation error" treatment. |
| Routing | Reuse `GET /registrations/new` and `POST /registrations`; render `closed.html.erb` based on policy state | RESTful per project rules — no custom actions, no new routes. The "new registration" resource has one state-dependent representation. |
| Race-condition handling (two browsers, same token) | Wrap user creation + invitation acceptance in a single transaction; rollback on conflict | Tab A and Tab B both submitting same invitation token would otherwise produce a half-created User in Tab B without workspace membership. Transactional wrapping ensures both succeed or both fail. |
| OAuth dev setup | Real Google + GitHub OAuth apps; credentials namespaced under `oauth:` | OmniAuth `developer` strategy can't exercise `oauth_email_verified?` paths; real apps catch real bugs. Nested `oauth:` namespace avoids future collision with top-level `google:` (Maps/GCS) or `github:` (Actions) credentials. |

---

## Architecture

### Policy and callers

```text
                      ┌───────────────────────────────────────┐
                      │   SignupPolicy.allows_signup?(token:) │
                      │  (Rails.configuration.x.signup,       │
                      │   session[:pending_invitation_token]) │
                      └─────────────┬─────────────────────────┘
                                    │
            ┌───────────────────────┼──────────────────────────┐
            ▼                       ▼                          ▼
  RegistrationsController   RegistrationsController   OmniauthCallbacksController
        #new                       #create                    #create
  (render :new or          (proceed with create or    (proceed with new-user
   render :closed)          render :closed, 422)       creation, or 303 to
                                                       new_registration_path)
                                                              │
                                                              ▼
                                              gate also consulted in views:
                                              signups_open? helper hides
                                              landing-page "Sign up" CTA
```

### Decision logic

```text
SignupPolicy.allows_signup?(token:) returns true when ANY of:

  1. Rails.configuration.x.signup.mode == :open
     (deployment is fully-open signup)

  2. token is a non-blank string AND
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

Class-method API (no instance state). Pure function of `(Rails.configuration, token, Invitation table)`. Three callers, no per-call state worth instantiating; refactor to an instance later if per-request fields (rate-limiting, A/B) need to be threaded in.

### `Invitation#acceptable?` (new method on existing model)

Uses the existing `:status` enum as the source of truth for state and the existing `expired?` method (or `expires_at < Time.current` check, whichever exists) for time-based expiry:

```ruby
# app/models/invitation.rb
def acceptable?
  pending? && !expired?
end
```

This is intentionally simpler than initially proposed — the enum encodes the `accepted`/`declined`/`revoked` states already; re-checking timestamp columns would duplicate that information. The semantic is: "this invitation is in pending status and hasn't timed out." The exact `expired?` predicate name will be reconciled against the existing model during implementation.

### `RegistrationsController` (modify)

```ruby
def new
  if signups_open?
    @user = User.new
    # renders new.html.erb (default)
  else
    render :closed
  end
end

def create
  unless signups_open?
    render :closed, status: :unprocessable_entity
    return
  end

  # existing create logic — unchanged
  # BUT: user creation + invitation acceptance are wrapped in a single
  # transaction (see "Race-condition handling" below)
end
```

State-based rendering on the standard 7 RESTful actions. No new routes, no new actions. **Status 422 (not 403)** on POST denial, per Turbo Form adapter conventions — Turbo replaces the form's containing content with the response body cleanly on 4xx; 403 would confuse it.

### Race-condition handling (new — in `RegistrationsController#create`)

Two browsers submitting the same invitation token simultaneously would, without protection, produce one successful User (Tab A) and one half-created User in Tab B that has no inviting workspace membership. The fix: wrap user creation AND invitation acceptance in a single transaction so Tab B sees an honest "this invitation has already been used" error, not a silent half-success.

Pseudocode for the relevant region of `#create`:

```ruby
ApplicationRecord.transaction do
  @user.save!
  token = session.delete(:pending_invitation_token)
  invitation = token && Invitation.find_by(token: token)
  invitation&.accept!(@user)
rescue ActiveRecord::RecordInvalid => e
  # invitation was consumed between gate-check and accept!
  # roll back the user creation; show "invitation no longer valid" message
  raise ActiveRecord::Rollback
end
```

The exact placement (inside the controller, in a service object, or as a model concern) is the planner's call. The contract is: **user creation and invitation acceptance succeed or fail together — never partially.**

### `OmniauthCallbacksController` (modify — new-user branch only)

The OAuth callbacks controller has three branches. The gate must be placed only in the third branch:

```text
#create
├── Branch 1: Existing Authentication record found
│   └── Sign in existing user. NOT GATED.
│
├── Branch 2: Current.user present (linking new provider)
│   └── Attach new Authentication to existing user. NOT GATED.
│
└── Branch 3: New OAuth user (no current_user, no matching identity)
    ├── Check SignupPolicy.allows_signup?(token: session[:pending_invitation_token])
    │   └── if false → 303 to new_registration_path with alert flash; return
    └── existing new-user OAuth creation logic — unchanged
```

The check sits at the top of branch 3, before user creation:

```ruby
unless signups_open?
  redirect_to new_registration_path,
              alert: t("registrations.closed.oauth_blocked"),
              status: :see_other
  return
end

# existing new-user OAuth creation logic — unchanged
```

The gate must NOT wrap the entire `#create` action — existing-identity sign-in (branch 1) and signed-in-user-linking (branch 2) stay reachable. Dedicated regression specs enforce this for both branches.

### `signups_open?` helper (new — on `ApplicationController`, memoized)

Placed on the controller (not in a view helper module) so it can memoize per-request and stay accessible to views via `helper_method`:

```ruby
# app/controllers/application_controller.rb
helper_method :signups_open?

def signups_open?
  @signups_open ||= SignupPolicy.allows_signup?(
    token: session[:pending_invitation_token]
  )
end
```

Memoization matters: landing pages that call `signups_open?` from multiple partials would otherwise issue a `find_by` per call when an invitation token is in the session. One per-request memo avoids the multi-query hot path.

Used in:

- `RegistrationsController#new` and `#create` (gate decision)
- `OmniauthCallbacksController#create` (gate decision, branch 3 only)
- Landing-page partial(s) — hide "Sign up" CTA when false. The "Sign in" CTA stays visible at all times.

### `closed.html.erb` (new — `app/views/registrations/closed.html.erb`)

Sibling template to `new.html.erb`. Follows the existing auth view structure used in [app/views/sessions/new.html.erb](app/views/sessions/new.html.erb) and [app/views/registrations/new.html.erb](app/views/registrations/new.html.erb) — `max-w-md mx-auto px-4 py-16` layout, semantic text tokens, `.btn-primary` for the CTA.

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

Notes:

- All classes verified against the existing Tailwind config and the codebase's design-token CSS layer. No phantom classes.
- `safe_html` per project convention (not `raw`) to satisfy herb-lint.
- `mt-6` (24px) / `mt-12` (48px) spacing intentionally more generous than `mt-4`/`mt-8` per Steve Schoger's panel feedback — a deny page should feel intentional and unhurried, not cramped.
- Dark mode is inherited automatically via semantic tokens (`text-text-heading`, `text-text-body` adapt under `.dark`); no `dark:` prefixes needed.
- No `<h1>` collision concern — the shared layout uses landmarks (`<nav>`, `<main>`) without headings of its own.

### i18n keys (new — `config/locales/en.yml`)

The app name is interpolated through `t("app_name")` so downstream forks renaming the template don't need to override the closed-page strings — just the single `app_name` key.

```yaml
en:
  app_name: "ModelRails"   # downstream forks override this single key
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

If `app_name` already exists as an i18n key in the codebase, reuse it instead of defining a second one. The planner will reconcile.

### Configuration (new — `config/application.rb` + initializer)

In `config/application.rb` (inside the application class body):

```ruby
config.x.signup.mode = ENV.fetch("SIGNUP_MODE", "invite_only").to_sym
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
```

### Personal workspace creation (unchanged from today)

Every signup — open-mode, invitation-driven email/password, or OAuth — continues to create a personal workspace via the existing `User#after_create :create_personal_workspace` callback in [app/models/user.rb](app/models/user.rb). This spec does NOT change that behavior. Invitation-driven signups also get the invited workspace membership in addition to their personal workspace, which matches today's behavior.

The "no personal workspace for B2B-only deployments" use case is captured as a separate follow-up spec (see Out-of-scope follow-ups) — it requires changes to three call sites that today assume every user has a personal workspace, and bundling those changes here would conflate two features.

---

## OAuth dev environment setup

Documented separately so it can be referenced by future contributors hitting "the OAuth buttons aren't showing in dev." Credentials are namespaced under an `oauth:` parent key (avoids collision with future top-level `google:` or `github:` credentials for other services).

### Step 1 — Google OAuth client

1. Visit [console.cloud.google.com](https://console.cloud.google.com) → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID — type: **Web application**
3. Authorized redirect URI: `http://localhost:3000/auth/google_oauth2/callback`
4. **OAuth consent screen scopes:** verify `email` and `profile` are requested. Without `email`, the `oauth_email_verified?` check in `OmniauthCallbacksController` will misfire and verified-email auto-link will silently break.
5. Copy the client ID and client secret

### Step 2 — GitHub OAuth app

1. Visit `github.com/settings/developers` → OAuth Apps → New OAuth App
2. Homepage URL: `http://localhost:3000`
3. Authorization callback URL: `http://localhost:3000/auth/github/callback`
4. The OAuth flow requests `user:email` scope (already configured in [config/initializers/omniauth.rb](config/initializers/omniauth.rb)) — no extra GitHub-side scope config needed.
5. Generate and copy the client secret

### Step 3 — Store in credentials (per-environment recommended)

```bash
bin/rails credentials:edit --environment=development
```

```yaml
oauth:
  google:
    client_id: 1234567890-abc.apps.googleusercontent.com
    client_secret: GOCSPX-...
  github:
    client_id: Iv1.abc123
    client_secret: ghp_...
```

Add `config/credentials/development.key` to `.gitignore`. Share the dev key via team password manager, not git.

### Step 4 — Restart `bin/dev`

The initializer reads credentials at boot.

---

## Testing strategy

### `spec/lib/signup_policy_spec.rb` (new — pure unit)

```text
describe SignupPolicy do
  describe ".allows_signup?" do
    context "when SIGNUP_MODE is :open" do
      it "returns true with no token"
      it "returns true with any token (valid or not)"
    end

    context "when SIGNUP_MODE is :invite_only" do
      it "returns false with no token"
      it "returns false with a non-matching token string"
      it "returns false with an expired invitation token"      # build(:invitation, :expired)
      it "returns false with an already-accepted invitation"   # build(:invitation, :accepted)
      it "returns false with a declined invitation"            # build(:invitation, :declined)
      it "returns false with a revoked invitation"             # build(:invitation, :revoked)
      it "returns true with a valid, pending invitation token" # build(:invitation)
    end
  end
end
```

Uses existing factory traits (`:expired`, `:accepted`, `:declined`, `:revoked`) — confirmed by panel review. Runs in <50ms total. Stub `Rails.configuration.x.signup.mode` via `allow(Rails.configuration.x.signup).to receive(:mode).and_return(...)`. No request stack.

### `spec/requests/registrations_spec.rb` (additions to existing file)

- `GET /registrations/new` in `:invite_only` with no token → renders `:closed`, status 200
- `GET /registrations/new` in `:invite_only` with valid token in session → renders `:new`
- `GET /registrations/new` in `:open` → renders `:new` (regression)
- `POST /registrations` in `:invite_only` with no token → renders `:closed`, status **422 (Unprocessable Entity)**, no `User` created
- `POST /registrations` in `:invite_only` with valid token → creates user, consumes invitation, signs in
- **`POST /registrations` with valid token that gets consumed mid-flight (concurrent acceptance) → User creation is rolled back, error rendered** ← critical race-condition regression

### `spec/requests/omniauth_callbacks_spec.rb` (additions to existing file)

- New-user OAuth callback in `:invite_only` with no token → 303 to `new_registration_path`, no `User` created, no `Authentication` created
- New-user OAuth callback in `:invite_only` with valid token in session → creates `User`, attaches OAuth `Authentication`, signs in
- **Existing-user OAuth callback (identity match) in `:invite_only` → signs in normally** ← critical regression spec for Branch 1
- **Signed-in-user OAuth linking in `:invite_only` → links normally** ← critical regression spec for Branch 2
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
  # Verify closed page IS shown (heading text + sign-in link visible)
  # axe-core AAA scan on closed page (expect_axe_audit_to_pass)
end
```

### Edge cases pinned by explicit specs

1. **Existing user OAuth is NOT blocked when SIGNUP_MODE=invite_only.** Prevents future contributors from "simplifying" the gate into a broader `before_action` that locks out paying users.
2. **Signed-in user OAuth linking is NOT blocked when SIGNUP_MODE=invite_only.** Same reasoning for Branch 2.
3. **`session[:pending_invitation_token]` is cleared after acceptance attempt** — regardless of whether acceptance succeeds or fails. Prevents a stale browser session being used to bypass the gate later.
4. **Tampered/non-matching token strings in session do not pass the gate.** `Invitation.find_by(token: "garbage")` returns `nil`, `&.acceptable?` short-circuits, policy returns `false`. Spec pins this behavior so a future "let's add a fallback" change can't silently weaken it.
5. **Two-browser concurrent acceptance race produces no half-created Users.** When Tab A and Tab B both submit registration with the same token, only one User is created (transactional rollback). The losing tab sees a clear error message; the winning tab gets the workspace membership.
6. **Initializer fails fast on invalid SIGNUP_MODE.** Boot-time validation prevents silent fallback to a wrong mode on typo.
7. **Memoized `signups_open?` issues only one `Invitation.find_by` per request** — even when called from multiple partials. Pin via a query-counting matcher or RSpec-mocks assertion.

---

## Out-of-scope follow-ups (captured for later)

- **B2B-only deployment mode (`CREATE_PERSONAL_WORKSPACE=false`).** Adds an env var to suppress personal-workspace creation for invited users, plus three call-site fixes: (1) [PersonalWorkspaceContext](app/controllers/concerns/personal_workspace_context.rb) needs a fallback when `Current.user.personal_workspace` is nil; (2) [SettingsNavigationHelper](app/helpers/settings_navigation_helper.rb) needs context inference that doesn't default to `:personal` when `Current.workspace` is nil; (3) post-login redirect in [Authenticatable](app/controllers/concerns/authenticatable.rb) needs to route invited-only users to their first workspace instead of `root_url`. Open-mode signups always get a personal workspace (otherwise zero-workspace state). Trigger: a real B2B-only deployment of the template.
- **`OauthCredentials` POPO refactor.** DRY the `Rails.application.credentials.dig(:oauth, ...)` lookups that will live in both `omniauth.rb` and `oauth_helper.rb`. Trigger: next OAuth schema change or new provider addition.
- **Database-backed signup_mode setting.** If a deployment needs to flip invite-only without redeploying, build an `AppSetting` model with admin UI. Trigger: real demand from a downstream template user.
- **"Request access" form.** Adds an `AccessRequest` model collecting email + optional message, admin queue, notification email. Trigger: real waitlist demand; manual emails asking for access.
- **Admin UI for managing pending/expired/sent invitations.** Bulk send, resend, revoke. Trigger: workspace admins reporting friction managing invites via the existing UI.
- **Bot/abuse protection on the closed page.** If the closed page becomes a high-traffic discovery point, add rate limiting on hits and minor cache headers.

---

## Acceptance checklist

- `SignupPolicy.allows_signup?(token:)` returns the correct boolean for all (mode × token-state) combinations covered in the unit spec.
- `GET /registrations/new` renders `:new` when the gate allows, `:closed` when it denies — same URL, two states.
- `POST /registrations` returns **422 (Unprocessable Entity)** with `:closed` when gate denies; user count does not change.
- `RegistrationsController#create` wraps user creation + invitation acceptance in a single transaction; the two-browser concurrent acceptance scenario produces exactly one new User, not two.
- OAuth new-user creation (Branch 3) is blocked when gate denies; OAuth existing-user sign-in (Branch 1) and signed-in-user linking (Branch 2) are unaffected.
- `signups_open?` is memoized per-request on the controller; one `Invitation.find_by` call per request maximum, regardless of how many partials consult the helper.
- Initializer fails fast at boot on invalid `SIGNUP_MODE`.
- Every successful signup (open-mode, invitation-driven email/password, or OAuth) results in the user having a personal workspace via the existing `User#after_create` callback. Invitation-driven signups additionally have a membership in the inviting workspace. No new user ends up with zero workspaces.
- System spec passes end-to-end including axe-core AAA scan on the closed page.
- **Manual screen-reader walkthrough of the closed page completed** before merge (VoiceOver on macOS or NVDA on Windows). Axe-core covers structure; the walkthrough confirms narrative flow, focus restoration after the OAuth-denied 303 redirect, and that the flash announcement is heard. Required because axe-core cannot test assistive-tech narrative.
- All new strings pass through I18n; downstream forks can rename the app by overriding the single `app_name` key.
- All Tailwind classes used in `closed.html.erb` are real (no phantom utilities) — verified by either visual rendering check or `bin/rails tailwindcss:build` not warning.
- All policy and request specs pass; no regression in existing `RegistrationsController` or `OmniauthCallbacksController` specs.
