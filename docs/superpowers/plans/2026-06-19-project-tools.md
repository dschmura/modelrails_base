# Per-Project Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each project a configurable set of tools via an extensible registry — wiring the one tool that exists (Docs/Resources) — with project-home tabs, a settings toggle, and a self-hiding onboarding step.

**Architecture:** A code-defined `ProjectTools::Registry` of immutable `ProjectTools::Tool` value objects is the extension seam. Per-project state is one `projects.enabled_tools` JSON array. Project-home tabs, a settings toggle controller, an enablement guard concern, and a forward-only onboarding step all read the registry + that column. No tool logic is built beyond Docs; forks register their own.

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (`Data.define` available), RSpec, Capybara + Playwright (axe), TailwindCSS 4 + modelrails_ui, SQLite.

## Global Constraints

- All user-facing text via I18n locale keys — no hardcoded strings.
- Every controller action calls Pundit `authorize` (house rule). The tools settings toggle authorizes the project with `manage_projects`.
- Access the signed-in user via `Current.user`; the active workspace/project via `Current.workspace` / `Current.project`.
- RESTful routes only (`resource :x` ⇒ **plural** `XsController`).
- UI uses modelrails_ui primitives + semantic AAA tokens (`bg-*-surface`, `text-text-*`, `border-border`). No raw hex. Focus is `focus-ring`, never `focus:ring-*`. WCAG 2.2 AAA, both themes, proven in CI.
- Domain (non-AR) modules live in `app/lib/` (e.g. `app/lib/tenancy_config.rb`). The registry goes in `app/lib/project_tools/`.
- `enabled_tools` stores tool keys as **strings** (JSON); registry keys are **symbols**. Compare with `key.to_s`.
- TDD: failing spec first, watch it fail, minimal implementation, watch it pass, commit.
- Run Ruby/Rails through the toolchain: `bundle exec rspec` (mise auto-activates; else prefix `mise exec --`). `bin/rails` for generators/migrations.
- Conventional Commits; **never** a `Co-Authored-By` / AI-attribution line. Full suite green before each phase's final commit.

---

## File Structure

Created:

- `app/lib/project_tools/tool.rb` — immutable Tool value object (`Data.define`).
- `app/lib/project_tools/registry.rb` — the registry module.
- `config/initializers/project_tools.rb` — registers `:docs`; the fork seam.
- `db/migrate/<ts>_add_enabled_tools_to_projects.rb` — JSON column + backfill.
- `app/controllers/concerns/enforces_project_tool.rb` — disabled-tool route guard.
- `app/controllers/workspaces/projects/tools_controller.rb` — settings toggle.
- `app/views/workspaces/projects/tools/edit.html.erb` — toggle form.
- `app/controllers/onboarding/tools_controller.rb` — onboarding step.
- `app/views/onboarding/tools/new.html.erb` — onboarding step view.
- `app/views/workspaces/projects/_tool_tabs.html.erb` — project-home tab bar.
- `app/policies/project_tools_policy.rb` *(only if a settings-specific policy is needed; otherwise authorize the Project — see Task 5)*.
- `app/docs/project-tools.md` — "register your own tool" guide.
- Specs under `spec/lib/project_tools/`, `spec/models/project_spec.rb` (additions), `spec/requests/workspaces/projects/tools_spec.rb`, `spec/requests/onboarding/tools_spec.rb`, `spec/requests/workspaces/projects/resources_tool_guard_spec.rb`, `spec/system/project_tools_spec.rb`.

Modified:

- `config/routes.rb` — `resource :tools` under projects; `resource :tools` in the onboarding namespace.
- `app/models/project.rb` — `enabled_tools` default + `tool_enabled?` + `tools`.
- `app/controllers/workspaces/projects/resources_controller.rb` — adopt the guard.
- `app/controllers/onboarding/projects_controller.rb` — forward-only redirect to the tools step.
- `app/views/workspaces/projects/show.html.erb` — render the tab bar.
- `config/locales/en/project_tools.en.yml` — all new keys (new file).
- `CHANGELOG.md`.

---

## PHASE P1 — Registry + model state

### Task 1: ProjectTools registry + Tool value object

**Files:**
- Create: `app/lib/project_tools/tool.rb`
- Create: `app/lib/project_tools/registry.rb`
- Create: `config/initializers/project_tools.rb`
- Create: `config/locales/en/project_tools.en.yml`
- Test: `spec/lib/project_tools/registry_spec.rb`

