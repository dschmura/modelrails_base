# ModelRails

A multi-tenant SaaS starter kit you fork to start a product, with sign-in,
workspaces, WCAG 2.2 AAA accessibility and deployment already done. It runs on
Rails main (8.2.0.alpha, pinned to one commit) and Ruby 4.0.9.

## Set up your machine

You need three tools before you clone. On macOS, install them with
[Homebrew](https://brew.sh):

```bash
brew install mise gh
brew install --cask google-chrome   # the browser tests drive it; Chromium works too
gh auth login                       # sign the GitHub CLI in to your account
```

Then activate mise, so the clone runs mise's Ruby and not your system's: add
`eval "$(mise activate zsh)"` to `~/.zshrc` (or `bash` and `~/.bashrc`), and
open a new terminal. On Linux, follow each tool's own install page:
[mise](https://mise.jdx.dev/getting-started.html),
[the GitHub CLI](https://cli.github.com/),
[Chrome](https://www.google.com/chrome/).

**Check**, in that new terminal:

- `mise doctor` reports `activated: yes`;
- `gh auth status` says you're logged in to github.com;
- `open -Ra "Google Chrome" || open -Ra Chromium` prints nothing (on Linux,
  `command -v google-chrome chromium` prints a path).

Ruby, `age` and `fnox` come later, from `mise install` in the clone. Docker is
needed only when you deploy, from the quickstart's step 5.

## Start a product

```bash
gh repo clone dschmura/modelrails_base my_app
cd my_app
mise install   # Ruby 4.0.9 and the deploy tools
bin/fork
```

`bin/fork` names your product, creates its GitHub repo, sets the app up, and
opens the quickstart in it: every step from here to a deployed app you can
sign in to. If you skip its offer to start the app, run `bin/dev`
and open the "Start here" address it prints.

To read the quickstart before cloning: [Quickstart](app/docs/developer/quickstart.md).
[Forking](app/docs/developer/forking.md) covers `bin/fork`'s options and
taking the template's updates later with `bin/sync`.

## Tech stack

- **Framework:** Rails main (8.2.0.alpha) at a pinned commit, Ruby 4.0.9
- **Database:** SQLite, with Solid Queue, Cache and Cable in-process
- **Frontend:** TailwindCSS 4, Turbo, Stimulus, Propshaft, importmaps
- **Auth:** passwordless-first magic links, passkeys (WebAuthn), Google and
  GitHub OAuth, optional passwords, Pundit
- **Content:** Action Text with [Lexxy](https://github.com/basecamp/lexxy)
- **Docs:** served by the app at `/docs`, for users and developers
- **Testing:** RSpec, FactoryBot, Capybara with Cuprite, axe-core at WCAG 2.2
  AAA, Bullet
- **Deployment:** Kamal, with its local registry: the machine that deploys
  builds the image, and the server pulls it over SSH, so there's no registry
  account. [fnox](https://fnox.jdx.dev) keeps the deploy secrets
- **Versions:** [mise](https://mise.jdx.dev/) reads `.tool-versions` and
  `mise.toml`; the `Gemfile` reads the Ruby version from `.tool-versions`

## What's included

A multi-tenant SaaS kit, not an auth starter: workspaces with roles and
invitations, projects with per-project collaboration, a polymorphic resource
registry with rich-text documents, device/session management, and a
workspace-visible activity trail — on top of the authentication below.

### Workspaces & tenancy
- Multi-tenant workspaces with four system roles (Owner, Admin, Member, Viewer), role permissions, member management, invitations (email + magic-link), open join links, and workspace branding (logo, primary color)
- Tenancy presets (personal / shared / none) selected by env, with onboarding to match
- Suspension/archive/soft-delete lifecycle with guarded transitions
- An instance-operator area (`/operations`) above the workspaces: create and lock workspaces, look users up, suspend and reinstate accounts, grant other operators — 404 to everyone else, reauthenticated on every request, every action in the audit trail

### Projects & resources
- Projects as collaboration spaces with creator/editor/viewer memberships, pinning, capacity limits, and per-project tool toggles
- Polymorphic resource registry (documents via Action Text + Lexxy) with client-visible sharing and an external client area

### Sessions & activity
- Device/session management (list, revoke others, revoke on credential change), passkey (WebAuthn) sign-in and management
- Best-effort activity log with workspace-visible feed and 12-month retention sweep

### Authentication
- Passwordless by default: one email field sends a sign-in link, or a
  registration link for a new address
- Magic links expire after 15 minutes and work once; registration asks only for
  a name
- Passkey (WebAuthn) sign-in
- Optional passwords (`AUTH_PASSWORDS=enabled`): a 12-character minimum, a
  breached-password check, account locking after 5 failed attempts, and reset
  links that expire after 15 minutes
- Email verification with 24-hour token expiry
- Turbo Frame inline transitions (check-email confirmation replaces form in-place)

### OAuth
- Google and GitHub sign-in via OmniAuth
- Automatic account linking by email for new OAuth signups (matches verified existing users)
- Signed-in users can link additional providers; if the OAuth-returned email matches the user's primary email, the link auto-verifies, otherwise a verification email is sent to the OAuth address and the link stays pending until clicked
- Pending OAuth authentications cannot sign in. Users can resend the confirmation email (rate-limited per user) or cancel the pending link from connected accounts
- 24-hour token expiry on verification links; cross-user collision blocked; per-user rate limit on resend
- OAuth-only users can add password sign-in when passwords are on

### Account management
- Profile editing (name, email)
- Avatar upload (Active Storage) with Gravatar fallback
- Connected accounts view with last-verified-method protection (can't remove the only verified sign-in method; pending auths can always be cancelled)
- Theme preferences (light, dark, system) with Stimulus controller and Turbo Stream updates

### UI
- All text via I18n locale files (no hardcoded strings)
- WCAG 2.2 AAA, enforced by an automated axe-core gate in both themes (scope honestly documented in [/docs/developer/accessibility](https://github.com/dschmura/modelrails_base/blob/main/app/docs/developer/accessibility.md))
- Skip-to-content link, semantic HTML landmarks
- 44px minimum touch targets on interactive elements
- Dark mode support throughout
- Accessible forms with labels, ARIA attributes, and focus rings
- Design system primitives via the vendored [modelrails_ui](https://github.com/dschmura/modelrails_ui) component library (`UI::*` ViewComponents, OKLCH semantic tokens); Lookbook previews at `/lookbook` in development

### Static pages
- Home, About, Privacy, Contact

## Working on the template itself

This part is for changing ModelRails itself. A product forked from it starts
with [Start a product](#start-a-product).

### Set up

```bash
mise install
bin/setup      # dependencies, the database, then bin/dev
```

Chrome or Chromium must be installed for the system specs: Cuprite finds an
installed browser and doesn't download one.

### Run the tests

```bash
bin/parallel-rspec   # the full suite on every core, with CI's integrity gates
bundle exec rspec    # one process, for focused files and debugging
```

The coverage report is written to `coverage/index.html`.

### OAuth

Google and GitHub sign-in are optional; magic links work without them.
[OAuth Setup](app/docs/developer/getting-started.md#oauth-setup-optional) shows
the credentials they read.

### Project structure

```
app/
  controllers/
    settings/                         # Profile, avatar, password, passkeys, theme, connected accounts
    concerns/
      authenticatable.rb              # Rails 8 auth concern
      signupable.rb                   # One transaction for a new user and their pending claims
    sessions/
      lookups_controller.rb           # Email-first step: sends a sign-in or registration link
    sessions_controller.rb            # Sign-in page and password sign-in
    magic_links_controller.rb         # Request a magic link
    magic_link_callbacks_controller.rb  # Open a magic link; registration form for a new email
    magic_link_callbacks/
      sessions_controller.rb          # Spend the token and start the session (existing user)
    password_resets_controller.rb
    email_verifications_controller.rb
    omniauth_callbacks_controller.rb
    pages_controller.rb
  models/
    user.rb               # Core user; the optional password lives in user/password.rb
    session.rb            # DB-backed sessions
    magic_link_token.rb   # Secure tokens for passwordless sign-in and registration
    authentication.rb     # Multi-provider identity (email, Google, GitHub)
    user_preferences.rb   # Theme, locale, timezone
  mailers/
    authentication_mailer.rb  # Verification + password reset emails
    magic_link_mailer.rb      # Sign-in and registration magic link emails
```

### Test suite

Tests are organized by type:

- `spec/models/` — Model validations, associations, business logic
- `spec/requests/` — Controller/integration tests
- `spec/system/` — Browser tests with Cuprite (headless Chromium via CDP; no Node)
- `spec/mailers/` — Mailer content and delivery tests
