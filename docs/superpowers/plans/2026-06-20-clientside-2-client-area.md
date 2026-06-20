# Clientside #2 — Client Area + Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a team share individual project resources to the client side and let an external client view those shared items in a separate, read-only client area.

**Architecture:** A `shared_with_client` flag on `Resource` (visible to clients only when also published) drives a `MeController`-style `Clientside::` namespace — authenticated but NOT workspace-scoped — that resolves projects via the current user's `ClientAccess` (from #1), gates on `clientside_enabled?`, and renders a focused `clientside` layout. No `Current.workspace`, no workspace chrome, no member data.

**Tech Stack:** Rails 8.1, Ruby 4.0.4, RSpec, Capybara + Playwright (axe), modelrails_ui, SQLite.

## Global Constraints

- All user-facing text via I18n locale keys — no hardcoded strings.
- Controllers that act on a resource enforce Pundit `authorize`; self-scoped client-area reads need no policy (like `MeController`) — access is enforced by the `ClientAccess` lookup + `clientside_enabled?` gate.
- Access the signed-in user via `Current.user`. The client area sets `Current.project` for the loaded project but **NEVER** `Current.workspace`, and never includes `WorkspaceScoped`.
- Client-area controllers MUST call `skip_onboarding_requirement` (the #362 guard would otherwise funnel an `onboarded_at: nil` client into the onboarding wizard under `:none`).
- RESTful routes only (`resource(s) :x` ⇒ plural controller).
- modelrails_ui + semantic AAA tokens (`bg-surface-raised`, `text-text-*`, `border-border`); `focus-ring` not `focus:ring-*`; WCAG 2.2 AAA proven in CI, both themes.
- A resource is client-visible iff `shared_with_client? && published?`.
- TDD: failing spec first, watch it fail, minimal implementation, watch it pass, commit.
- Toolchain: `bundle exec rspec` (mise auto-activates; else `mise exec --`); `bin/rails` for migrations; `bin/rails db:test:prepare` after migrating; commit `db/schema.rb`.
- `rake erb:check` runs only on push/CI; run `mise exec -- bundle exec rake erb:check` before each phase's final commit. Partials use strict locals and must not read controller ivars.
- Conventional Commits; **never** a `Co-Authored-By` / AI-attribution line. Full suite green before each phase's final commit.

---

## File Structure

Created:

- `db/migrate/<ts>_add_shared_with_client_to_resources.rb`
- `app/controllers/clientside/base_controller.rb`
- `app/controllers/clientside/projects_controller.rb`
- `app/controllers/clientside/projects/resources_controller.rb`
- `app/views/layouts/clientside.html.erb`
- `app/views/clientside/projects/index.html.erb`
- `app/views/clientside/projects/show.html.erb`
- `app/views/clientside/projects/resources/show.html.erb`
- `config/locales/en/clientside.en.yml` additions (file exists from #1)
- Specs: `spec/models/resource_spec.rb` + `spec/models/project_spec.rb` additions, `spec/requests/workspaces/projects/resource_sharing_spec.rb`, `spec/requests/clientside/projects_spec.rb`, `spec/requests/clientside/projects/resources_spec.rb`, `spec/system/clientside_area_spec.rb`

Modified:

- `app/models/resource.rb` — `client_visible?`
- `app/models/project.rb` — `client_visible_resources`
- `app/controllers/workspaces/projects/resources_controller.rb` — `resource_params` clientside-guarded
- `app/views/workspaces/projects/resources/edit.html.erb` — share checkbox
- `config/routes.rb` — `namespace :clientside`

---

## PHASE P1 — Sharing flag (team side)

### Task 1: `shared_with_client` + member-side sharing control

**Files:**
- Create: `db/migrate/<ts>_add_shared_with_client_to_resources.rb`
- Modify: `app/models/resource.rb`, `app/models/project.rb`, `app/controllers/workspaces/projects/resources_controller.rb`, `app/views/workspaces/projects/resources/edit.html.erb`, `config/locales/en/clientside.en.yml`
- Test: `spec/models/resource_spec.rb`, `spec/models/project_spec.rb`, `spec/requests/workspaces/projects/resource_sharing_spec.rb`

**Interfaces:**
- Produces: `resources.shared_with_client` (boolean, default false); `Resource#client_visible?` → Boolean; `Project#client_visible_resources` → ActiveRecord::Relation (kept, published, shared, position order).

- [ ] **Step 1: Write the failing model specs**

Add to `spec/models/resource_spec.rb` (inside `RSpec.describe Resource`):

```ruby
  describe "#client_visible?" do
    it "is true when shared and published" do
      r = create(:resource, status: "published", shared_with_client: true)
      expect(r.client_visible?).to be(true)
    end

    it "is false when shared but still a draft" do
      r = create(:resource, status: "draft", shared_with_client: true)
      expect(r.client_visible?).to be(false)
    end

    it "is false when published but not shared" do
      r = create(:resource, status: "published", shared_with_client: false)
      expect(r.client_visible?).to be(false)
    end
  end
```

Add to `spec/models/project_spec.rb` (inside `RSpec.describe Project`):

```ruby
  describe "#client_visible_resources" do
    it "returns only kept, published, shared resources" do
      project = create(:project)
      visible = create(:resource, project: project, status: "published", shared_with_client: true)
      create(:resource, project: project, status: "draft", shared_with_client: true)
      create(:resource, project: project, status: "published", shared_with_client: false)
      expect(project.client_visible_resources).to eq([ visible ])
    end
  end
```

> If the `:resource` factory does not accept `status`/`shared_with_client`/`project`
> directly, set them via the factory's existing attributes — check
> `spec/factories/resources.rb` first and pass what it supports (it builds a
> `Document` resourceable). Add a `shared_with_client` to the factory only if
> needed; the column defaults to false.

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/models/resource_spec.rb -e client_visible? spec/models/project_spec.rb -e client_visible_resources`
Expected: FAIL — unknown attribute `shared_with_client` / no `client_visible?`.

- [ ] **Step 3: Generate and write the migration**

Run: `bin/rails g migration AddSharedWithClientToResources`

Replace the body with:

```ruby
class AddSharedWithClientToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :shared_with_client, :boolean, null: false, default: false
  end
end
```

- [ ] **Step 4: Migrate**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: `db/schema.rb` shows `t.boolean "shared_with_client", default: false, null: false` on `resources`.

- [ ] **Step 5: Implement the model methods**

In `app/models/resource.rb`, add a public method (near the existing scopes):

```ruby
  def client_visible?
    shared_with_client? && published?
  end
```

In `app/models/project.rb`, add a public method:

```ruby
  def client_visible_resources
    resources.kept.published.where(shared_with_client: true).positioned
  end
```

> `published` and `positioned` are existing `Resource` scopes; `kept` comes from
> `Discardable`. No new `Resource` scope is added (YAGNI — the one query lives in
> `client_visible_resources`).

- [ ] **Step 6: Run the model specs and confirm they pass**

Run: `bundle exec rspec spec/models/resource_spec.rb -e client_visible? spec/models/project_spec.rb -e client_visible_resources`
Expected: PASS.

- [ ] **Step 7: Write the failing member-side sharing request spec**

Create `spec/requests/workspaces/projects/resource_sharing_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Resource client-sharing (team side)", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end
  let(:resource) { create(:resource, project: project, status: "published") }

  before { sign_in(user) }

  it "shows the share checkbox on edit only when Clientside is enabled" do
    project.update!(clientside_enabled: false)
    get edit_workspace_project_resource_path(workspace, project, resource)
    expect(response.body).not_to include("resource_shared_with_client")

    project.update!(clientside_enabled: true)
    get edit_workspace_project_resource_path(workspace, project, resource)
    expect(response.body).to include("resource_shared_with_client")
  end

  it "sets shared_with_client when Clientside is enabled" do
    project.update!(clientside_enabled: true)
    patch workspace_project_resource_path(workspace, project, resource),
      params: { resource: { title: resource.title, status: "published", shared_with_client: "1" } }
    expect(resource.reload.shared_with_client?).to be(true)
  end

  it "ignores shared_with_client when Clientside is disabled" do
    project.update!(clientside_enabled: false)
    patch workspace_project_resource_path(workspace, project, resource),
      params: { resource: { title: resource.title, status: "published", shared_with_client: "1" } }
    expect(resource.reload.shared_with_client?).to be(false)
  end
end
```

- [ ] **Step 8: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/workspaces/projects/resource_sharing_spec.rb`
Expected: FAIL — checkbox absent / flag not set.

- [ ] **Step 9: Guard the controller param**

In `app/controllers/workspaces/projects/resources_controller.rb`, replace
`resource_params`:

```ruby
      def resource_params
        permitted = [ :title, :status ]
        permitted << :shared_with_client if @project&.clientside_enabled?
        params.require(:resource).permit(*permitted)
      end
```

- [ ] **Step 10: Add the edit-form checkbox**

In `app/views/workspaces/projects/resources/edit.html.erb`, add immediately
before the `<%= submit_tag … %>` line:

```erb
    <% if @project.clientside_enabled? %>
      <div>
        <%= hidden_field_tag "resource[shared_with_client]", "0" %>
        <label class="flex items-center gap-2 text-sm text-text-body">
          <%= check_box_tag "resource[shared_with_client]", "1", @resource.shared_with_client?,
                id: "resource_shared_with_client", class: "focus-ring rounded" %>
          <%= t("workspaces.projects.resources.edit.share_with_client") %>
        </label>
      </div>
    <% end %>
```

- [ ] **Step 11: Add the locale key**

In `config/locales/en/clientside.en.yml`, add under `en:` (alongside the existing
`activerecord:` and `clientside:` sections) into the existing
`workspaces.projects.resources.edit` namespace — add a NEW top-level `en:` entry
merged by Rails:

```yaml
  workspaces:
    projects:
      resources:
        edit:
          share_with_client: "Share with the client side"
```

- [ ] **Step 12: Run the request spec, then erb:check, full suite, commit**

Run: `bundle exec rspec spec/requests/workspaces/projects/resource_sharing_spec.rb`
Expected: PASS (3 examples).

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean.

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add db/migrate db/schema.rb app/models/resource.rb app/models/project.rb \
        app/controllers/workspaces/projects/resources_controller.rb \
        app/views/workspaces/projects/resources/edit.html.erb \
        config/locales/en/clientside.en.yml \
        spec/models/resource_spec.rb spec/models/project_spec.rb \
        spec/requests/workspaces/projects/resource_sharing_spec.rb
git commit -m "feat(clientside): share resources to the client side (team-side flag)"
```

---

## PHASE P2 — Client area: projects

### Task 2: Clientside namespace, layout, projects index/show

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/clientside/base_controller.rb`, `app/controllers/clientside/projects_controller.rb`
- Create: `app/views/layouts/clientside.html.erb`, `app/views/clientside/projects/index.html.erb`, `app/views/clientside/projects/show.html.erb`
- Modify: `config/locales/en/clientside.en.yml`
- Test: `spec/requests/clientside/projects_spec.rb`

**Interfaces:**
- Consumes: `Current.user.client_accesses` (#1); `Project#clientside_enabled?` (#1); `Project#client_visible_resources` (Task 1).
- Produces: routes `clientside_projects_path`, `clientside_project_path(project)`; `Clientside::BaseController` with `set_client_project` + `ensure_clientside_enabled`; `Clientside::ProjectsController` (`index`, `show`).

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, after the onboarding namespace block and before
`draw(:app)` (around line 108–114), add:

```ruby
  namespace :clientside do
    resources :projects, only: %i[index show] do
      resources :resources, only: %i[show], module: :projects
    end
  end
```

(The nested `resources :resources` is used in Task 3; adding it now keeps routes in one place.)

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/clientside/projects_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Clientside projects", type: :request do
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) } # project has clientside_enabled: true (factory)
  let(:project) { access.project }

  before { access; sign_in(client) }

  it "lists the projects the user is a client of" do
    get clientside_projects_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(project.name)
  end

  it "shows a project's client area with only client-visible resources" do
    visible = create(:resource, project: project, status: "published", shared_with_client: true)
    hidden = create(:resource, project: project, status: "published", shared_with_client: false)
    get clientside_project_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.title)
    expect(response.body).not_to include(hidden.title)
  end

  it "redirects a non-client away from a project they have no access to" do
    other = create(:project, clientside_enabled: true)
    get clientside_project_path(other)
    expect(response).to redirect_to(clientside_projects_path)
  end

  it "blocks the area when Clientside is turned off" do
    project.update!(clientside_enabled: false)
    get clientside_project_path(project)
    expect(response).to redirect_to(clientside_projects_path)
  end