**Interfaces:**
- Produces:
  - `ProjectTools::Tool` (`Data.define(:key, :default_enabled, :implemented, :path_helper)`) with `#implemented?`, `#default_enabled?`, `#name`, `#description`.
  - `ProjectTools::Registry` module methods: `register(key:, path_helper: nil, default_enabled: true, implemented: true)` → Tool; `all` → Array<Tool> (the live internal array); `reset!`; `find(key)` → Tool|nil; `implemented` → Array<Tool>; `toggleable` → Array<Tool> (alias of `implemented`); `default_keys` → Array<String>.

- [ ] **Step 1: Write the failing test**

Create `spec/lib/project_tools/registry_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ProjectTools::Registry do
  # The registry holds module-level state populated at boot; save/restore it so
  # examples that register extra tools don't leak into the rest of the suite.
  around do |example|
    original = described_class.all.dup
    example.run
    described_class.all.replace(original)
  end

  it "ships docs as an implemented, default-on tool" do
    docs = described_class.find(:docs)
    expect(docs).to be_present
    expect(docs.implemented?).to be(true)
    expect(docs.default_enabled?).to be(true)
    expect(docs.path_helper).to eq(:workspace_project_resources_path)
  end

  it "exposes default_keys as strings for implemented default-on tools" do
    expect(described_class.default_keys).to include("docs")
    expect(described_class.default_keys).to all(be_a(String))
  end

  it "refuses to register an implemented tool with no path_helper" do
    expect {
      described_class.register(key: :broken, path_helper: nil, implemented: true)
    }.to raise_error(ArgumentError, /path_helper/)
  end

  it "treats only implemented tools as toggleable" do
    described_class.register(key: :future, default_enabled: false, implemented: false)
    expect(described_class.toggleable.map(&:key)).not_to include(:future)
  end

  it "resolves a tool's name from i18n" do
    expect(described_class.find(:docs).name).to eq("Docs & Files")
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/lib/project_tools/registry_spec.rb`
Expected: FAIL — uninitialized constant `ProjectTools::Registry`.

- [ ] **Step 3: Create the Tool value object**

Create `app/lib/project_tools/tool.rb`:

```ruby
module ProjectTools
  # An available project tool. Immutable; identity is its key. `path_helper` is
  # the route-helper name the tab bar calls as `helper(workspace, project)`.
  Tool = Data.define(:key, :default_enabled, :implemented, :path_helper) do
    def implemented?      = implemented
    def default_enabled?  = default_enabled
    def name        = I18n.t("project_tools.#{key}.name")
    def description = I18n.t("project_tools.#{key}.description", default: "")
  end
end
```

- [ ] **Step 4: Create the Registry**

Create `app/lib/project_tools/registry.rb`:

```ruby
module ProjectTools
  # Code-defined catalogue of project tools — the fork extension seam. Forks
  # register their own tools in config/initializers/project_tools.rb after
  # building them. Holds module-level state repopulated on each boot/reload via
  # the initializer's `to_prepare` (reset! keeps it idempotent).
  module Registry
    module_function

    def all
      @tools ||= []
    end

    def reset!
      @tools = []
    end

    def register(key:, path_helper: nil, default_enabled: true, implemented: true)
      if implemented && path_helper.blank?
        raise ArgumentError, "ProjectTools: implemented tool #{key.inspect} needs a path_helper"
      end

      tool = Tool.new(key: key.to_sym, default_enabled:, implemented:, path_helper:)
      all << tool
      tool
    end

    def find(key)
      all.find { |t| t.key == key.to_sym }
    end

    def implemented
      all.select(&:implemented?)
    end

    # Tools a user may flip on/off — only ones with a real surface.
    def toggleable
      implemented
    end

    # String keys (JSON-friendly) of the tools enabled by default on a new project.
    def default_keys
      implemented.select(&:default_enabled?).map { |t| t.key.to_s }
    end
  end
end
```

- [ ] **Step 5: Register docs in an initializer**

Create `config/initializers/project_tools.rb`:

```ruby
# Project tools registry — the fork extension seam.
#
# Register a tool here AFTER you've built its surface (model + controller +
# routes + views). `path_helper` is a project-scoped route helper the project
# tab bar calls as `helper(workspace, project)`.
#
#   ProjectTools::Registry.register(
#     key: :messages,
#     path_helper: :workspace_project_messages_path,
#     default_enabled: true
#   )
#
# See app/docs/project-tools.md. The base template ships only :docs.
Rails.application.config.to_prepare do
  ProjectTools::Registry.reset!

  ProjectTools::Registry.register(
    key: :docs,
    path_helper: :workspace_project_resources_path,
    default_enabled: true
  )
end
```

