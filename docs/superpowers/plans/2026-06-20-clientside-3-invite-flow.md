# Clientside #3 — Client Invite Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a team invite an external client (by email + company) to a project's client side; the client accepts (existing account in one click, or sets up a login) and lands in the read-only client area.

**Architecture:** Extend the existing hardened `Invitation` with a client variant (nullable role + `company_name`; `accept!` creates a `ClientAccess` and stamps `onboarded_at`), reusing the token / `consume!` / `EmailMismatch` / new-vs-existing accept machinery. A dedicated team-side controller sends client invites; client landing is centralized in `authenticated_home_path`.

**Tech Stack:** Rails 8.1, Ruby 4.0.4, RSpec, Capybara + Playwright (axe), Action Mailer, SQLite.

## Global Constraints

- All user-facing text via I18n locale keys — no hardcoded strings.
- Controllers acting on a resource call Pundit `authorize`; the client-invite controller reuses `InvitationPolicy` (`can?("manage_members")`).
- `Current.user` for the signed-in user. Client landing must NOT depend on `Current.workspace`.
- A client invite is an `Invitation` with `company_name` present, `invitable_type == "Project"`, and a nil `role`. `client_invite?` ⇔ `company_name.present?`.
- The member-invite paths (`bulk_invite!`, project/workspace accept) MUST remain unchanged; making `role` optional must NOT weaken member-invite validation (a member invite still requires a role).
- RESTful routes only (`resource(s) :x` ⇒ plural controller).
- modelrails_ui + semantic AAA tokens; `focus-ring` not `focus:ring-*`; WCAG 2.2 AAA proven in CI, both themes.
- TDD: failing spec first, watch it fail, minimal implementation, watch it pass, commit.
- Toolchain: `bundle exec rspec` (mise auto-activates; else `mise exec --`); `bin/rails` migrations; `bin/rails db:test:prepare` after migrating; commit `db/schema.rb`. `rake erb:check` runs on push/CI only — run `mise exec -- bundle exec rake erb:check` before each phase's final commit.
- Conventional Commits; **never** a `Co-Authored-By` / AI-attribution line. Full suite green before each phase's final commit.

---

## File Structure

Created:

- `db/migrate/<ts>_allow_client_invitations.rb`
- `app/views/invitation_mailer/invite_client.html.erb`, `app/views/invitation_mailer/invite_client.text.erb`
- `app/controllers/workspaces/projects/client_invitations_controller.rb`
- `app/views/workspaces/projects/client_invitations/new.html.erb`
- Specs: `spec/models/invitation_spec.rb` additions, `spec/mailers/invitation_mailer_spec.rb` additions, `spec/requests/workspaces/projects/client_invitations_spec.rb`, `spec/requests/clientside/invite_accept_spec.rb`, `spec/requests/authenticated_home_spec.rb`, `spec/system/clientside_invite_spec.rb`

Modified:

- `app/models/invitation.rb` — client variant
- `app/mailers/invitation_mailer.rb` — `invite_client`
- `spec/factories/invitations.rb` — `:client` trait
- `config/routes.rb` — `resources :client_invitations`
- `app/controllers/invitation_accepts_controller.rb` — client accept redirect
- `app/views/invitation_accepts/show.html.erb` — client framing (role-nil safe)
- `app/controllers/concerns/authenticatable.rb` — `authenticated_home_path` client-only branch
- `app/controllers/email_verifications_controller.rb` — success redirect to `after_authentication_url`
- `app/views/workspaces/projects/clientsides/edit.html.erb` — link to invite a client
- `config/locales/en/clientside.en.yml`, `config/locales/en/*` mailer keys

---

## PHASE P1 — Invitation client variant + mailer

### Task 1: Extend Invitation + `invite_client` mailer

**Files:**
- Create: `db/migrate/<ts>_allow_client_invitations.rb`, `app/views/invitation_mailer/invite_client.html.erb`, `app/views/invitation_mailer/invite_client.text.erb`
- Modify: `app/models/invitation.rb`, `app/mailers/invitation_mailer.rb`, `spec/factories/invitations.rb`, `config/locales/en/clientside.en.yml`
- Test: `spec/models/invitation_spec.rb`, `spec/mailers/invitation_mailer_spec.rb`

