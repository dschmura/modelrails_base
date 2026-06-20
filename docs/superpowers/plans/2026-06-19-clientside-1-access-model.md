# Clientside #1 — Client Access Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the foundation for external project clients — a `ClientAccess` model (separate from `Membership`), a per-project `clientside_enabled` toggle, and the access query later sub-projects build on.

**Architecture:** A client is a regular `User` whose *external* relationship to a project is a `ClientAccess` row (not a `Membership`), so clients never enter workspace policies or member-seat counting. A per-project boolean gates whether client access may exist; a dedicated settings controller toggles it (mirroring the existing `Workspaces::Projects::ToolsController`).

**Tech Stack:** Rails 8.1, Ruby 4.0.4, RSpec, SQLite, modelrails_ui (settings UI).

## Global Constraints

- All user-facing text via I18n locale keys — no hardcoded strings.
- Every controller action calls Pundit `authorize`; the toggle authorizes `@project, :update?` (reuses `ProjectPolicy#update?` = `manage_projects`).
- Access the signed-in user via `Current.user`; the active workspace/project via `Current.workspace` / `Current.project`.
- RESTful routes only (`resource :x` ⇒ plural `XsController`).
- modelrails_ui + semantic AAA tokens; `focus-ring` not `focus:ring-*`; WCAG 2.2 AAA proven in CI.
- TDD: failing spec first, watch it fail, minimal implementation, watch it pass, commit.
- Run Ruby/Rails through the toolchain: `bundle exec rspec` (mise auto-activates; else prefix `mise exec --`); `bin/rails` for migrations. Migrate dev then `bin/rails db:test:prepare`; commit `db/schema.rb`.
- `rake erb:check` (herb-lint) runs only on push/CI, NOT in `bundle exec rspec`. Partials must take **strict locals** and must NOT read controller instance variables (`@workspace` etc.) — pass them as locals. Run `mise exec -- bundle exec rake erb:check` before the phase's final commit.
- Conventional Commits; **never** a `Co-Authored-By` / AI-attribution line. Full suite green before each phase's final commit.

---

## File Structure

Created:

- `db/migrate/<ts>_add_clientside_enabled_to_projects.rb`
- `db/migrate/<ts>_create_client_accesses.rb`
- `app/models/client_access.rb`
- `spec/factories/client_accesses.rb`
- `app/controllers/workspaces/projects/clientside_controller.rb`
- `app/views/workspaces/projects/clientside/edit.html.erb`
- `config/locales/en/clientside.en.yml`
- Specs: `spec/models/client_access_spec.rb`, additions to `spec/models/project_spec.rb` + `spec/models/user_spec.rb`, `spec/requests/workspaces/projects/clientside_spec.rb`

Modified:

- `app/models/project.rb` — `has_many :client_accesses`, `client?`
- `app/models/user.rb` — `has_many :client_accesses`, `client_of?`
- `config/routes.rb` — `resource :clientside` under the projects scope
- `app/views/workspaces/projects/show.html.erb` — settings nav link

---

## PHASE P1 — Model layer

### Task 1: Migrations, ClientAccess model, associations, factory

**Files:**
- Create: `db/migrate/<ts>_add_clientside_enabled_to_projects.rb`
- Create: `db/migrate/<ts>_create_client_accesses.rb`
- Create: `app/models/client_access.rb`
- Create: `spec/factories/client_accesses.rb`
- Modify: `app/models/project.rb`, `app/models/user.rb`
- Test: `spec/models/client_access_spec.rb`, `spec/models/project_spec.rb`, `spec/models/user_spec.rb`

**Interfaces:**
- Produces:
  - `projects.clientside_enabled` (boolean, default false); `Project#clientside_enabled?`, `Project#client?(user)` → Boolean, `Project#client_accesses`.
  - `client_accesses` table (`project_id`, `user_id`, `company_name`, `discarded_at`, timestamps; unique `(project_id, user_id)`).
  - `ClientAccess` model: `belongs_to :project`, `belongs_to :user`, `include Discardable`; validates `company_name` presence + `(project, user)` uniqueness + `project.clientside_enabled?` on create.
  - `User#client_accesses`, `User#client_of?(project)` → Boolean.
  - Factory `:client_access` (project with `clientside_enabled: true`, user, `company_name`).