- [ ] **Step 6: Add locale keys**

Create `config/locales/en/project_tools.en.yml`:

```yaml
en:
  project_tools:
    disabled: "That tool isn't enabled for this project."
    docs:
      name: "Docs & Files"
      description: "Documents and files for this project."
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/lib/project_tools/registry_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 8: Commit**

```bash
git add app/lib/project_tools config/initializers/project_tools.rb \
        config/locales/en/project_tools.en.yml spec/lib/project_tools/registry_spec.rb
git commit -m "feat(project-tools): tool registry + docs registration"
```

### Task 2: `projects.enabled_tools` column + Project helpers

**Files:**
- Create: `db/migrate/<ts>_add_enabled_tools_to_projects.rb`
- Modify: `app/models/project.rb`
- Test: `spec/models/project_spec.rb`

**Interfaces:**
- Consumes: `ProjectTools::Registry.default_keys`, `ProjectTools::Registry.implemented` (Task 1).
- Produces: `projects.enabled_tools` (JSON array of string keys); `Project#tool_enabled?(key)` → Boolean; `Project#tools` → Array<ProjectTools::Tool> (registry-ordered, implemented ∩ enabled).

- [ ] **Step 1: Write the failing test**

Add to `spec/models/project_spec.rb` (inside `RSpec.describe Project`):

```ruby
  describe "tool enablement" do
    it "defaults a new project's enabled_tools to the registry defaults" do
      project = create(:project)
      expect(project.enabled_tools).to eq(ProjectTools::Registry.default_keys)
      expect(project.tool_enabled?(:docs)).to be(true)
    end

    it "does not override an explicitly-set enabled_tools" do
      project = create(:project, enabled_tools: [])
      expect(project.enabled_tools).to eq([])
      expect(project.tool_enabled?(:docs)).to be(false)
    end

    it "#tools returns implemented + enabled registry tools" do
      project = create(:project)
      expect(project.tools.map(&:key)).to eq([ :docs ])

      project.update!(enabled_tools: [])
      expect(project.tools).to be_empty
    end
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/project_spec.rb -e "tool enablement"`
Expected: FAIL — unknown attribute `enabled_tools`.

- [ ] **Step 3: Generate and write the migration**

Run: `bin/rails g migration AddEnabledToolsToProjects`

Replace the generated file body with:

```ruby
class AddEnabledToolsToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :enabled_tools, :json, null: false, default: []

    # Backfill existing projects with the registry's default-enabled tools.
    Project.reset_column_information
    Project.update_all(enabled_tools: ProjectTools::Registry.default_keys)
  end

  def down
    remove_column :projects, :enabled_tools
  end
end
```

- [ ] **Step 4: Migrate**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: `db/schema.rb` shows `t.json "enabled_tools", default: [], null: false` on `projects`.

- [ ] **Step 5: Implement the model helpers**

In `app/models/project.rb`, add after the `belongs_to`/`has_many` block a create-time default and the readers. Add this callback registration near the other callbacks (after the `include`s, before validations is fine) :

```ruby
  before_create :default_enabled_tools

  # ... (existing validations / methods) ...

  def tool_enabled?(key)
    enabled_tools.include?(key.to_s)
  end

  # Registry tools that are both implemented and enabled for this project,
  # in registry order — what the project tab bar renders.
  def tools
    ProjectTools::Registry.implemented.select { |tool| tool_enabled?(tool.key) }
  end

  private

  def default_enabled_tools
    self.enabled_tools = ProjectTools::Registry.default_keys if enabled_tools.blank?
  end
```

> Place `tool_enabled?` and `tools` as public methods (above the existing
> `private` keyword) and `default_enabled_tools` below `private`. The model
> already has a `private` section — add `default_enabled_tools` there and the
> readers above it.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/models/project_spec.rb -e "tool enablement"`
Expected: PASS (3 examples).

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/project.rb spec/models/project_spec.rb
git commit -m "feat(project-tools): per-project enabled_tools state + helpers"
```

---

## PHASE P2 — Project-home tabs + enablement guard

### Task 3: Project-home tool tab bar

**Files:**
- Create: `app/views/workspaces/projects/_tool_tabs.html.erb`
- Modify: `app/views/workspaces/projects/show.html.erb`
- Modify: `config/locales/en/project_tools.en.yml`
- Test: `spec/requests/workspaces/projects/tool_tabs_spec.rb`

