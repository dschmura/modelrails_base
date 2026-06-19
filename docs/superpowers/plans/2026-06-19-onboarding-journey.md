# Onboarding Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give first-run users on the `none` signup posture a guided wizard — name your workspace → create first project → invite teammates → land in the project home — plus a soft email-verification "check your email" screen with resend.

**Architecture:** A posture-gated redirect guard sends not-yet-onboarded `:none` users into a resumable wizard whose current step is derived from data (no workspace → Account; workspace, no project → Project; else → Invite). One nullable `users.onboarded_at` column is the only stored state. Wizard controllers live under an `Onboarding::` namespace and reuse the app's existing Workspace / Project / Invitation creation paths — they own only views and redirects. A separate soft-gate sends new registrations to a "check your email" screen with a non-blocking reminder banner.

**Tech Stack:** Rails 8.1, Ruby 4.0.4, RSpec, Capybara + Playwright (axe), TailwindCSS 4 + modelrails_ui ViewComponents, Turbo/Stimulus, SQLite.

## Global Constraints

- All user-facing text via I18n locale keys — no hardcoded strings.
- Every controller action calls Pundit `authorize` (project house rule). Reuse existing `WorkspacePolicy`, `ProjectPolicy`, `InvitationPolicy`.
- Access the signed-in user via `Current.user`; never add a `current_user` shim.
- RESTful routes only — no custom action aliases. (`resource :x` ⇒ **plural** `XsController`.)
- UI uses modelrails_ui primitives + semantic AAA tokens (`bg-*-surface`, `text-text-*`, `bg-hue-*`). No raw hex / arbitrary colors. Focus is `focus-ring` (offset outline), never `focus:ring-*`.
- WCAG 2.2 AAA on all UI; both light and dark themes. Contrast is proven in CI, not locally.
- TDD: write the failing spec first, watch it fail, implement minimally, watch it pass, commit.
- Run Ruby/Rails commands through the project toolchain (mise auto-activates in the repo; if a command isn't found, prefix `mise exec --`). RSpec runs via `bundle exec rspec`.
- Commit messages: Conventional Commits. **Never** add a `Co-Authored-By` / AI-attribution line.
- Run the full suite green before the final commit of each phase.

---

## File Structure

Created:

- `app/views/email_verifications/new.html.erb` — "check your email" screen (resend + continue).
- `app/views/shared/_email_verification_banner.html.erb` — non-blocking reminder banner.
- `db/migrate/<ts>_add_onboarded_at_to_users.rb` — state column + backfill.
- `app/controllers/concerns/requires_onboarding.rb` — posture-gated redirect guard.
- `app/controllers/onboardings_controller.rb` — dispatcher (`show`) + completion (`update`).
- `app/controllers/onboarding/base_controller.rb` — shared wizard chrome (workspace resolution, not-onboarded guard, layout).
- `app/controllers/onboarding/workspaces_controller.rb` — step 1.
- `app/controllers/onboarding/projects_controller.rb` — step 2.
- `app/controllers/onboarding/teams_controller.rb` — step 3 (invite).
- `app/views/layouts/onboarding.html.erb` — focused wizard layout (no workspace sidebar).
- `app/views/onboarding/_stepper.html.erb` — progress chrome (strict locals).
- `app/views/onboarding/workspaces/new.html.erb`, `app/views/onboarding/projects/new.html.erb`, `app/views/onboarding/teams/new.html.erb`.
- `config/locales/en/onboarding.en.yml` — all new locale keys.
- Specs under `spec/requests/onboarding/`, `spec/requests/email_verifications_spec.rb`, `spec/models/user_spec.rb` additions, `spec/system/onboarding_journey_spec.rb`.

Modified:

- `config/routes.rb` — add `new` to `:email_verification`; add onboarding routes.
- `app/controllers/registrations_controller.rb` — redirect to check-email screen.
- `app/controllers/email_verifications_controller.rb` — `new` action + auth posture.
- `app/controllers/email_verification_resends_controller.rb` — return to check-email screen + skip guard.
- `app/controllers/application_controller.rb` — `include RequiresOnboarding`.
- `app/models/user.rb` — `onboarded?`, `email_verification_pending?`.
- `app/lib/tenancy_config.rb` — `none?`.
- `app/views/layouts/application.html.erb` — render banner.
- `CHANGELOG.md`.

---

## PHASE A — Soft email-verification gate

Independent and shippable on its own (works in every posture).

### Task A1: "Check your email" screen + resend wiring

**Files:**
- Modify: `config/routes.rb:8`
- Modify: `app/controllers/email_verifications_controller.rb`
- Modify: `app/controllers/email_verification_resends_controller.rb`
- Create: `app/views/email_verifications/new.html.erb`
- Create: `config/locales/en/onboarding.en.yml`
- Test: `spec/requests/email_verifications_spec.rb`

**Interfaces:**
- Produces: route helper `new_email_verification_path`; `EmailVerificationsController#new` assigning `@authentication` (the user's email `Authentication` or nil).

- [ ] **Step 1: Write the failing test**

Create `spec/requests/email_verifications_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Email verifications", type: :request do
  describe "GET /email_verification/new" do
    let(:user) { create(:user, :with_email_auth) }

    it "renders the check-your-email screen for a signed-in user" do
      sign_in(user)
      get new_email_verification_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.email_address)
    end

    it "requires authentication" do
      get new_email_verification_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /email_verification_resend" do
    let(:user) { create(:user, :with_email_auth) }

    it "re-enqueues the verification email and returns to the check screen" do
      sign_in(user)
      expect {
        post email_verification_resend_path
      }.to have_enqueued_mail(AuthenticationMailer, :verification_email)
      expect(response).to redirect_to(new_email_verification_path)
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/email_verifications_spec.rb`
Expected: FAIL — `new_email_verification_path` undefined / no `new` action.

- [ ] **Step 3: Add the route**

In `config/routes.rb` change line 8 from:

```ruby
  resource :email_verification, only: [ :show ]
```

to:

```ruby
  resource :email_verification, only: [ :new, :show ]
```

- [ ] **Step 4: Add the controller action and adjust auth posture**

Replace `app/controllers/email_verifications_controller.rb` with the version below.
`show` stays unauthenticated (it's the token click target, which may be opened
while signed out); `new` is the "check your email" prompt for the signed-in,
unverified user, so it requires authentication.

```ruby
class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :show

  def new
    @authentication = Current.user&.authentications&.email&.first
  end

  def show
    authentication = Authentication.find_by_token_for(:email_verification, params[:token])

    if authentication.nil?
      redirect_to root_path, alert: t(".invalid_or_expired")
    else
      authentication.verify!
      redirect_to root_path, notice: t(".success")
    end
  end
end
```

> The onboarding guard's `skip_onboarding_requirement` line is intentionally NOT
> added here — that concern doesn't exist until Task C1, which adds the skip to
> this controller in its Step 6. This keeps Phase A independently shippable.

- [ ] **Step 5: Point resend back at the check screen**

In `app/controllers/email_verification_resends_controller.rb`, change the two
success/already-verified redirects from `root_path` to `new_email_verification_path`:

```ruby
class EmailVerificationResendsController < ApplicationController
  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to new_email_verification_path, alert: t("email_verification_resends.create.rate_limited") }

  def create
    authentication = Current.user.authentications.email.first

    if authentication&.verified?
      redirect_to root_path, notice: t(".already_verified")
    elsif authentication
      AuthenticationMailer.verification_email(authentication).deliver_later
      redirect_to new_email_verification_path, notice: t(".success")
    else
      redirect_to root_path, alert: t(".no_email_auth")
    end
  end
end
```

- [ ] **Step 6: Create the view**

Create `app/views/email_verifications/new.html.erb`:

```erb
<% content_for(:title) { t("email_verifications.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16 text-center">
  <div class="mx-auto w-16 h-16 rounded-full bg-info-surface flex items-center justify-center mb-6">
    <%= icon(:envelope, class: "w-8 h-8 text-info") %>
  </div>

  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("email_verifications.new.title") %>
  </h1>

  <p class="mt-3 text-text-body">
    <%= t("email_verifications.new.description_html", email: content_tag(:span, Current.user&.email_address, class: "font-semibold")) %>
  </p>

  <p class="mt-2 text-sm text-text-muted">
    <%= t("email_verifications.new.expiry") %>
  </p>

  <div class="mt-8 flex flex-col gap-3">
    <%= button_to t("email_verifications.new.resend"), email_verification_resend_path,
          class: "btn-outline btn-neutral w-full" %>

    <%= link_to t("email_verifications.new.continue"), root_path,
          class: "btn-solid btn-primary w-full" %>
  </div>

  <% if Rails.env.development? %>
    <%= link_to "/letter_opener", target: "_blank", rel: "noopener",
          class: "mt-6 inline-block text-sm text-interactive underline hover:no-underline focus-ring rounded" do %>
      <%= t("email_verifications.new.dev_open_inbox") %>
    <% end %>
  <% end %>
</div>
```

> The `.btn-solid`/`.btn-outline` + tone classes are the canonical design-system button classes. `icon(:envelope, …)` matches the existing `sessions/check_email` usage.

- [ ] **Step 7: Add locale keys**

Create `config/locales/en/onboarding.en.yml` (this file accumulates all keys for the feature across phases):

```yaml
en:
  email_verifications:
    new:
      title: "Confirm your email"
      description_html: "We sent a verification link to %{email}. Click it to confirm your address."
      expiry: "The link expires in 24 hours."
      resend: "Resend link"
      continue: "Continue"
      dev_open_inbox: "Open the dev inbox"
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/requests/email_verifications_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/email_verifications_controller.rb \
        app/controllers/email_verification_resends_controller.rb \
        app/views/email_verifications/new.html.erb \
        config/locales/en/onboarding.en.yml \
        spec/requests/email_verifications_spec.rb
git commit -m "feat(onboarding): check-your-email screen with resend"
```

### Task A2: Route registration to the check-email screen

**Files:**
- Modify: `app/controllers/registrations_controller.rb:42`
- Test: `spec/requests/registrations_spec.rb`

**Interfaces:**
- Consumes: `new_email_verification_path` (Task A1).

- [ ] **Step 1: Inspect and update the registration spec**

Run the existing spec to see the current post-create expectation:

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "create"`
Expected: PASS currently (asserts redirect to `after_authentication_url` / root).

In `spec/requests/registrations_spec.rb`, find the successful-create example and
change its redirect expectation to:

```ruby
      expect(response).to redirect_to(new_email_verification_path)
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/registrations_spec.rb -e "create"`
Expected: FAIL — still redirects to root.

- [ ] **Step 3: Update the controller**

In `app/controllers/registrations_controller.rb`, change line 42 from:

```ruby
    redirect_to after_authentication_url, notice: t(".success")
```

to:

```ruby
    redirect_to new_email_verification_path, notice: t(".success")
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/requests/registrations_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/registrations_controller.rb spec/requests/registrations_spec.rb
git commit -m "feat(onboarding): send new signups to the check-your-email screen"
```

### Task A3: Email-verification reminder banner

**Files:**
- Modify: `app/models/user.rb`
- Create: `app/views/shared/_email_verification_banner.html.erb`
- Modify: `app/views/layouts/application.html.erb:32`
- Modify: `config/locales/en/onboarding.en.yml`
- Test: `spec/models/user_spec.rb`, `spec/requests/email_verification_banner_spec.rb`

**Interfaces:**
- Produces: `User#email_verification_pending?` → Boolean (true iff an email `Authentication` exists and is unverified).

- [ ] **Step 1: Write the failing model test**

Add to `spec/models/user_spec.rb` (inside the top-level `RSpec.describe User`):

```ruby
  describe "#email_verification_pending?" do
    it "is true when the email authentication is unverified" do
      user = create(:user, :with_email_auth)
      expect(user.email_verification_pending?).to be(true)
    end

    it "is false when the email authentication is verified" do
      user = create(:user, :with_email_auth)
      user.authentications.email.first.update!(verified_at: Time.current)
      expect(user.email_verification_pending?).to be(false)
    end

    it "is false when there is no email authentication (e.g. OAuth-only)" do
      user = create(:user)
      expect(user.email_verification_pending?).to be(false)
    end
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/user_spec.rb -e "email_verification_pending?"`
Expected: FAIL — `NoMethodError`.

- [ ] **Step 3: Implement the method**

In `app/models/user.rb`, add a public method (after `#initials`, around line 69):

```ruby
  def email_verification_pending?
    auth = authentications.email.first
    auth.present? && !auth.verified?
  end
```

- [ ] **Step 4: Run the model test and confirm it passes**

Run: `bundle exec rspec spec/models/user_spec.rb -e "email_verification_pending?"`
Expected: PASS.

- [ ] **Step 5: Write the failing banner request test**

Create `spec/requests/email_verification_banner_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Email verification banner", type: :request do
  it "shows the banner to a signed-in user with an unverified email" do
    user = create(:user, :with_email_auth)
    sign_in(user)
    get root_path
    expect(response.body).to include("verify-banner")
  end

  it "hides the banner once the email is verified" do
    user = create(:user, :with_email_auth)
    user.authentications.email.first.update!(verified_at: Time.current)
    sign_in(user)
    get root_path
    expect(response.body).not_to include("verify-banner")
  end
end
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/email_verification_banner_spec.rb`
Expected: FAIL — no `verify-banner` markup.

- [ ] **Step 7: Create the banner partial**

Create `app/views/shared/_email_verification_banner.html.erb`:

```erb
<% if Current.user&.email_verification_pending? %>
  <div id="verify-banner"
       role="status"
       class="bg-warning-surface text-warning warning-border border-b">
    <div class="max-w-5xl mx-auto px-4 py-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
      <%= icon(:envelope, class: "w-4 h-4 shrink-0") %>
      <span><%= t("email_verifications.banner.message") %></span>
      <%= link_to t("email_verifications.banner.action"), new_email_verification_path,
            class: "font-semibold underline hover:no-underline focus-ring rounded" %>
    </div>
  </div>
<% end %>
```

> Tinted-chip treatment (`bg-warning-surface` + `text-warning` + `warning-border`) is the canonical signal style for an alert surface — do not use a solid fill here.

- [ ] **Step 8: Render it in the layout**

In `app/views/layouts/application.html.erb`, add immediately after line 32
(`<%= render "shared/header" %>`):

```erb
    <%= render "shared/email_verification_banner" %>
```

- [ ] **Step 9: Add locale keys**

In `config/locales/en/onboarding.en.yml`, add under `email_verifications:`:

```yaml
    banner:
      message: "Please confirm your email address."
      action: "Resend link"
```

- [ ] **Step 10: Run both specs and confirm they pass**

Run: `bundle exec rspec spec/models/user_spec.rb spec/requests/email_verification_banner_spec.rb`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add app/models/user.rb app/views/shared/_email_verification_banner.html.erb \
        app/views/layouts/application.html.erb config/locales/en/onboarding.en.yml \
        spec/models/user_spec.rb spec/requests/email_verification_banner_spec.rb
git commit -m "feat(onboarding): non-blocking email-verification reminder banner"
```

---

## PHASE B — Onboarding state

### Task B1: `onboarded_at` column, backfill, and posture helpers

**Files:**
- Create: `db/migrate/<ts>_add_onboarded_at_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `app/lib/tenancy_config.rb`
- Test: `spec/models/user_spec.rb`, `spec/lib/tenancy_config_spec.rb` (create if absent)

**Interfaces:**
- Produces: `User#onboarded?` → Boolean; `TenancyConfig.none?` → Boolean; `users.onboarded_at : datetime` (nullable).

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/user_spec.rb`:

```ruby
  describe "#onboarded?" do
    it "is false when onboarded_at is nil" do
      expect(build(:user, onboarded_at: nil).onboarded?).to be(false)
    end

    it "is true when onboarded_at is set" do
      expect(build(:user, onboarded_at: Time.current).onboarded?).to be(true)
    end
  end
```

Create `spec/lib/tenancy_config_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TenancyConfig do
  describe ".none?" do
    it "is true when onboarding is :none" do
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      expect(TenancyConfig.none?).to be(true)
    end

    it "is false otherwise" do
      allow(TenancyConfig).to receive(:onboarding).and_return(:personal)
      expect(TenancyConfig.none?).to be(false)
    end
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/models/user_spec.rb -e "onboarded?" spec/lib/tenancy_config_spec.rb`
Expected: FAIL — unknown attribute `onboarded_at` / no `none?`.

- [ ] **Step 3: Generate and write the migration**

Run: `bin/rails g migration AddOnboardedAtToUsers onboarded_at:datetime`

Then replace the generated file body with:

```ruby
class AddOnboardedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :onboarded_at, :datetime

    # Existing users predate onboarding — stamp them complete so the wizard
    # guard never retroactively traps them.
    User.reset_column_information
    User.update_all(onboarded_at: Time.current)
  end

  def down
    remove_column :users, :onboarded_at
  end
end
```

- [ ] **Step 4: Run the migration**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: schema updated; `db/schema.rb` shows `t.datetime "onboarded_at"` on `users`.

- [ ] **Step 5: Implement the model + config methods**

In `app/models/user.rb`, add a public method (after `#email_verification_pending?`):

```ruby
  def onboarded?
    onboarded_at.present?
  end
```

In `app/lib/tenancy_config.rb`, add (after `def shared?`):

```ruby
  def none?
    onboarding == :none
  end
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/models/user_spec.rb -e "onboarded?" spec/lib/tenancy_config_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/user.rb app/lib/tenancy_config.rb \
        spec/models/user_spec.rb spec/lib/tenancy_config_spec.rb
git commit -m "feat(onboarding): add users.onboarded_at state + posture helpers"
```

---

## PHASE C — Wizard skeleton, guard, and steps

### Task C1: Onboarding skeleton — routes, guard, dispatcher, base controller, layout

**Files:**
- Modify: `config/routes.rb` (after line 100, before `draw(:app)`)
- Create: `app/controllers/concerns/requires_onboarding.rb`
- Modify: `app/controllers/application_controller.rb:2`
- Modify: `app/controllers/email_verifications_controller.rb`, `app/controllers/email_verification_resends_controller.rb` (add skip)
- Create: `app/controllers/onboardings_controller.rb`
- Create: `app/controllers/onboarding/base_controller.rb`
- Create: `app/views/layouts/onboarding.html.erb`
- Modify: `config/locales/en/onboarding.en.yml`
- Test: `spec/requests/onboarding/dispatcher_spec.rb`, `spec/requests/onboarding/guard_spec.rb`

**Interfaces:**
- Produces:
  - Routes: `onboarding_path` (GET show, PATCH update), `new_onboarding_workspace_path`, `onboarding_workspace_path` (POST), `new_onboarding_project_path`, `onboarding_project_path` (POST), `new_onboarding_team_path`, `onboarding_team_path` (POST).
  - `RequiresOnboarding` concern with class method `skip_onboarding_requirement(**opts)` and `before_action :require_onboarding`.
  - `Onboarding::BaseController` setting `@workspace = Current.user.workspaces.kept.first` and `Current.workspace`, using `layout "onboarding"`, with a `redirect_to root_path if Current.user.onboarded?` guard.

- [ ] **Step 1: Write the failing dispatcher + guard specs**

Create `spec/requests/onboarding/dispatcher_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Onboarding dispatcher", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  def admit(user, workspace)
    workspace.memberships.create!(user: user, role: owner_role)
  end

  it "routes a user with no workspace to the account step" do
    user = create(:user, :with_zero_workspaces)
    sign_in(user)
    get onboarding_path
    expect(response).to redirect_to(new_onboarding_workspace_path)
  end

  it "routes a user with a workspace but no project to the project step" do
    user = create(:user, :with_zero_workspaces)
    workspace = create(:workspace)
    admit(user, workspace)
    sign_in(user)
    get onboarding_path
    expect(response).to redirect_to(new_onboarding_project_path)
  end

  it "routes a user with a workspace and a project to the team step" do
    user = create(:user, :with_zero_workspaces)
    workspace = create(:workspace)
    admit(user, workspace)
    create(:project, workspace: workspace)
    sign_in(user)
    get onboarding_path
    expect(response).to redirect_to(new_onboarding_team_path)
  end

  it "PATCH marks onboarding complete and lands on the workspace" do
    user = create(:user, :with_zero_workspaces)
    workspace = create(:workspace)
    admit(user, workspace)
    sign_in(user)
    patch onboarding_path
    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_path(workspace))
  end
end
```

Create `spec/requests/onboarding/guard_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Onboarding guard", type: :request do
  context "under :none posture with a not-onboarded user" do
    before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

    it "redirects app pages into onboarding" do
      user = create(:user, :with_zero_workspaces)
      sign_in(user)
      get workspaces_path
      expect(response).to redirect_to(onboarding_path)
    end

    it "does not redirect the email-verification screen (escape hatch)" do
      user = create(:user, :with_zero_workspaces, :with_email_auth)
      sign_in(user)
      get new_email_verification_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "never redirects under non-:none postures" do
    allow(TenancyConfig).to receive(:onboarding).and_return(:personal)
    user = create(:user, :with_zero_workspaces)
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "does not redirect an already-onboarded :none user" do
    allow(TenancyConfig).to receive(:onboarding).and_return(:none)
    user = create(:user, :with_zero_workspaces, onboarded_at: Time.current)
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/requests/onboarding/`
Expected: FAIL — `onboarding_path` undefined.

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, after the invitation accept/decline routes (after line 100) and before the `draw(:app)` comment block, add:

```ruby
  resource :onboarding, only: %i[show update]
  namespace :onboarding do
    resource :workspace, only: %i[new create]
    resource :project, only: %i[new create]
    resource :team,    only: %i[new create]
  end
```

- [ ] **Step 4: Create the guard concern**

Create `app/controllers/concerns/requires_onboarding.rb`:

```ruby
# Posture-gated first-run guard. Under WORKSPACE_ON_SIGNUP=none, a signed-in
# user who has not finished onboarding is funneled into the wizard. Inert in
# every other posture, so the :personal/:shared flows and the zero-workspace
# crash-safety spec are unaffected. Controllers that must stay reachable mid-
# onboarding (the wizard itself, sign-out, email verification/resend) opt out
# via `skip_onboarding_requirement`.
module RequiresOnboarding
  extend ActiveSupport::Concern

  included do
    before_action :require_onboarding
  end

  class_methods do
    def skip_onboarding_requirement(**options)
      skip_before_action :require_onboarding, **options
    end
  end

  private

  def require_onboarding
    return unless TenancyConfig.none?
    return unless Current.user && !Current.user.onboarded?

    redirect_to onboarding_path
  end
end
```

- [ ] **Step 5: Include the guard in ApplicationController**

In `app/controllers/application_controller.rb`, add after `include Authenticatable` (line 2):

```ruby
  include RequiresOnboarding
```

> Order matters: `Authenticatable`'s `require_authentication` (which resumes the session and so populates `Current.user`) must run before `require_onboarding`.

- [ ] **Step 6: Opt the auth/verification controllers out of the guard**

In `app/controllers/email_verifications_controller.rb`, add below `allow_unauthenticated_access only: :show`:

```ruby
  skip_onboarding_requirement
```

In `app/controllers/email_verification_resends_controller.rb`, add as the first line inside the class (above `rate_limit`):

```ruby
  skip_onboarding_requirement
```

> `SessionsController`, `RegistrationsController`, `PasswordsController`, the magic-link controllers, and `OmniauthCallbacksController` use `allow_unauthenticated_access`, so the session is never resumed there and `require_onboarding` no-ops (`Current.user` is nil). They need no skip. The two email-verification controllers do resume the session, so they need the explicit skip above.

- [ ] **Step 7: Create the dispatcher controller**

Create `app/controllers/onboardings_controller.rb`:

```ruby
class OnboardingsController < ApplicationController
  skip_onboarding_requirement

  # Single entry point: compute the derived step and redirect to it.
  def show
    return redirect_to(root_path) if Current.user.onboarded?

    workspace = Current.user.workspaces.kept.first
    if workspace.nil?
      redirect_to new_onboarding_workspace_path
    elsif workspace.projects.kept.none?
      redirect_to new_onboarding_project_path
    else
      redirect_to new_onboarding_team_path
    end
  end

  # "Skip for now" / finish: mark complete and land in the workspace.
  def update
    Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?

    workspace = Current.user.workspaces.kept.first
    if workspace && (project = workspace.projects.kept.first)
      redirect_to workspace_project_path(workspace, project), notice: t(".complete")
    elsif workspace
      redirect_to workspace_path(workspace), notice: t(".complete")
    else
      redirect_to root_path, notice: t(".complete")
    end
  end
end
```

- [ ] **Step 8: Create the base controller**

Create `app/controllers/onboarding/base_controller.rb`:

```ruby
module Onboarding
  class BaseController < ApplicationController
    skip_onboarding_requirement
    layout "onboarding"

    before_action :require_not_onboarded
    before_action :set_onboarding_workspace

    private

    def require_not_onboarded
      redirect_to root_path if Current.user.onboarded?
    end

    # During first-run the user owns exactly one workspace; resolve it so the
    # project/team steps run inside its tenancy scope. Nil at the account step.
    def set_onboarding_workspace
      @workspace = Current.user.workspaces.kept.first
      Current.workspace = @workspace if @workspace
    end
  end
end
```

- [ ] **Step 9: Create the onboarding layout**

Create `app/views/layouts/onboarding.html.erb`:

```erb
<!DOCTYPE html>
<html lang="<%= I18n.locale %>"
      data-controller="theme"
      data-theme-theme-value="<%= current_user_theme %>">
<%= render "shared/layout_head" %>

  <body class="min-h-screen flex flex-col bg-surface-raised text-text-heading">
    <%= render "shared/skip_link" %>
    <%= render "shared/email_verification_banner" %>

    <main id="main-content" tabindex="-1" class="flex-1">
      <%= yield %>
    </main>

    <%= render "shared/layout_tail" %>
  </body>
</html>
```

- [ ] **Step 10: Add dispatcher locale key**

In `config/locales/en/onboarding.en.yml`, add a top-level (under `en:`) section:

```yaml
  onboardings:
    update:
      complete: "You're all set."
```

- [ ] **Step 11: Run the specs and confirm they pass**

Run: `bundle exec rspec spec/requests/onboarding/`
Expected: PASS (dispatcher 4 + guard 4 = 8 examples).

- [ ] **Step 12: Commit**

```bash
git add config/routes.rb app/controllers/concerns/requires_onboarding.rb \
        app/controllers/application_controller.rb \
        app/controllers/email_verifications_controller.rb \
        app/controllers/email_verification_resends_controller.rb \
        app/controllers/onboardings_controller.rb \
        app/controllers/onboarding/base_controller.rb \
        app/views/layouts/onboarding.html.erb config/locales/en/onboarding.en.yml \
        spec/requests/onboarding/dispatcher_spec.rb spec/requests/onboarding/guard_spec.rb
git commit -m "feat(onboarding): wizard skeleton — routes, posture guard, dispatcher, layout"
```

### Task C2: Step 1 — name your workspace

**Files:**
- Create: `app/controllers/onboarding/workspaces_controller.rb`
- Create: `app/views/onboarding/_stepper.html.erb`
- Create: `app/views/onboarding/workspaces/new.html.erb`
- Modify: `config/locales/en/onboarding.en.yml`
- Test: `spec/requests/onboarding/workspaces_spec.rb`

**Interfaces:**
- Consumes: routes from C1; `Onboarding::BaseController`.
- Produces: `Onboarding::WorkspacesController#create` creating a `Workspace` + owner `Membership`, redirecting to `new_onboarding_project_path`. Stepper partial `onboarding/_stepper` with strict local `current:` (`:workspace|:project|:team`).

- [ ] **Step 1: Write the failing test**

Create `spec/requests/onboarding/workspaces_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Onboarding · account step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  before { sign_in(user) }

  it "renders the name-your-account form" do
    get new_onboarding_workspace_path
    expect(response).to have_http_status(:ok)
  end

  it "creates the workspace + owner membership and advances to the project step" do
    expect {
      post onboarding_workspace_path, params: { workspace: { name: "Acme Co" } }
    }.to change(Workspace.kept, :count).by(1)

    workspace = user.reload.workspaces.kept.first
    expect(workspace.name).to eq("Acme Co")
    expect(workspace.owner).to eq(user)
    expect(response).to redirect_to(new_onboarding_project_path)
  end

  it "re-renders on a blank name" do
    post onboarding_workspace_path, params: { workspace: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/onboarding/workspaces_spec.rb`
Expected: FAIL — uninitialized constant `Onboarding::WorkspacesController`.

- [ ] **Step 3: Create the controller**

Create `app/controllers/onboarding/workspaces_controller.rb`:

```ruby
module Onboarding
  class AccountsController < BaseController
    def new
      authorize Workspace
      @workspace = Workspace.new
    end

    def create
      authorize Workspace
      @workspace = Workspace.new(workspace_params)

      if @workspace.save
        owner_role = Role.find_by!(slug: "owner", workspace_id: nil)
        @workspace.memberships.create!(user: Current.user, role: owner_role)
        redirect_to new_onboarding_project_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def workspace_params
      params.require(:workspace).permit(:name)
    end
  end
end
```

- [ ] **Step 4: Create the stepper partial**

Create `app/views/onboarding/_stepper.html.erb`:

```erb
<%# locals: (current:) %>
<% step_keys = %i[workspace project team] %>
<% current_index = step_keys.index(current) %>
<%= render(UI::StepperComponent.new(steps: step_keys.each_with_index.map { |key, i|
      {
        label: t("onboarding.steps.#{key}"),
        status: (i < current_index ? :complete : (i == current_index ? :current : :pending))
      }
    })) %>
```

- [ ] **Step 5: Create the view**

Create `app/views/onboarding/workspaces/new.html.erb`:

```erb
<% content_for(:title) { t("onboarding.workspaces.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <%= render "onboarding/stepper", current: :workspace %>

  <h1 class="mt-10 text-3xl font-bold text-text-heading">
    <%= t("onboarding.workspaces.new.title") %>
  </h1>
  <p class="mt-2 text-text-body">
    <%= t("onboarding.workspaces.new.subtitle") %>
  </p>

  <%= form_with(model: @workspace, url: onboarding_workspace_path, class: "mt-8 space-y-6") do |form| %>
    <%= form.error_summary %>

    <%= form.text_field :name,
          label: t("onboarding.workspaces.new.name_label"),
          required: true,
          autofocus: true %>

    <%= form.submit t("onboarding.workspaces.new.submit"), class: "w-full" %>
  <% end %>
</div>
```

- [ ] **Step 6: Add locale keys**

In `config/locales/en/onboarding.en.yml`, add under `en:`:

```yaml
  onboarding:
    steps:
      workspace: "Workspace"
      project: "Project"
      team: "Team"
    workspaces:
      new:
        title: "Name your workspace"
        subtitle: "This is the workspace your team will join."
        name_label: "Workspace name"
        submit: "Continue"
      create:
        success: "Account created."
```

- [ ] **Step 7: Run the test and confirm it passes**

Run: `bundle exec rspec spec/requests/onboarding/workspaces_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/onboarding/workspaces_controller.rb \
        app/views/onboarding/_stepper.html.erb \
        app/views/onboarding/workspaces/new.html.erb \
        config/locales/en/onboarding.en.yml \
        spec/requests/onboarding/workspaces_spec.rb
git commit -m "feat(onboarding): step 1 — name your workspace"
```

### Task C3: Step 2 — create first project

**Files:**
- Create: `app/controllers/onboarding/projects_controller.rb`
- Create: `app/views/onboarding/projects/new.html.erb`
- Modify: `config/locales/en/onboarding.en.yml`
- Test: `spec/requests/onboarding/projects_spec.rb`

**Interfaces:**
- Consumes: `Current.workspace` set by `Onboarding::BaseController`.
- Produces: `Onboarding::ProjectsController#create` building `Current.workspace.projects` + creator `ProjectMembership`, redirecting to `new_onboarding_team_path`.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/onboarding/projects_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Onboarding · project step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    sign_in(user)
  end

  it "renders the new-project form" do
    get new_onboarding_project_path
    expect(response).to have_http_status(:ok)
  end

  it "creates the project and advances to the team step" do
    expect {
      post onboarding_project_path, params: { project: { name: "Acme Website", description: "Marketing site" } }
    }.to change(workspace.projects.kept, :count).by(1)

    project = workspace.projects.kept.first
    expect(project.name).to eq("Acme Website")
    expect(project.project_memberships.find_by(user: user)&.role).to eq("creator")
    expect(response).to redirect_to(new_onboarding_team_path)
  end

  it "redirects back to the account step if no workspace exists yet" do
    other = create(:user, :with_zero_workspaces)
    sign_in(other)
    get new_onboarding_project_path
    expect(response).to redirect_to(new_onboarding_workspace_path)
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/onboarding/projects_spec.rb`
Expected: FAIL — uninitialized constant `Onboarding::ProjectsController`.

- [ ] **Step 3: Create the controller**

Create `app/controllers/onboarding/projects_controller.rb`:

```ruby
module Onboarding
  class ProjectsController < BaseController
    before_action :require_workspace

    def new
      authorize Project
      @project = Current.workspace.projects.build
    end

    def create
      authorize Project
      @project = Current.workspace.projects.build(project_params)
      @project.created_by = Current.user

      if @project.save
        @project.project_memberships.create!(user: Current.user, role: "creator")
        redirect_to new_onboarding_team_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def require_workspace
      redirect_to new_onboarding_workspace_path if Current.workspace.nil?
    end

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
```

- [ ] **Step 4: Create the view**

Create `app/views/onboarding/projects/new.html.erb`:

```erb
<% content_for(:title) { t("onboarding.projects.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <%= render "onboarding/stepper", current: :project %>

  <h1 class="mt-10 text-3xl font-bold text-text-heading">
    <%= t("onboarding.projects.new.title") %>
  </h1>
  <p class="mt-2 text-text-body">
    <%= t("onboarding.projects.new.subtitle") %>
  </p>

  <%= form_with(model: @project, url: onboarding_project_path, class: "mt-8 space-y-6") do |form| %>
    <%= form.error_summary %>

    <%= form.text_field :name,
          label: t("onboarding.projects.new.name_label"),
          required: true,
          autofocus: true %>

    <%= form.text_area :description,
          label: t("onboarding.projects.new.description_label"),
          rows: 3 %>

    <%= form.submit t("onboarding.projects.new.submit"), class: "w-full" %>
  <% end %>
</div>
```

- [ ] **Step 5: Add locale keys**

In `config/locales/en/onboarding.en.yml`, add under `onboarding:`:

```yaml
    projects:
      new:
        title: "Create your first project"
        subtitle: "Projects hold the work — you can add more later."
        name_label: "Project name"
        description_label: "What's it about? (optional)"
        submit: "Continue"
      create:
        success: "Project created."
```

- [ ] **Step 6: Run the test and confirm it passes**

Run: `bundle exec rspec spec/requests/onboarding/projects_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/onboarding/projects_controller.rb \
        app/views/onboarding/projects/new.html.erb \
        config/locales/en/onboarding.en.yml \
        spec/requests/onboarding/projects_spec.rb
git commit -m "feat(onboarding): step 2 — create first project"
```

### Task C4: Step 3 — invite teammates (and finish)

**Files:**
- Create: `app/controllers/onboarding/teams_controller.rb`
- Create: `app/views/onboarding/teams/new.html.erb`
- Modify: `config/locales/en/onboarding.en.yml`
- Test: `spec/requests/onboarding/teams_spec.rb`

**Interfaces:**
- Consumes: `Current.workspace` + its first kept project; `Invitation.bulk_invite!(workspace:, emails:, role:, invited_by:)`; `OnboardingsController#update` (skip path).
- Produces: `Onboarding::TeamsController#create` sending invites, stamping `onboarded_at`, redirecting to the project home.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/onboarding/teams_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Onboarding · team step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let!(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    end
  end
  let!(:project) { create(:project, workspace: workspace) }

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    sign_in(user)
  end

  it "renders the invite form" do
    get new_onboarding_team_path
    expect(response).to have_http_status(:ok)
  end

  it "sends invites, completes onboarding, and lands on the project" do
    expect {
      post onboarding_team_path, params: {
        invitation: { emails: "sam@example.com, lee@example.com", role_id: member_role.id }
      }
    }.to change(Invitation, :count).by(2)

    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end

  it "re-renders when no emails are provided" do
    post onboarding_team_path, params: { invitation: { emails: "", role_id: member_role.id } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.onboarded?).to be(false)
  end

  it "skipping (PATCH onboarding) completes onboarding without invites" do
    expect {
      patch onboarding_path
    }.not_to change(Invitation, :count)
    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/onboarding/teams_spec.rb`
Expected: FAIL — uninitialized constant `Onboarding::TeamsController`.

- [ ] **Step 3: Create the controller**

Create `app/controllers/onboarding/teams_controller.rb`:

```ruby
module Onboarding
  # Singular `resource :team` maps to a PLURAL controller name.
  class TeamsController < BaseController
    before_action :require_workspace_with_project

    def new
      authorize Invitation
      @invitation = Invitation.new
      @roles = Current.workspace.effective_roles
    end

    def create
      authorize Invitation

      emails = invitation_params[:emails].to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
      if emails.empty?
        @invitation = Invitation.new
        @roles = Current.workspace.effective_roles
        flash.now[:alert] = t(".no_emails")
        return render :new, status: :unprocessable_entity
      end

      role = Current.workspace.effective_roles.find(invitation_params[:role_id])
      Invitation.bulk_invite!(
        workspace: Current.workspace,
        emails: emails,
        role: role,
        invited_by: Current.user
      )

      Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?
      redirect_to project_home_path, notice: t(".sent")
    end

    private

    def require_workspace_with_project
      redirect_to onboarding_path if Current.workspace.nil? || Current.workspace.projects.kept.none?
    end

    def project_home_path
      workspace_project_path(Current.workspace, Current.workspace.projects.kept.first)
    end

    def invitation_params
      params.require(:invitation).permit(:emails, :role_id)
    end
  end
end
```

- [ ] **Step 4: Create the view**

Create `app/views/onboarding/teams/new.html.erb`:

```erb
<% content_for(:title) { t("onboarding.teams.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <%= render "onboarding/stepper", current: :team %>

  <h1 class="mt-10 text-3xl font-bold text-text-heading">
    <%= t("onboarding.teams.new.title") %>
  </h1>
  <p class="mt-2 text-text-body">
    <%= t("onboarding.teams.new.subtitle") %>
  </p>

  <%= form_with(model: @invitation, url: onboarding_team_path, class: "mt-8 space-y-6") do |form| %>
    <%= form.text_area :emails,
          label: t("onboarding.teams.new.emails_label"),
          rows: 3,
          placeholder: t("onboarding.teams.new.emails_placeholder") %>

    <%= form.select :role_id,
          options_from_collection_for_select(@roles, :id, :name, @roles.find { |r| r.slug == "member" }&.id),
          { label: t("onboarding.teams.new.role_label") } %>

    <%= form.submit t("onboarding.teams.new.submit"), class: "w-full" %>
  <% end %>

  <%= button_to t("onboarding.teams.new.skip"), onboarding_path, method: :patch,
        class: "btn-text btn-neutral w-full mt-3" %>
</div>
```

> If `form.select` with a `label:` option isn't supported by the app's form
> builder, fall back to a `<label data-slot="label">` + `form.select` pair; verify
> against an existing select usage (`app/views/workspaces/invitations/new.html.erb`)
> during implementation.

- [ ] **Step 5: Add locale keys**

In `config/locales/en/onboarding.en.yml`, add under `onboarding:`:

```yaml
    teams:
      new:
        title: "Invite your team"
        subtitle: "Add teammates by email — or skip and invite them later."
        emails_label: "Email addresses"
        emails_placeholder: "sam@example.com, lee@example.com"
        role_label: "Role"
        submit: "Send invites"
        skip: "Skip for now"
      create:
        sent: "Invitations sent."
        no_emails: "Enter at least one email address, or skip for now."
```

- [ ] **Step 6: Run the test and confirm it passes**

Run: `bundle exec rspec spec/requests/onboarding/teams_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/onboarding/teams_controller.rb \
        app/views/onboarding/teams/new.html.erb \
        config/locales/en/onboarding.en.yml \
        spec/requests/onboarding/teams_spec.rb
git commit -m "feat(onboarding): step 3 — invite teammates and finish"
```

---

## PHASE D — Full journey + accessibility

### Task D1: End-to-end system spec + AAA axe coverage

**Files:**
- Create: `spec/system/onboarding_journey_spec.rb`

**Interfaces:**
- Consumes: all routes/views from Phases A–C.

- [ ] **Step 1: Write the system spec**

Create `spec/system/onboarding_journey_spec.rb`:

```ruby
require "rails_helper"

# Posture must be :none for the real server thread, so set the shared
# Rails.configuration value (an RSpec mock would not cross into the Capybara
# server thread). Restored after each example.
RSpec.describe "Onboarding journey", type: :system do
  around do |example|
    original = Rails.configuration.x.tenancy.onboarding
    Rails.configuration.x.tenancy.onboarding = :none
    example.run
    Rails.configuration.x.tenancy.onboarding = original
  end

  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let!(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    end
  end
  let(:user) { create(:user, :with_zero_workspaces) }

  before { sign_in(user) }

  it "walks account → project → invite → project home" do
    visit root_path
    expect(page).to have_current_path(new_onboarding_workspace_path)
    expect(page).to be_axe_clean

    fill_in "Workspace name", with: "Acme Co"
    click_button "Continue"

    expect(page).to have_current_path(new_onboarding_project_path)
    expect(page).to be_axe_clean
    fill_in "Project name", with: "Acme Website"
    click_button "Continue"

    expect(page).to have_current_path(new_onboarding_team_path)
    expect(page).to be_axe_clean
    fill_in "Email addresses", with: "sam@example.com"
    click_button "Send invites"

    workspace = user.reload.workspaces.kept.first
    project = workspace.projects.kept.first
    expect(page).to have_current_path(workspace_project_path(workspace, project))
    expect(user.onboarded?).to be(true)
  end

  it "supports skipping the invite step" do
    visit new_onboarding_workspace_path
    fill_in "Workspace name", with: "Acme Co"
    click_button "Continue"
    fill_in "Project name", with: "Acme Website"
    click_button "Continue"

    click_button "Skip for now"

    expect(user.reload.onboarded?).to be(true)
    workspace = user.workspaces.kept.first
    expect(page).to have_current_path(workspace_project_path(workspace, workspace.projects.kept.first))
  end
end
```

> `be_axe_clean` is the project's axe matcher (see `spec/system/notifications_a11y_spec.rb`
> for the exact matcher in use — mirror it). Locally axe runs at AA; the CI hook in
> `spec/support/playwright_accessibility.rb` upgrades to WCAG 2.2 AAA. Do not claim
> AAA from a local pass — push and read CI.

- [ ] **Step 2: Run the system spec**

Run: `bundle exec rspec spec/system/onboarding_journey_spec.rb`
Expected: PASS (2 examples). If a label text doesn't match, align the spec's
`fill_in`/`click_button` text with the rendered labels from Phase C views.

- [ ] **Step 3: Commit**

```bash
git add spec/system/onboarding_journey_spec.rb
git commit -m "test(onboarding): end-to-end journey + axe coverage"
```

### Task D2: i18n audit, CHANGELOG, full suite

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Verify no missing translations**

Run: `bundle exec rspec spec/requests/onboarding spec/requests/email_verifications_spec.rb spec/requests/email_verification_banner_spec.rb`
Expected: PASS, and grep the rendered bodies for `translation missing`:

Run: `bundle exec rspec spec/requests/onboarding 2>&1 | grep -i "translation missing" || echo "no missing translations"`
Expected: `no missing translations`.

- [ ] **Step 2: Add a CHANGELOG entry**

In `CHANGELOG.md`, add one line under the unreleased section (match the file's
existing one-line action-statement style):

```markdown
- Add first-run onboarding journey (none posture): name account → first project → invite, with a soft email-verification gate.
```

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures. Investigate any pending examples.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(onboarding): changelog entry for the onboarding journey"
```

- [ ] **Step 5: Push and open the PR (after the full suite is green)**

```bash
git push -u origin feat/onboarding-journey
```

Then open a PR to `main` summarizing Phases A–D. Lefthook pre-push runs CI locally;
do not bypass it. AAA contrast is proven by the CI `test` job, not locally.

---

## Self-Review (completed during authoring)

- **Spec coverage:** check-email screen (A1) ✓; registration redirect (A2) ✓; reminder banner (A3) ✓; `onboarded_at` + backfill + posture helpers (B1) ✓; routes + guard + dispatcher + base + layout (C1) ✓; account/project/team steps (C2–C4) ✓; soft-gate, derive-from-data state, top-level routes, `none`-only guard, stepper reuse, AAA — all mapped. Out-of-scope items (email-exists→login, Apple OAuth, pricing/marketing, tools toggles) intentionally absent.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; the two "verify against existing usage" notes (form `select` label API; axe matcher name) point at concrete reference files rather than deferring work.
- **Type/name consistency:** `Onboarding::TeamsController` (plural) matches singular `resource :team`; `skip_onboarding_requirement`, `require_onboarding`, `onboarded?`, `email_verification_pending?`, `TenancyConfig.none?`, `new_email_verification_path` used consistently across tasks; `Invitation.bulk_invite!` signature matches the existing call site.