- [ ] **Step 1: Write the failing model specs**

Create `spec/models/client_access_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ClientAccess, type: :model do
  it "is valid with a company name on a clientside-enabled project" do
    access = build(:client_access)
    expect(access).to be_valid
  end

  it "requires a company name" do
    access = build(:client_access, company_name: "")
    expect(access).not_to be_valid
    expect(access.errors[:company_name]).to be_present
  end

  it "is unique per (project, user)" do
    existing = create(:client_access)
    dup = build(:client_access, project: existing.project, user: existing.user)
    expect(dup).not_to be_valid
  end

  it "cannot be created when the project's Clientside is disabled" do
    project = create(:project, clientside_enabled: false)
    access = build(:client_access, project: project)
    expect(access).not_to be_valid
    expect(access.errors[:base]).to be_present
  end

  it "supports soft-deletion via Discardable" do
    access = create(:client_access)
    access.discard!
    expect(access).to be_discarded
    expect(ClientAccess.kept).not_to include(access)
  end

  it "does not consume a workspace member seat" do
    project = create(:project, clientside_enabled: true)
    workspace = project.workspace
    before = workspace.memberships.kept.count
    client = create(:user)
    described_class.create!(project: project, user: client, company_name: "BigCo")
    expect(workspace.memberships.kept.count).to eq(before)
    expect(workspace.users).not_to include(client)
  end
end
```

Add to `spec/models/project_spec.rb` (inside `RSpec.describe Project`):

```ruby
  describe "clientside access" do
    it "#client? is true for a user with a kept client access" do
      access = create(:client_access)
      expect(access.project.client?(access.user)).to be(true)
    end

    it "#client? is false for a user without client access" do
      project = create(:project, clientside_enabled: true)
      expect(project.client?(create(:user))).to be(false)
    end
  end
```

Add to `spec/models/user_spec.rb` (inside `RSpec.describe User`):

```ruby
  describe "#client_of?" do
    it "is true for a project the user has client access to" do
      access = create(:client_access)
      expect(access.user.client_of?(access.project)).to be(true)
    end

    it "is false otherwise" do
      project = create(:project, clientside_enabled: true)
      expect(create(:user).client_of?(project)).to be(false)
    end
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/models/client_access_spec.rb`
Expected: FAIL — uninitialized constant `ClientAccess` / factory not registered.

- [ ] **Step 3: Generate and write the migrations**

Run: `bin/rails g migration AddClientsideEnabledToProjects` then `bin/rails g migration CreateClientAccesses`

Replace the first migration body with:

```ruby
class AddClientsideEnabledToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :clientside_enabled, :boolean, null: false, default: false
  end
end
```

Replace the second migration body with:

```ruby
class CreateClientAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :client_accesses do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :company_name, null: false
      t.datetime :discarded_at
      t.timestamps
    end

    add_index :client_accesses, [ :project_id, :user_id ], unique: true
    add_index :client_accesses, :discarded_at
  end
end
```

- [ ] **Step 4: Migrate**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: `db/schema.rb` shows `clientside_enabled` on `projects` and the `client_accesses` table with both indexes.

- [ ] **Step 5: Create the ClientAccess model**

Create `app/models/client_access.rb`:

```ruby
# An external client's scoped access to a single project (Clientside). A client
# is a regular User; this row is the EXTERNAL relationship — deliberately NOT a
# Membership, so clients never enter workspace policies or member-seat counting.
class ClientAccess < ApplicationRecord
  include Discardable

  belongs_to :project
  belongs_to :user

  validates :company_name, presence: true
  validates :user_id, uniqueness: { scope: :project_id }
  validate :project_clientside_enabled, on: :create

  private

  def project_clientside_enabled
    return if project&.clientside_enabled?
    errors.add(:base, :clientside_disabled)
  end
end
```

- [ ] **Step 6: Add associations + queries to Project and User**