**Interfaces:**
- Consumes: `Project#tools` (Task 2); each tool's `path_helper`.
- Produces: a `<nav aria-label>` tab bar partial taking strict local `project:`.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/workspaces/projects/tool_tabs_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Project tool tabs", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders a Docs tab linking to the project's resources" do
    get workspace_project_path(workspace, project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(workspace_project_resources_path(workspace, project))
    expect(response.body).to include("Docs &amp; Files")
  end

  it "omits a tool's tab when it is disabled" do
    project.update!(enabled_tools: [])
    get workspace_project_path(workspace, project)
    expect(response.body).not_to include(workspace_project_resources_path(workspace, project))
  end
end
```

> `user.workspaces.sole` works because the default `:personal` test posture
> auto-creates exactly one workspace for the user.

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/workspaces/projects/tool_tabs_spec.rb`
Expected: FAIL — the resources path / "Docs & Files" not in the body.

- [ ] **Step 3: Create the tab bar partial**

Create `app/views/workspaces/projects/_tool_tabs.html.erb`:

```erb
<%# locals: (project:) %>
<% tools = project.tools %>
<% if tools.any? %>
  <nav class="mt-8 flex flex-wrap gap-2" aria-label="<%= t("project_tools.tabs_label") %>">
    <% tools.each do |tool| %>
      <%= link_to tool.name, public_send(tool.path_helper, @workspace, project),
            class: "min-h-[var(--form-input-height)] flex items-center px-4 py-2 rounded-md
                    border border-border text-text-body hover:border-interactive focus-ring" %>
    <% end %>
  </nav>
<% end %>
```

- [ ] **Step 4: Render it in the project show page**

In `app/views/workspaces/projects/show.html.erb`, add immediately **above** the
existing `<nav ... aria-label="Project navigation">` (the Members/Edit nav):

```erb
  <%= render "workspaces/projects/tool_tabs", project: @project %>
```

- [ ] **Step 5: Add the locale key**

In `config/locales/en/project_tools.en.yml`, add under `project_tools:`:

```yaml
    tabs_label: "Project tools"
```

- [ ] **Step 6: Run the test and confirm it passes**

Run: `bundle exec rspec spec/requests/workspaces/projects/tool_tabs_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 7: Commit**

```bash
git add app/views/workspaces/projects/_tool_tabs.html.erb \
        app/views/workspaces/projects/show.html.erb \
        config/locales/en/project_tools.en.yml \
        spec/requests/workspaces/projects/tool_tabs_spec.rb
git commit -m "feat(project-tools): project-home tool tabs (surfaces Docs)"
```

### Task 4: Enablement guard concern + adopt in Docs

**Files:**
- Create: `app/controllers/concerns/enforces_project_tool.rb`
- Modify: `app/controllers/workspaces/projects/resources_controller.rb`
- Test: `spec/requests/workspaces/projects/resources_tool_guard_spec.rb`

**Interfaces:**
- Consumes: `Project#tool_enabled?` (Task 2); `@project`, `@workspace` set by the controller's existing `WorkspaceScoped` + `set_project`.
- Produces: `EnforcesProjectTool` concern with class macro `enforces_tool(key)` + `before_action :enforce_project_tool_enabled`.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/workspaces/projects/resources_tool_guard_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Docs tool enablement guard", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "allows the resources index when docs is enabled" do
    get workspace_project_resources_path(workspace, project)
    expect(response).to have_http_status(:ok)
  end

  it "redirects to the project when docs is disabled" do
    project.update!(enabled_tools: [])
    get workspace_project_resources_path(workspace, project)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/workspaces/projects/resources_tool_guard_spec.rb`
Expected: FAIL — the disabled case returns 200, not a redirect.

- [ ] **Step 3: Create the concern**

Create `app/controllers/concerns/enforces_project_tool.rb`:

```ruby
# Redirects a project-tool's routes back to the project home when that tool is
# disabled for the project. Include AFTER the before_action that sets @project,
# so @project is resolved before the guard runs. Declare the tool with
# `enforces_tool :key`.
module EnforcesProjectTool
  extend ActiveSupport::Concern

  included do
    before_action :enforce_project_tool_enabled
  end

  class_methods do
    def enforces_tool(key)
      @enforced_tool_key = key
    end

    def enforced_tool_key
      @enforced_tool_key
    end
  end

  private

  def enforce_project_tool_enabled
    key = self.class.enforced_tool_key
    return if key.nil? || @project.nil?
    return if @project.tool_enabled?(key)

    redirect_to workspace_project_path(@workspace, @project),
      alert: t("project_tools.disabled")
  end
end
```

- [ ] **Step 4: Adopt it in the Docs controller**

In `app/controllers/workspaces/projects/resources_controller.rb`, add the
include + declaration **immediately after** the `before_action :set_project`
line (so the guard's before_action is registered after `set_project` and runs
after it):

```ruby
      before_action :set_project
      include EnforcesProjectTool
      enforces_tool :docs
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `bundle exec rspec spec/requests/workspaces/projects/resources_tool_guard_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/concerns/enforces_project_tool.rb \
        app/controllers/workspaces/projects/resources_controller.rb \
        spec/requests/workspaces/projects/resources_tool_guard_spec.rb
git commit -m "feat(project-tools): enablement guard; Docs routes respect toggle"
```

---

## PHASE P3 — Settings toggle

### Task 5: Project tools settings page

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/workspaces/projects/tools_controller.rb`
- Create: `app/views/workspaces/projects/tools/edit.html.erb`
- Modify: `config/locales/en/project_tools.en.yml`
- Modify: `app/views/workspaces/projects/show.html.erb` (link to settings)
- Test: `spec/requests/workspaces/projects/tools_spec.rb`

**Interfaces:**
- Consumes: `ProjectTools::Registry.toggleable`; `Project#tool_enabled?`, `Project#enabled_tools`.
- Produces: routes `edit_workspace_project_tools_path` / `workspace_project_tools_path` (PATCH) → `Workspaces::Projects::ToolsController`.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `scope module: :projects do … end` block
(after the `resources :resources …` block, before the block's closing `end` at
line ~92), add:

```ruby
          resource :tools, only: %i[edit update]
```

- [ ] **Step 2: Write the failing test**

Create `spec/requests/workspaces/projects/tools_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Project tools settings", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders the toggle form" do
    get edit_workspace_project_tools_path(workspace, project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Docs &amp; Files")
  end

  it "updates enabled_tools, intersected with toggleable keys" do
    patch workspace_project_tools_path(workspace, project),
      params: { project: { enabled_tools: [ "docs", "bogus" ] } }
    expect(project.reload.enabled_tools).to eq([ "docs" ])
    expect(response).to redirect_to(edit_workspace_project_tools_path(workspace, project))
  end

  it "treats an absent checkbox group as all-off" do
    patch workspace_project_tools_path(workspace, project), params: { project: {} }
    expect(project.reload.enabled_tools).to eq([])
  end
end
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/workspaces/projects/tools_spec.rb`
Expected: FAIL — uninitialized constant `Workspaces::Projects::ToolsController`.

- [ ] **Step 4: Create the controller**

Create `app/controllers/workspaces/projects/tools_controller.rb`:

```ruby
module Workspaces
  module Projects
    class ToolsController < ApplicationController
      include WorkspaceScoped
      before_action :set_project

      def edit
        authorize @project, :update?
        @tools = ProjectTools::Registry.toggleable
      end

      def update
        authorize @project, :update?

        allowed = ProjectTools::Registry.toggleable.map { |t| t.key.to_s }
        selected = Array(params.dig(:project, :enabled_tools)) & allowed
        @project.update!(enabled_tools: selected)

        redirect_to edit_workspace_project_tools_path(@workspace, @project),
          notice: t("project_tools.settings.saved")
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
        Current.project = @project
      end
    end
  end
end
```

> Authorize uses the existing `ProjectPolicy#update?` (already governs project
> edit, which requires `manage_projects`) — no new policy needed.

- [ ] **Step 5: Create the view**

Create `app/views/workspaces/projects/tools/edit.html.erb`:

```erb
<% content_for(:title) { t("project_tools.settings.title") } %>
<div class="max-w-2xl mx-auto px-4 py-16">
  <h1 class="text-3xl font-bold text-text-heading"><%= t("project_tools.settings.title") %></h1>
  <p class="mt-2 text-text-body"><%= t("project_tools.settings.subtitle") %></p>

  <%= form_with url: workspace_project_tools_path(@workspace, @project), method: :patch,
        class: "mt-8 space-y-4" do |form| %>
    <% @tools.each do |tool| %>
      <label data-slot="control"
             class="flex items-start gap-3 rounded-md border border-border p-4">
        <%= check_box_tag "project[enabled_tools][]", tool.key.to_s,
              @project.tool_enabled?(tool.key),
              id: "tool_#{tool.key}", class: "mt-1" %>
        <span>
          <span class="block font-semibold text-text-heading"><%= tool.name %></span>
          <span class="block text-sm text-text-muted"><%= tool.description %></span>
        </span>
      </label>
    <% end %>
    <%= form.submit t("project_tools.settings.save"), class: "w-full" %>
  <% end %>
</div>
```

> A bare `check_box_tag` group is used (not a model-bound builder field) because
> `enabled_tools` is an array of keys, not a per-tool boolean attribute. The
> `[]` name collects checked keys; the controller intersects them with the
> toggleable allowlist. The hidden-field "all off" case is handled by the
> controller's `Array(...)` (an absent group ⇒ `[]`).

- [ ] **Step 6: Link settings from the project page**

In `app/views/workspaces/projects/show.html.erb`, inside the existing
`policy(@project).update?` block (next to the Edit link), add:

```erb
      <%= link_to t("project_tools.settings.link"), edit_workspace_project_tools_path(@workspace, @project),
            class: "min-h-[var(--form-input-height)] flex items-center px-4 py-2 rounded-md border border-border
                    text-text-body hover:border-interactive focus-ring" %>
```

- [ ] **Step 7: Add locale keys**

In `config/locales/en/project_tools.en.yml`, add under `project_tools:`:

```yaml
    settings:
      title: "Project tools"
      subtitle: "Choose which tools this project uses. You can change this anytime."
      save: "Save tools"
      saved: "Tools updated."
      link: "Tools"
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/requests/workspaces/projects/tools_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/workspaces/projects/tools_controller.rb \
        app/views/workspaces/projects/tools/edit.html.erb \
        app/views/workspaces/projects/show.html.erb \
        config/locales/en/project_tools.en.yml \
        spec/requests/workspaces/projects/tools_spec.rb
git commit -m "feat(project-tools): per-project tools settings toggle"
```

---

## PHASE P4 — Self-hiding onboarding step

### Task 6: Onboarding tools step (forward-only, registry-driven)

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/onboarding/tools_controller.rb`
- Create: `app/views/onboarding/tools/new.html.erb`
- Modify: `app/controllers/onboarding/projects_controller.rb`
- Modify: `config/locales/en/onboarding.en.yml`
- Test: `spec/requests/onboarding/tools_spec.rb`

**Interfaces:**
- Consumes: `ProjectTools::Registry.toggleable`; `Current.workspace`, `Current.project`; the onboarding base controller (`Onboarding::BaseController`, which sets `Current.workspace`, requires not-onboarded, and `skip_onboarding_requirement`).
- Produces: routes `new_onboarding_tools_path` / `onboarding_tools_path` (POST) → `Onboarding::ToolsController`. `Onboarding::ProjectsController#create` redirects to the tools step when `ProjectTools::Registry.toggleable.size > 1`, else the team step.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, in the onboarding namespace block, add `resource :tools`
between `project` and `team`:

```ruby
  namespace :onboarding do
    resource :workspace, only: %i[new create]
    resource :project, only: %i[new create]
    resource :tools, only: %i[new create]
    resource :team, only: %i[new create]
  end
```

- [ ] **Step 2: Write the failing test**

Create `spec/requests/onboarding/tools_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Onboarding · tools step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let!(:project) { create(:project, workspace: workspace) }

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    sign_in(user)
  end

  # A second toggleable tool so the registry offers a real choice. Restored by
  # the registry's own save/restore pattern is not active here, so undo it.
  def with_two_tools
    extra = ProjectTools::Registry.register(key: :extra, path_helper: :workspace_project_resources_path)
    yield
  ensure
    ProjectTools::Registry.all.delete(extra)
  end

  it "renders the tools step when the registry offers more than one tool" do
    with_two_tools do
      get new_onboarding_tools_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "saves the selected tools and advances to the team step" do
    with_two_tools do
      patch onboarding_tools_path, params: { project: { enabled_tools: [ "docs" ] } }
      expect(project.reload.enabled_tools).to eq([ "docs" ])
      expect(response).to redirect_to(new_onboarding_team_path)
    end
  end

  it "project create skips the tools step when only one tool is toggleable" do
    # Default registry (docs only) → project#create goes straight to team.
    get new_onboarding_project_path
    post onboarding_project_path, params: { project: { name: "Acme Website" } }
    expect(response).to redirect_to(new_onboarding_team_path)
  end

  it "project create routes through the tools step when >1 tool is toggleable" do
    with_two_tools do
      get new_onboarding_project_path
      post onboarding_project_path, params: { project: { name: "Acme Two" } }
      expect(response).to redirect_to(new_onboarding_tools_path)
    end
  end
end
```

> The `with_two_tools` helper registers a temporary second toggleable tool and
> removes it after the block, so registry state doesn't leak between examples.

- [ ] **Step 3: Run it and confirm it fails**

Run: `bundle exec rspec spec/requests/onboarding/tools_spec.rb`
Expected: FAIL — uninitialized constant `Onboarding::ToolsController` / wrong redirect from project create.

- [ ] **Step 4: Create the onboarding tools controller**

Create `app/controllers/onboarding/tools_controller.rb`:

```ruby
module Onboarding
  # Forward-only interstitial between the project and team steps. Self-hides:
  # ProjectsController#create only routes here when the registry offers a real
  # choice (>1 toggleable tool). The resume dispatcher never sends users here —
  # tool selection is optional and falls back to the create-time defaults.
  class ToolsController < BaseController
    before_action :require_project

    def new
      authorize @project, :update?
      @tools = ProjectTools::Registry.toggleable
    end

    def create
      authorize @project, :update?

      allowed = ProjectTools::Registry.toggleable.map { |t| t.key.to_s }
      selected = Array(params.dig(:project, :enabled_tools)) & allowed
      @project.update!(enabled_tools: selected)

      redirect_to new_onboarding_team_path
    end

    private

    def require_project
      @project = Current.workspace&.projects&.kept&.first
      redirect_to onboarding_path if @project.nil?
    end
  end
end
```

- [ ] **Step 5: Create the view**

Create `app/views/onboarding/tools/new.html.erb`:

```erb
<% content_for(:title) { t("onboarding.tools.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <%= render "onboarding/stepper", current: :project %>

  <h1 class="mt-10 text-3xl font-bold text-text-heading"><%= t("onboarding.tools.new.title") %></h1>
  <p class="mt-2 text-text-body"><%= t("onboarding.tools.new.subtitle") %></p>

  <%= form_with url: onboarding_tools_path, method: :patch, class: "mt-8 space-y-4" do |form| %>
    <% @tools.each do |tool| %>
      <label data-slot="control" class="flex items-start gap-3 rounded-md border border-border p-4">
        <%= check_box_tag "project[enabled_tools][]", tool.key.to_s,
              @project.tool_enabled?(tool.key), id: "tool_#{tool.key}", class: "mt-1" %>
        <span>
          <span class="block font-semibold text-text-heading"><%= tool.name %></span>
          <span class="block text-sm text-text-muted"><%= tool.description %></span>
        </span>
      </label>
    <% end %>
    <%= form.submit t("onboarding.tools.new.submit"), class: "w-full" %>
  <% end %>
</div>
```

> The stepper has no `:tools` state (the dispatcher is unchanged); showing
> `current: :project` keeps the three-dot progress consistent while on this
> interstitial.

- [ ] **Step 6: Route project create through the tools step when live**

In `app/controllers/onboarding/projects_controller.rb`, change the success
redirect in `create` from:

```ruby
        redirect_to new_onboarding_team_path, notice: t(".success")
```

to:

```ruby
        redirect_to onboarding_after_project_path, notice: t(".success")
```

and add a private helper:

```ruby
    # Forward-only: route through the tools step only when the registry offers a
    # real choice; otherwise straight to the team step.
    def onboarding_after_project_path
      if ProjectTools::Registry.toggleable.size > 1
        new_onboarding_tools_path
      else
        new_onboarding_team_path
      end
    end
```

- [ ] **Step 7: Add locale keys**

In `config/locales/en/onboarding.en.yml`, add under `onboarding:`:

```yaml
    tools:
      new:
        title: "Pick your tools"
        subtitle: "Turn on the tools this project needs — you can change these later."
        submit: "Save tools"
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/requests/onboarding/tools_spec.rb spec/requests/onboarding/projects_spec.rb`
Expected: PASS (the new tools spec + the unchanged project-step spec, which still expects the team redirect under the default registry).

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/onboarding/tools_controller.rb \
        app/views/onboarding/tools/new.html.erb \
        app/controllers/onboarding/projects_controller.rb \
        config/locales/en/onboarding.en.yml \
        spec/requests/onboarding/tools_spec.rb
git commit -m "feat(project-tools): self-hiding onboarding tools step"
```

---

## PHASE P5 — System coverage, accessibility, docs

### Task 7: End-to-end system spec + AAA axe

**Files:**
- Create: `spec/system/project_tools_spec.rb`

**Interfaces:**
- Consumes: everything from P1–P4.

- [ ] **Step 1: Write the system spec**

Create `spec/system/project_tools_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Project tools", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in_via_form(user) }

  it "shows the Docs tab and toggling it in settings hides it (AAA)" do
    visit workspace_project_path(workspace, project)
    expect(page).to have_link("Docs & Files")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")

    visit edit_workspace_project_tools_path(workspace, project)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
    uncheck "Docs & Files"
    click_button "Save tools"

    visit workspace_project_path(workspace, project)
    expect(page).to have_no_link("Docs & Files")
  end
end
```

> Mirrors the project's axe idiom (see `spec/system/me_spec.rb`):
> `sign_in_via_form`, `axe_clean_in_both_themes?(axe_options)` with `wcag2aaa`
> tags. Locally axe runs AA; CI enforces AAA — don't claim AAA from a local run.
> If `uncheck`/label-association needs the input's label `for`, the
> `check_box_tag` `id: "tool_docs"` pairs with the visible name; adjust the
> `uncheck` locator to the tool name or `id` to match the rendered label.

- [ ] **Step 2: Run the system spec**

Run: `bundle exec rspec spec/system/project_tools_spec.rb`
Expected: PASS (1 example). Align label/locator text with the rendered view if needed.

- [ ] **Step 3: Commit**

```bash
git add spec/system/project_tools_spec.rb
git commit -m "test(project-tools): end-to-end tabs + settings toggle + axe"
```

### Task 8: Fork guide, changelog, full suite

**Files:**
- Create: `app/docs/project-tools.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write the "register your own tool" guide**

Create `app/docs/project-tools.md`:

```markdown
# Project tools

Each project has a set of enabled **tools**. The base template ships one tool —
**Docs** (the `Resource`/`Document` surface). Add your own through the registry.

## Register a tool

1. Build the tool's surface: model, controller, routes, views — a project-scoped
   route helper like `workspace_project_messages_path(workspace, project)`.
2. Register it in `config/initializers/project_tools.rb`:

   ```ruby
   ProjectTools::Registry.register(
     key: :messages,
     path_helper: :workspace_project_messages_path,
     default_enabled: true
   )
   ```

3. (Optional) Guard the tool's controller so disabled projects can't reach it:

   ```ruby
   include EnforcesProjectTool
   enforces_tool :messages   # place after the before_action that sets @project
   ```

4. Add `project_tools.messages.{name,description}` locale keys.

The tool now appears as a project-home tab (when enabled), in the project tools
settings toggle, and — once more than one tool is toggleable — in the onboarding
"Pick your tools" step. Per-project state lives in `projects.enabled_tools`.
```

- [ ] **Step 2: Add a CHANGELOG entry**

In `CHANGELOG.md`, add one line under the unreleased `### Added` section (match
the file's one-line style):

```markdown
- Add per-project tools: an extensible registry, per-project toggle, project-home tabs, and a self-hiding onboarding step (ships Docs).
```

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures. Investigate any pending examples related to this feature.

- [ ] **Step 4: Commit**

```bash
git add app/docs/project-tools.md CHANGELOG.md
git commit -m "docs(project-tools): fork guide + changelog"
```

- [ ] **Step 5: Push and open a PR (after the full suite is green)**

```bash
git push -u origin feat/project-tools
```

Lefthook pre-push runs full CI locally — don't bypass it. Open a PR to `main`
summarizing P1–P5. AAA contrast is proven by the CI `test` job.

---

## Self-Review (completed during authoring)

- **Spec coverage:** registry + no-dead-entry guard (T1) ✓; `enabled_tools` column + backfill + helpers (T2) ✓; project-home tabs surfacing Docs (T3) ✓; enablement guard (T4) ✓; settings toggle with allowlist intersection + authorization (T5) ✓; self-hiding forward-only onboarding step, dispatcher untouched (T6) ✓; system + AAA (T7) ✓; fork guide + changelog (T8) ✓. Out-of-scope items (building the 5 other tools, per-tool config, reordering, seats) intentionally absent.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code. The two "align locator/label if needed" notes (system-spec `uncheck` target; the `private`-placement note in T2) point at concrete, named adjustments, not deferred work.
- **Type/name consistency:** `enabled_tools` is string-keyed throughout (`default_keys`, `tool_enabled?(key.to_s)`, `& allowed`); `toggleable`/`implemented`/`default_keys`/`find` used consistently; `EnforcesProjectTool`/`enforces_tool`/`enforced_tool_key` consistent; `path_helper` invoked as `public_send(tool.path_helper, @workspace, project)` in the view matching its registration symbol; onboarding redirect helper `onboarding_after_project_path` defined where used.
```