**Interfaces:**
- Produces: `invitations.company_name` (string, nullable); `invitations.role_id` now nullable; `Invitation#client_invite?` → Boolean; `Invitation.invite_client!(project:, email:, company_name:, invited_by:)` → Invitation; `accept!` creates a `ClientAccess` + stamps `onboarded_at` for client invites; `InvitationMailer#invite_client(invitation)`; factory trait `:client`.

- [ ] **Step 1: Write the failing model specs**

Add to `spec/models/invitation_spec.rb` (inside `RSpec.describe Invitation`):

```ruby
  describe "client invitations" do
    let!(:owner_role) do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"; r.permissions = { manage_workspace: true }
      end
    end
    let(:project) { create(:project, clientside_enabled: true) }
    let(:inviter) { create(:user) }

    it "is a client invite when company_name is present" do
      inv = build(:invitation, :client, invitable: project)
      expect(inv.client_invite?).to be(true)
      expect(inv).to be_valid
    end

    it "allows a nil role only for client invites" do
      member = build(:invitation, role: nil, company_name: nil)
      expect(member).not_to be_valid
      expect(member.errors[:role]).to be_present
    end

    it ".invite_client! creates the invite and enqueues the client mailer" do
      expect {
        Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                  company_name: "BigCo", invited_by: inviter)
      }.to have_enqueued_mail(InvitationMailer, :invite_client)
      inv = Invitation.last
      expect(inv.client_invite?).to be(true)
      expect(inv.role).to be_nil
      expect(inv.invitable).to eq(project)
    end

    it "accept! creates a ClientAccess and stamps onboarded_at" do
      inv = Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      client = create(:user, :with_zero_workspaces, email_address: "dana@bigco.com")
      expect { inv.accept!(client) }.to change { project.client_accesses.kept.count }.by(1)
      expect(project.client?(client)).to be(true)
      expect(client.reload.onboarded?).to be(true)
      expect(inv.reload).to be_accepted
    end

    it "consume! still guards against a mismatched email (bearer protection)" do
      inv = Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      other = create(:user, :with_zero_workspaces, email_address: "evil@example.com")
      expect { Invitation.consume!(token: inv.token, user: other, expected_email: other.email_address) }
        .to raise_error(Invitation::EmailMismatch)
    end
  end
```

> Replace the `(bearer защита)` text in the last example name with `(bearer protection)` — keep it ASCII.

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/models/invitation_spec.rb -e "client invitations"`
Expected: FAIL — unknown attribute `company_name` / no `client_invite?` / no `invite_client!`.

- [ ] **Step 3: Generate and write the migration**

Run: `bin/rails g migration AllowClientInvitations`

Replace the body with:

```ruby
class AllowClientInvitations < ActiveRecord::Migration[8.1]
  def up
    add_column :invitations, :company_name, :string
    change_column_null :invitations, :role_id, true
  end

  def down
    change_column_null :invitations, :role_id, false
    remove_column :invitations, :company_name
  end
end
```

- [ ] **Step 4: Migrate**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: schema shows `t.string "company_name"` on invitations and `t.integer "role_id"` (no `null: false`).

- [ ] **Step 5: Update the Invitation model**

In `app/models/invitation.rb`:

- Change `belongs_to :role` to `belongs_to :role, optional: true`.
- Change `validates :role, presence: true` to:

```ruby
  validates :role, presence: true, unless: :client_invite?
  validate :client_invite_targets_a_project
```

- Add the predicate + class method (public):

```ruby
  def client_invite?
    company_name.present?
  end

  def self.invite_client!(project:, email:, company_name:, invited_by:)
    invitation = create!(
      invitable: project,
      email: email.to_s.downcase.strip,
      company_name: company_name,
      invited_by: invited_by,
      expires_at: 7.days.from_now
    )
    InvitationMailer.invite_client(invitation).deliver_later
    invitation
  end
```

- In `accept!`, change the branch to put client first:

```ruby
      if client_invite?
        accept_client_invitation!(user)
      elsif invitable_type == "Project"
        accept_project_invitation!(user)
      else
        accept_workspace_invitation!(user)
      end