In `app/models/project.rb`, add to the association block (near `has_many :resources`):

```ruby
  has_many :client_accesses, dependent: :destroy
```

and add a public method:

```ruby
  def client?(user)
    client_accesses.kept.exists?(user: user)
  end
```

In `app/models/user.rb`, add to the association block:

```ruby
  has_many :client_accesses, dependent: :destroy
```

and add a public method:

```ruby
  def client_of?(project)
    client_accesses.kept.exists?(project: project)
  end
```

- [ ] **Step 7: Create the factory**

Create `spec/factories/client_accesses.rb`:

```ruby
FactoryBot.define do
  factory :client_access do
    project { association(:project, clientside_enabled: true) }
    user
    company_name { "BigCo" }
  end
end
```

- [ ] **Step 8: Add the i18n error message**

Create `config/locales/en/clientside.en.yml` (accumulates Clientside keys; the
toggle keys come in Task 2):

```yaml
en:
  activerecord:
    errors:
      models:
        client_access:
          attributes:
            base:
              clientside_disabled: "Clientside must be enabled for this project before adding clients."
```

- [ ] **Step 9: Run the model specs and confirm they pass**

Run: `bundle exec rspec spec/models/client_access_spec.rb spec/models/project_spec.rb spec/models/user_spec.rb`
Expected: PASS.

- [ ] **Step 10: Run the full suite, then commit**

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add db/migrate db/schema.rb app/models/client_access.rb \
        app/models/project.rb app/models/user.rb \
        spec/factories/client_accesses.rb config/locales/en/clientside.en.yml \
        spec/models/client_access_spec.rb spec/models/project_spec.rb spec/models/user_spec.rb
git commit -m "feat(clientside): ClientAccess model + per-project clientside_enabled"
```

---

## PHASE P2 — Per-project Clientside toggle

### Task 2: Clientside settings controller + view

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/workspaces/projects/clientside_controller.rb`
- Create: `app/views/workspaces/projects/clientside/edit.html.erb`
- Modify: `config/locales/en/clientside.en.yml`
- Modify: `app/views/workspaces/projects/show.html.erb`
- Test: `spec/requests/workspaces/projects/clientside_spec.rb`

**Interfaces:**
- Consumes: `Project#clientside_enabled` (Task 1); `ProjectPolicy#update?`.
- Produces: routes `edit_workspace_project_clientside_path` / `workspace_project_clientside_path` (PATCH) → `Workspaces::Projects::ClientsideController`.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `scope module: :projects do … end` block, after
the `resource :tools, only: %i[edit update]` line, add:

```ruby
          resource :clientside, only: %i[edit update]
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/workspaces/projects/clientside_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Project Clientside settings", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders the toggle form" do
    get edit_workspace_project_clientside_path(workspace, project)
    expect(response).to have_http_status(:ok)
  end

  it "enables Clientside" do
    patch workspace_project_clientside_path(workspace, project),
      params: { project: { clientside_enabled: "1" } }
    expect(project.reload.clientside_enabled?).to be(true)
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))
  end

  context "as a workspace member without manage_projects" do
    let(:viewer) { create(:user) }
    let!(:viewer_role) do
      Role.find_or_create_by!(slug: "viewer", workspace_id: nil) do |r|
        r.name = "Viewer"
        r.permissions = {}
      end
    end

    before do
      workspace.memberships.create!(user: viewer, role: viewer_role)
      project.project_memberships.create!(user: viewer, role: "viewer")
      sign_in(viewer)
    end

    it "denies access (redirect, unchanged)" do
      patch workspace_project_clientside_path(workspace, project),
        params: { project: { clientside_enabled: "1" } }
      expect(response).to have_http_status(:redirect)
      expect(project.reload.clientside_enabled?).to be(false)
    end
  end
end
```

> `user.workspaces.sole` is the auto-created personal workspace under the default
> `:personal` test posture. The viewer context proves authorization is enforced.