end
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/clientside/projects_spec.rb`
Expected: FAIL — uninitialized constant `Clientside::ProjectsController`.

- [ ] **Step 4: Create the base controller**

Create `app/controllers/clientside/base_controller.rb`:

```ruby
module Clientside
  # External client area. Clients are Users but NOT workspace members, so this
  # area never uses WorkspaceScoped / Current.workspace. Projects are resolved
  # ONLY through the current user's kept ClientAccess (Clientside #1).
  class BaseController < ApplicationController
    # A client (external User, possibly onboarded_at: nil under :none) must reach
    # the client area rather than being funneled into the onboarding wizard.
    skip_onboarding_requirement
    layout "clientside"

    private

    def set_client_project
      project_id = params[:project_id] || params[:id]
      access = Current.user.client_accesses.kept.find_by(project_id: project_id)
      if access.nil?
        redirect_to clientside_projects_path, alert: t("clientside.area.no_access")
        return
      end
      @project = access.project
      Current.project = @project
    end

    def ensure_clientside_enabled
      return if @project&.clientside_enabled?
      redirect_to clientside_projects_path, alert: t("clientside.area.unavailable")
    end
  end
end
```

- [ ] **Step 5: Create the projects controller**

Create `app/controllers/clientside/projects_controller.rb`:

```ruby
module Clientside
  class ProjectsController < BaseController
    before_action :set_client_project, only: :show
    before_action :ensure_clientside_enabled, only: :show

    def index
      @projects = Project.where(id: Current.user.client_accesses.kept.select(:project_id))
    end

    def show
      @resources = @project.client_visible_resources
    end
  end