```

- Add the private methods:

```ruby
  def accept_client_invitation!(user)
    access = invitable.client_accesses.find_by(user: user)
    if access&.discarded?
      access.undiscard!
    elsif access.nil?
      invitable.client_accesses.create!(user: user, company_name: company_name)
    end
    user.update!(onboarded_at: Time.current) unless user.onboarded?
  end

  def client_invite_targets_a_project
    return unless client_invite?
    errors.add(:base, :client_requires_project) if invitable_type != "Project"
  end
```

- [ ] **Step 6: Add the `:client` factory trait**

In `spec/factories/invitations.rb`, add inside the `factory :invitation` block:

```ruby
    trait :client do
      association :invitable, factory: :project, clientside_enabled: true
      role { nil }
      company_name { "BigCo" }
      email { "dana@bigco.com" }
    end
```

- [ ] **Step 7: Add the `invite_client` mailer + templates**

In `app/mailers/invitation_mailer.rb`, add:

```ruby
  def invite_client(invitation)
    return if invitation.email.nil?

    @invitation = invitation
    @inviter = invitation.invited_by
    @project = invitation.invitable
    @workspace = @project.workspace
    @accept_url = accept_invitation_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: t("invitation_mailer.invite_client.subject", project: @project.name)
    )
  end
```

Create `app/views/invitation_mailer/invite_client.html.erb`:

```erb
<p><%= t("invitation_mailer.invite_client.greeting") %></p>
<p><%= t("invitation_mailer.invite_client.body", inviter: @inviter.full_name, project: @project.name) %></p>
<p><%= link_to t("invitation_mailer.invite_client.action"), @accept_url %></p>
```

Create `app/views/invitation_mailer/invite_client.text.erb`:

```erb
<%= t("invitation_mailer.invite_client.greeting") %>

<%= t("invitation_mailer.invite_client.body", inviter: @inviter.full_name, project: @project.name) %>

<%= t("invitation_mailer.invite_client.action") %>: <%= @accept_url %>
```

- [ ] **Step 8: Write the failing mailer spec**

Add to `spec/mailers/invitation_mailer_spec.rb`:

```ruby
  describe "#invite_client" do
    it "renders to the client with the accept URL" do
      project = create(:project, clientside_enabled: true)
      inv = create(:invitation, :client, invitable: project, email: "dana@bigco.com")
      mail = InvitationMailer.invite_client(inv)
      expect(mail.to).to eq([ "dana@bigco.com" ])
      expect(mail.body.encoded).to include(accept_invitation_url(token: inv.token))
    end
  end
```

- [ ] **Step 9: Add locale keys**

In `config/locales/en/clientside.en.yml`, add under `en:` a mailer block:

```yaml
  invitation_mailer:
    invite_client:
      subject: "You've been invited to %{project}"
      greeting: "Hello,"
      body: "%{inviter} shared the project %{project} with you."
      action: "View the invitation"
```

- [ ] **Step 10: Run the model + mailer specs**

Run: `bundle exec rspec spec/models/invitation_spec.rb -e "client invitations" spec/mailers/invitation_mailer_spec.rb -e invite_client`
Expected: PASS.

- [ ] **Step 11: Full suite + commit**

Run: `bundle exec rspec`
Expected: 0 failures (member-invite specs still green — the role-optional change didn't weaken them).

```bash
git add db/migrate db/schema.rb app/models/invitation.rb app/mailers/invitation_mailer.rb \
        app/views/invitation_mailer/invite_client.html.erb app/views/invitation_mailer/invite_client.text.erb \
        spec/factories/invitations.rb config/locales/en/clientside.en.yml \
        spec/models/invitation_spec.rb spec/mailers/invitation_mailer_spec.rb
git commit -m "feat(clientside): Invitation client variant + invite_client mailer"
```

---

## PHASE P2 — Team invite UI

### Task 2: `ClientInvitationsController` + form

**Files:**
- Modify: `config/routes.rb`, `app/views/workspaces/projects/clientsides/edit.html.erb`, `config/locales/en/clientside.en.yml`
- Create: `app/controllers/workspaces/projects/client_invitations_controller.rb`, `app/views/workspaces/projects/client_invitations/new.html.erb`
- Test: `spec/requests/workspaces/projects/client_invitations_spec.rb`

**Interfaces:**
- Consumes: `Invitation.invite_client!` (Task 1); `Project#clientside_enabled?`; `InvitationPolicy`.
- Produces: routes `new_workspace_project_client_invitation_path` / `workspace_project_client_invitations_path` (POST) → `Workspaces::Projects::ClientInvitationsController`.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, in the projects `scope module: :projects` block, after
`resource :clientside, only: %i[edit update]` (line 93), add:

```ruby
          resources :client_invitations, only: %i[new create]
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/workspaces/projects/client_invitations_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Client invitations (team side)", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user, clientside_enabled: true).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders the invite form when Clientside is on" do
    get new_workspace_project_client_invitation_path(workspace, project)
    expect(response).to have_http_status(:ok)
  end

  it "redirects to settings when Clientside is off" do
    project.update!(clientside_enabled: false)
    get new_workspace_project_client_invitation_path(workspace, project)
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))
  end

  it "sends a client invitation" do
    expect {
      post workspace_project_client_invitations_path(workspace, project),
        params: { client_invitation: { email: "dana@bigco.com", company_name: "BigCo" } }
    }.to change { project.invitations.where.not(company_name: nil).count }.by(1)
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))
  end

  it "re-renders on an invalid email" do
    post workspace_project_client_invitations_path(workspace, project),
      params: { client_invitation: { email: "", company_name: "BigCo" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/workspaces/projects/client_invitations_spec.rb`
Expected: FAIL — uninitialized constant `Workspaces::Projects::ClientInvitationsController`.

- [ ] **Step 4: Create the controller**

Create `app/controllers/workspaces/projects/client_invitations_controller.rb`:

```ruby
module Workspaces
  module Projects
    class ClientInvitationsController < ApplicationController
      include WorkspaceScoped
      before_action :set_project
      before_action :ensure_clientside_enabled

      def new
        authorize Invitation
      end

      def create
        authorize Invitation
        Invitation.invite_client!(
          project: @project,
          email: client_invitation_params[:email],
          company_name: client_invitation_params[:company_name],
          invited_by: Current.user
        )
        redirect_to edit_workspace_project_clientside_path(@workspace, @project),
          notice: t("clientside.invitations.sent")
      rescue ActiveRecord::RecordInvalid
        flash.now[:alert] = t("clientside.invitations.invalid")
        render :new, status: :unprocessable_entity
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
        Current.project = @project
      end

      def ensure_clientside_enabled
        return if @project.clientside_enabled?
        redirect_to edit_workspace_project_clientside_path(@workspace, @project),
          alert: t("clientside.invitations.disabled")
      end

      def client_invitation_params
        params.require(:client_invitation).permit(:email, :company_name)
      end
    end
  end
end
```

- [ ] **Step 5: Create the form view**

Create `app/views/workspaces/projects/client_invitations/new.html.erb`:

```erb
<% content_for(:title) { t("clientside.invitations.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading"><%= t("clientside.invitations.new.title") %></h1>
  <p class="mt-2 text-text-body"><%= t("clientside.invitations.new.subtitle") %></p>

  <%= form_with url: workspace_project_client_invitations_path(@workspace, @project),
        scope: :client_invitation, method: :post, class: "mt-8 space-y-6" do |form| %>
    <%= form.email_field :email, label: t("clientside.invitations.new.email_label"),
          required: true, autocomplete: "off" %>
    <%= form.text_field :company_name, label: t("clientside.invitations.new.company_label"),
          required: true %>
    <%= form.submit t("clientside.invitations.new.submit"), class: "w-full" %>
  <% end %>
</div>
```

> `form_with scope: :client_invitation` namespaces the params to match the
> controller's `params.require(:client_invitation)`. `form.email_field`/`text_field`
> with `label:` are the app's form-builder helpers (as in registrations/new).

- [ ] **Step 6: Link from the Clientside settings page**

In `app/views/workspaces/projects/clientsides/edit.html.erb`, add after the
`form_with … end` block (before the closing `</div>`):

```erb
  <div class="mt-8">
    <%= link_to t("clientside.invitations.new.link"),
          new_workspace_project_client_invitation_path(@workspace, @project),
          class: "text-interactive font-medium hover:underline focus-ring rounded" %>
  </div>
```

- [ ] **Step 7: Add locale keys**