- [ ] **Step 3: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/workspaces/projects/clientside_spec.rb`
Expected: FAIL — uninitialized constant `Workspaces::Projects::ClientsideController`.

- [ ] **Step 4: Create the controller**

Create `app/controllers/workspaces/projects/clientside_controller.rb`:

```ruby
module Workspaces
  module Projects
    class ClientsideController < ApplicationController
      include WorkspaceScoped
      before_action :set_project

      def edit
        authorize @project, :update?
      end

      def update
        authorize @project, :update?
        @project.update!(clientside_params)
        redirect_to edit_workspace_project_clientside_path(@workspace, @project),
          notice: t("clientside.settings.saved")
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
        Current.project = @project
      end

      def clientside_params
        params.require(:project).permit(:clientside_enabled)
      end
    end
  end
end
```

- [ ] **Step 5: Create the view**

Create `app/views/workspaces/projects/clientside/edit.html.erb`:

```erb
<% content_for(:title) { t("clientside.settings.title") } %>
<div class="max-w-2xl mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading"><%= t("clientside.settings.title") %></h1>
  <p class="mt-2 text-text-body"><%= t("clientside.settings.subtitle") %></p>

  <%= form_with model: @project,
        url: workspace_project_clientside_path(@workspace, @project),
        method: :patch, class: "mt-8 space-y-6" do |form| %>
    <%= form.check_box :clientside_enabled, label: t("clientside.settings.toggle_label") %>
    <%= form.submit t("clientside.settings.save"), class: "w-full" %>
  <% end %>
</div>
```

> `TailwindFormBuilder#check_box` accepts a `label:` and emits the auto hidden
> field (so unchecking submits `"0"` → false). Verify against an existing
> `form.check_box` usage if the signature differs.

- [ ] **Step 6: Link the settings page from the project**

In `app/views/workspaces/projects/show.html.erb`, inside the existing
`policy(@project).update?` block (next to the Edit/Tools links), add:

```erb
      <%= link_to t("clientside.settings.link"), edit_workspace_project_clientside_path(@workspace, @project),
            class: "min-h-[var(--form-input-height)] flex items-center px-4 py-2 rounded-md border border-border
                    text-text-body hover:border-interactive focus-ring" %>
```

- [ ] **Step 7: Add the toggle locale keys**

In `config/locales/en/clientside.en.yml`, add a `clientside:` top-level section
(under `en:`, alongside the existing `activerecord:` section):

```yaml
    clientside:
      settings:
        title: "Client access"
        subtitle: "Clientside gives external clients a separate, limited view of this project."
        toggle_label: "Turn on Clientside for this project"
        save: "Save"
        saved: "Client access updated."
        link: "Client access"
```

- [ ] **Step 8: Run the request spec and confirm it passes**

Run: `bundle exec rspec spec/requests/workspaces/projects/clientside_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 9: Lint, full suite, commit**

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean (the view uses `@project`/`@workspace` only in a top-level
template, not a partial — allowed).

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add config/routes.rb app/controllers/workspaces/projects/clientside_controller.rb \
        app/views/workspaces/projects/clientside/edit.html.erb \
        app/views/workspaces/projects/show.html.erb \
        config/locales/en/clientside.en.yml \
        spec/requests/workspaces/projects/clientside_spec.rb
git commit -m "feat(clientside): per-project Clientside settings toggle"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** `clientside_enabled` column (T1) ✓; `ClientAccess` model + validations incl. the clientside-disabled create guard (T1) ✓; `Project#client?` / `User#client_of?` (T1) ✓; capacity-exclusion guarantee (T1 spec) ✓; per-project toggle controller + view + authorization (T2) ✓; settings link (T2) ✓. Out-of-scope items (client area, sharing, invite flow, Company model) intentionally absent.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code. The one "verify against existing usage" note (form.check_box label) names the concrete check.
- **Type/name consistency:** `clientside_enabled` (column/reader/param) consistent; `ClientAccess`, `client_accesses`, `company_name` consistent; `client?(user)` / `client_of?(project)` consistent; `project_clientside_enabled` validation pairs with the `clientside_disabled` i18n key; route `resource :clientside` → `ClientsideController` + `edit_workspace_project_clientside_path` used consistently in controller, view, and specs.
```