end
```

- [ ] **Step 6: Create the client layout**

Create `app/views/layouts/clientside.html.erb`:

```erb
<!DOCTYPE html>
<html lang="<%= I18n.locale %>"
      data-controller="theme"
      data-theme-theme-value="<%= current_user_theme %>">
<%= render "shared/layout_head" %>

  <body class="min-h-screen flex flex-col bg-surface-raised text-text-heading">
    <%= render "shared/skip_link" %>

    <header class="border-b border-border">
      <div class="max-w-4xl mx-auto px-4 py-3 flex items-center justify-between">
        <span class="font-semibold text-text-heading">
          <%= content_for?(:client_area_title) ? yield(:client_area_title) : t("clientside.area.title") %>
        </span>
        <%= button_to t("clientside.area.sign_out"), session_path, method: :delete,
              class: "btn-text btn-neutral" %>
      </div>
    </header>

    <main id="main-content" tabindex="-1" class="flex-1">
      <%= yield %>
    </main>

    <%= render "shared/layout_tail" %>
  </body>
</html>
```

- [ ] **Step 7: Create the index + show views**

Create `app/views/clientside/projects/index.html.erb`:

```erb
<% content_for(:title) { t("clientside.projects.index.title") } %>
<div class="max-w-4xl mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading"><%= t("clientside.projects.index.title") %></h1>
  <% if @projects.any? %>
    <ul class="mt-8 space-y-3" aria-label="<%= t("clientside.projects.index.title") %>">
      <% @projects.each do |project| %>
        <li class="border border-border rounded-lg px-4 py-3">
          <%= link_to project.name, clientside_project_path(project),
                class: "text-interactive font-medium hover:underline focus-ring rounded" %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <div class="mt-8"><%= render "shared/empty_state", message: t("clientside.projects.index.empty") %></div>
  <% end %>