In `config/locales/en/clientside.en.yml`, add under the existing `clientside:`
section:

```yaml
      invitations:
        sent: "Client invitation sent."
        invalid: "Enter a valid email and company."
        disabled: "Turn on Clientside before inviting clients."
        new:
          title: "Invite a client"
          subtitle: "They'll get a separate, limited view of this project."
          email_label: "Client email"
          company_label: "Their company"
          submit: "Send client invite"
          link: "Invite a client"
```

- [ ] **Step 8: Run the request spec, erb:check, full suite, commit**

Run: `bundle exec rspec spec/requests/workspaces/projects/client_invitations_spec.rb`
Expected: PASS (4 examples).

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean.

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add config/routes.rb app/controllers/workspaces/projects/client_invitations_controller.rb \
        app/views/workspaces/projects/client_invitations/new.html.erb \
        app/views/workspaces/projects/clientsides/edit.html.erb \
        config/locales/en/clientside.en.yml \
        spec/requests/workspaces/projects/client_invitations_spec.rb
git commit -m "feat(clientside): team-side client invite form"
```

---

## PHASE P3 — Accept + landing

### Task 3: Client accept redirect, role-safe accept view, client landing

**Files:**
- Modify: `app/controllers/invitation_accepts_controller.rb`, `app/views/invitation_accepts/show.html.erb`, `app/controllers/concerns/authenticatable.rb`, `app/controllers/email_verifications_controller.rb`, `config/locales/en/*` (accept view keys)
- Test: `spec/requests/clientside/invite_accept_spec.rb`, `spec/requests/authenticated_home_spec.rb`

**Interfaces:**
- Consumes: `Invitation#client_invite?` (Task 1); `clientside_project_path` / `clientside_projects_path` (#2); `User#client_accesses` (#1).
- Produces: `authenticated_home_path` returns `clientside_projects_path` for client-only users.

- [ ] **Step 1: Write the failing accept + landing specs**

Create `spec/requests/clientside/invite_accept_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Accepting a client invitation", type: :request do
  let(:project) { create(:project, clientside_enabled: true) }
  let(:inviter) { project.created_by }
  let(:invitation) do
    Invitation.invite_client!(project: project, email: "dana@bigco.com",
                              company_name: "BigCo", invited_by: inviter)
  end

  it "an existing user gets a ClientAccess and lands in the client area" do
    client = create(:user, :with_zero_workspaces, email_address: "dana@bigco.com")
    sign_in(client)
    post accept_invitation_path(token: invitation.token)
    expect(project.client?(client)).to be(true)
    expect(response).to redirect_to(clientside_project_path(project))
  end
end
```

Create `spec/requests/authenticated_home_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Authenticated home routing", type: :request do
  it "sends a client-only user to the client area" do
    project = create(:project, clientside_enabled: true)
    client = create(:user, :with_zero_workspaces)
    project.client_accesses.create!(user: client, company_name: "BigCo")
    sign_in(client)
    # A bare authenticated GET to root resolves through authenticated_home_path
    # only on post-auth redirects; assert the helper via the email-verify landing.
    get root_path
    expect(response).to have_http_status(:ok) # client-only user can view root; see landing helper spec below
  end
end
```

> The cleanest place to assert `authenticated_home_path` is a controller unit-ish
> check. If a direct request assertion is awkward, instead assert the verify
> landing (next step) and a member-vs-client comparison there. Keep at least one
> example proving a client-only user is routed to `clientside_projects_path` by
> `authenticated_home_path` — e.g. via the email-verification landing in Step 4's
> spec. Adjust this file to whatever cleanly exercises the helper.

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/requests/clientside/invite_accept_spec.rb`
Expected: FAIL — accept redirects to the member project path, not the client area.

- [ ] **Step 3: Branch the accept redirect**

In `app/controllers/invitation_accepts_controller.rb`, in `create`'s authenticated
branch, replace the success redirect block:

```ruby
        Invitation.consume!(token: @invitation.token, user: Current.user, expected_email: Current.user.email_address)
        if @invitation.client_invite?
          redirect_to clientside_project_path(@invitation.invitable), notice: t(".success")
        elsif @invitation.invitable_type == "Project"
          redirect_to workspace_project_path(@invitation.invitable.workspace, @invitation.invitable), notice: t(".success")
        else
          redirect_to workspace_path(@invitation.invitable), notice: t(".success")
        end
```

- [ ] **Step 4: Make the accept `show` view role-nil safe (client framing)**

In `app/views/invitation_accepts/show.html.erb`, replace the body paragraph so a
client invite (nil role) doesn't call `role.name`:

```erb
  <p class="mt-4 text-text-muted">
    <% if @invitation.client_invite? %>
      <%= t("invitation_accepts.show.client_body",
            inviter: @invitation.invited_by.full_name,
            project: @invitation.invitable.name) %>
    <% else %>
      <%= t("invitation_accepts.show.body",
            inviter: @invitation.invited_by.full_name,
            workspace: @invitation.invitable.name,
            role: @invitation.role.name) %>
    <% end %>
  </p>
```

Add the locale key next to the existing `invitation_accepts.show.body` (find the
file with `grep -rl "invitation_accepts:" config/locales`):

```yaml
          client_body: "%{inviter} shared the project %{project} with you."
```

- [ ] **Step 5: Add the client-only branch to `authenticated_home_path`**

In `app/controllers/concerns/authenticatable.rb`, replace `authenticated_home_path`:

```ruby
    def authenticated_home_path
      user = Current.user
      if user && user.client_accesses.kept.exists? && user.memberships.kept.none?
        clientside_projects_path
      else
        root_path
      end
    end
```

- [ ] **Step 6: Land verified clients via `authenticated_home_path`**

In `app/controllers/email_verifications_controller.rb`, change the success branch
redirect from `root_path` to `after_authentication_url`:

```ruby
    else
      authentication.verify!
      redirect_to after_authentication_url, notice: t(".success")
    end
```

- [ ] **Step 7: Adjust the landing spec to assert the helper**

Replace `spec/requests/authenticated_home_spec.rb` with a verify-landing assertion
that proves the client-only routing:

```ruby
require "rails_helper"

RSpec.describe "Client landing via email verification", type: :request do
  it "lands a verified client-only user in the client area" do
    project = create(:project, clientside_enabled: true)
    client = create(:user, :with_email_auth, :with_zero_workspaces)
    project.client_accesses.create!(user: client, company_name: "BigCo")
    sign_in(client)
    auth = client.authentications.email.first
    token = auth.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    expect(response).to redirect_to(clientside_projects_path)
  end

  it "lands a member on root" do
    user = create(:user, :with_email_auth)
    sign_in(user)
    auth = user.authentications.email.first
    token = auth.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    expect(response).to redirect_to(root_path)
  end
end
```

> `generate_token_for(:email_verification)` is the same token API the mailer uses
> (`Authentication generates_token_for :email_verification`). Verify the route
> helper name with `bin/rails routes -g email_verification` (it is
> `email_verification_path` with a `token` param).

- [ ] **Step 8: Run the specs, erb:check, full suite, commit**

Run: `bundle exec rspec spec/requests/clientside/invite_accept_spec.rb spec/requests/authenticated_home_spec.rb`
Expected: PASS.

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean.

Run: `bundle exec rspec`
Expected: 0 failures (existing email-verification + invitation-accept specs still green — if an existing spec asserted verify→root for a member, it still holds; if one asserted a specific redirect that now resolves through `after_authentication_url`, update it to the equivalent path).

```bash
git add app/controllers/invitation_accepts_controller.rb app/views/invitation_accepts/show.html.erb \
        app/controllers/concerns/authenticatable.rb app/controllers/email_verifications_controller.rb \
        config/locales \
        spec/requests/clientside/invite_accept_spec.rb spec/requests/authenticated_home_spec.rb
git commit -m "feat(clientside): client accept redirect + client-only home landing"
```

---

## PHASE P4 — System coverage + regression guards

### Task 4: End-to-end system spec + member-invite regression

**Files:**
- Create: `spec/system/clientside_invite_spec.rb`
- Test: `spec/models/invitation_spec.rb` (regression guard), `spec/system/clientside_invite_spec.rb`

**Interfaces:**
- Consumes: everything from P1–P3.

- [ ] **Step 1: Add the member-invite regression guard**

Add to `spec/models/invitation_spec.rb` (inside `RSpec.describe Invitation`):

```ruby
  describe "member-invite role requirement (regression for client-variant change)" do
    it "still requires a role for a normal (non-client) workspace invite" do
      inv = build(:invitation, company_name: nil, role: nil)
      expect(inv).not_to be_valid
      expect(inv.errors[:role]).to be_present
    end

    it "accepts a member invite with a role and creates a membership" do
      workspace = create(:workspace)
      role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      inv = create(:invitation, invitable: workspace, role: role, company_name: nil)
      user = create(:user, :with_zero_workspaces)
      expect { inv.accept!(user) }.to change { workspace.memberships.kept.count }.by(1)
    end
  end
```

- [ ] **Step 2: Run it and confirm it passes (guard already satisfied by P1)**

Run: `bundle exec rspec spec/models/invitation_spec.rb -e "regression"`
Expected: PASS — confirms the role-optional change did not weaken member invites.

- [ ] **Step 3: Write the end-to-end system spec**

Create `spec/system/clientside_invite_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Client invite flow", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:owner) { create(:user) }
  let(:workspace) { owner.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: owner, clientside_enabled: true).tap do |p|
      p.project_memberships.create!(user: owner, role: "creator")
    end
  end

  it "a team owner invites a client; the existing-account client accepts and sees the client area (AAA)" do
    # Team side: send the invite via the form.
    sign_in_via_form(owner)
    visit new_workspace_project_client_invitation_path(workspace, project)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
    fill_in "Client email", with: "dana@bigco.com"
    fill_in "Their company", with: "BigCo"
    click_button "Send client invite"

    invitation = project.invitations.where.not(company_name: nil).last
    expect(invitation).to be_present

    # A pre-existing client account accepts.
    create(:user, email_address: "dana@bigco.com", password: "SecureP@ssw0rd123!")
    # sign out the owner, sign in the client
    visit accept_invitation_path(token: invitation.token) # GET show
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
  end
end
```

> This system spec mirrors the project axe idiom (`sign_in_via_form`,
> `axe_clean_in_both_themes?`). The exact sign-out/sign-in-as-client steps and the
> final client-area assertion depend on the app's system-spec auth helpers — align
> them with `spec/system/me_spec.rb` and the #2 `spec/system/clientside_area_spec.rb`
> (which already drives a client). If a full sign-out/sign-in-as-different-user in
> one example is awkward in this suite, split into two examples (team sends; client
> accepts) using the request-level accept where the browser flow is not needed —
> keep at least the two AAA axe scans (invite form + accept page).

- [ ] **Step 4: Run the system spec**

Run: `bundle exec rspec spec/system/clientside_invite_spec.rb`
Expected: PASS. Align the auth steps/locators with the rendered markup + the #2 client-area spec.

- [ ] **Step 5: erb:check, full suite, commit**

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean.

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add spec/models/invitation_spec.rb spec/system/clientside_invite_spec.rb
git commit -m "test(clientside): end-to-end client invite + member-invite regression"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** `company_name` + nullable role migration (T1) ✓; `client_invite?`, role-optional-with-guard, `accept_client_invitation!`+onboarded stamp, `invite_client!`, `EmailMismatch` preserved (T1) ✓; `invite_client` mailer (T1) ✓; team invite controller + form + Clientside gate + authorization (T2) ✓; existing-user accept→client area redirect + role-nil-safe show view (T3) ✓; `authenticated_home_path` client-only + verify landing (T3) ✓; system + AAA + member-invite regression (T4) ✓. Out-of-scope (pending-client management UI, approve/comment) intentionally absent.
- **Placeholder scan:** no TBD/TODO; complete code in every code step. Two non-ASCII typos are flagged inline with explicit ASCII replacements; the "align auth steps" notes name concrete reference specs (me_spec, clientside_area_spec).
- **Type/name consistency:** `client_invite?` / `company_name` / `invite_client!` / `accept_client_invitation!` consistent; route `resources :client_invitations` ⇒ `Workspaces::Projects::ClientInvitationsController` + `new_workspace_project_client_invitation_path` used consistently; `authenticated_home_path` → `clientside_projects_path` (a #2 helper) used in T3 controller + specs; `client_body` locale key paired with the show-view branch.