</div>
```

Create `app/views/clientside/projects/show.html.erb`:

```erb
<% content_for(:title) { @project.name } %>
<% content_for(:client_area_title) { "#{@project.workspace.name} · #{t("clientside.area.title")}" } %>
<div class="max-w-4xl mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading"><%= @project.name %></h1>
  <p class="mt-2 text-text-body"><%= t("clientside.projects.show.shared_with_you") %></p>

  <% if @resources.any? %>
    <ul class="mt-8 space-y-3" aria-label="<%= t("clientside.projects.show.shared_with_you") %>">
      <% @resources.each do |resource| %>
        <li class="border border-border rounded-lg px-4 py-3">
          <%= link_to resource.title, clientside_project_resource_path(@project, resource),
                class: "text-interactive font-medium hover:underline focus-ring rounded" %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <div class="mt-8"><%= render "shared/empty_state", message: t("clientside.projects.show.empty") %></div>
  <% end %>
</div>
```

> `@project.workspace.name` reads the workspace name for the header only — it does
> NOT set `Current.workspace` (no chrome). Reading the association is fine.

- [ ] **Step 8: Add locale keys**

In `config/locales/en/clientside.en.yml`, add under the existing `clientside:`
section:

```yaml
      area:
        title: "Client area"
        sign_out: "Sign out"
        no_access: "You don't have client access to that project."
        unavailable: "That client area isn't available."
      projects:
        index:
          title: "Shared with you"
          empty: "You don't have access to any client areas yet."
        show:
          shared_with_you: "Shared with you"
          empty: "Nothing has been shared with you yet."
```

- [ ] **Step 9: Run the request spec, erb:check, full suite, commit**

Run: `bundle exec rspec spec/requests/clientside/projects_spec.rb`
Expected: PASS (4 examples).

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean.

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add config/routes.rb app/controllers/clientside/base_controller.rb \
        app/controllers/clientside/projects_controller.rb \
        app/views/layouts/clientside.html.erb app/views/clientside/projects/index.html.erb \
        app/views/clientside/projects/show.html.erb config/locales/en/clientside.en.yml \
        spec/requests/clientside/projects_spec.rb
git commit -m "feat(clientside): read-only client area (projects index + show)"
```

---

## PHASE P3 — Client area: resource view + system coverage

### Task 3: Client resource show + system spec

**Files:**
- Create: `app/controllers/clientside/projects/resources_controller.rb`
- Create: `app/views/clientside/projects/resources/show.html.erb`
- Modify: `config/locales/en/clientside.en.yml`
- Test: `spec/requests/clientside/projects/resources_spec.rb`, `spec/system/clientside_area_spec.rb`

**Interfaces:**
- Consumes: `Clientside::BaseController` (`set_client_project`, `ensure_clientside_enabled`); `Resource#client_visible?` (Task 1); route `clientside_project_resource_path(project, resource)` (Task 2).

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/clientside/projects/resources_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Clientside resources", type: :request do
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) }
  let(:project) { access.project }

  before { access; sign_in(client) }

  it "shows a client-visible resource" do
    resource = create(:resource, project: project, status: "published", shared_with_client: true)
    get clientside_project_resource_path(project, resource)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(resource.title)
  end

  it "refuses a resource that is not client-visible (draft or unshared)" do
    draft = create(:resource, project: project, status: "draft", shared_with_client: true)
    get clientside_project_resource_path(project, draft)
    expect(response).to redirect_to(clientside_project_path(project))
  end

  it "refuses access for a non-client" do
    other = create(:project, clientside_enabled: true)
    resource = create(:resource, project: other, status: "published", shared_with_client: true)
    get clientside_project_resource_path(other, resource)
    expect(response).to redirect_to(clientside_projects_path)
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/clientside/projects/resources_spec.rb`
Expected: FAIL — uninitialized constant `Clientside::Projects::ResourcesController`.

- [ ] **Step 3: Create the controller**

Create `app/controllers/clientside/projects/resources_controller.rb`:

```ruby
module Clientside
  module Projects
    class ResourcesController < Clientside::BaseController
      before_action :set_client_project
      before_action :ensure_clientside_enabled
      before_action :set_resource

      def show
      end

      private

      def set_resource
        @resource = @project.resources.kept.find_by(id: params[:id])
        return if @resource&.client_visible?
        redirect_to clientside_project_path(@project), alert: t("clientside.area.resource_unavailable")
      end
    end
  end
end
```

- [ ] **Step 4: Create the view**

Create `app/views/clientside/projects/resources/show.html.erb`:

```erb
<% content_for(:title) { @resource.title } %>
<% content_for(:client_area_title) { "#{@project.workspace.name} · #{t("clientside.area.title")}" } %>
<div class="max-w-3xl mx-auto px-4 py-16">
  <%= link_to t("clientside.area.back"), clientside_project_path(@project),
        class: "text-sm text-interactive hover:underline focus-ring rounded" %>
  <h1 class="mt-4 text-3xl font-bold text-text-heading"><%= @resource.title %></h1>
  <div class="mt-6 prose">
    <%= safe_html(@resource.resourceable.body.to_s) %>
  </div>
</div>
```

> `@resource.resourceable` is a `Document` (the only resourceable type); `.body`
> is its content. Use `safe_html` (the project's trusted-HTML helper) not `raw`.
> If `Document#body` is an ActionText/rich field, render it with the project's
> standard rich-text render instead — verify against
> `app/views/workspaces/projects/resources/show.html.erb` and match how it renders
> the document body there.

- [ ] **Step 5: Add the locale keys**

In `config/locales/en/clientside.en.yml`, add under the `clientside.area`
section:

```yaml
        back: "← Back"
        resource_unavailable: "That item isn't available."
```

- [ ] **Step 6: Run the request spec and confirm it passes**

Run: `bundle exec rspec spec/requests/clientside/projects/resources_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 7: Write the system spec**

Create `spec/system/clientside_area_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Client area", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) }
  let(:project) { access.project }

  before do
    access
    create(:resource, project: project, status: "published", shared_with_client: true, title: "Shared Doc")
    create(:resource, project: project, status: "published", shared_with_client: false, title: "Internal Doc")
    sign_in_via_form(client)
  end

  it "shows a client only the shared items, AAA in both themes" do
    visit clientside_project_path(project)
    expect(page).to have_link("Shared Doc")
    expect(page).to have_no_link("Internal Doc")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
  end
end
```

> Mirror the project's axe idiom (`sign_in_via_form`, `axe_clean_in_both_themes?`)
> exactly as in `spec/system/me_spec.rb`. If `create(:resource, title: …)` isn't
> supported by the factory, set the title via whatever the factory exposes and
> assert on the rendered titles accordingly.

- [ ] **Step 8: Run the system spec**

Run: `bundle exec rspec spec/system/clientside_area_spec.rb`
Expected: PASS (1 example). Align locators with the rendered markup if needed.

- [ ] **Step 9: erb:check, full suite, commit**

Run: `mise exec -- bundle exec rake erb:check`
Expected: clean.

Run: `bundle exec rspec`
Expected: 0 failures.

```bash
git add app/controllers/clientside/projects/resources_controller.rb \
        app/views/clientside/projects/resources/show.html.erb \
        config/locales/en/clientside.en.yml \
        spec/requests/clientside/projects/resources_spec.rb spec/system/clientside_area_spec.rb
git commit -m "feat(clientside): read-only client resource view + system coverage"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** `shared_with_client` + `client_visible?` + `client_visible_resources` (T1) ✓; member-side share checkbox + Clientside-guarded param (T1) ✓; `Clientside::BaseController` with skip_onboarding_requirement + no Current.workspace + access/enablement gates (T2) ✓; client layout (T2) ✓; projects index/show showing only client-visible resources, non-client + disabled blocked (T2) ✓; read-only resource show refusing non-visible (T3) ✓; system + AAA (T3) ✓. Out-of-scope (approve/comment, invite flow, one-click toggle) intentionally absent.
- **Placeholder scan:** no TBD/TODO; complete code in every step. The three "verify against existing usage" notes (resource factory attrs; document body rendering; axe idiom) name concrete reference files.
- **Type/name consistency:** `shared_with_client` (column/param/method) consistent; `client_visible?` / `client_visible_resources` consistent; `Clientside::BaseController#set_client_project` + `ensure_clientside_enabled` used by both `ProjectsController` and `Projects::ResourcesController`; routes `clientside_projects_path` / `clientside_project_path` / `clientside_project_resource_path` used consistently across controllers, views, and specs; `module: :projects` ⇒ `Clientside::Projects::ResourcesController` matches the controller file.
```
