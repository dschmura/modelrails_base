---
title: Extending
description: How to add resource types, custom roles, and new features to ModelRails
keywords: resource types roles permissions migration polymorphic customization logo branding cookies gdpr consent analytics cross-workspace unscoped queries sweep jobs admin rake tasks
---

# Extending ModelRails

## Adding a workspace-scoped feature

Most features you build are **workspace-scoped**: data a tenant owns that must never leak across workspaces. The framework keeps that **explicit** — there is no magic `default_scope` — so you opt in deliberately at each step. Here is the full path for a new model (say, a `Milestone`).

### 1. Generate the model and run the migration

```bash
rails generate model Milestone name:string workspace:references
rails db:migrate
```

`rails generate model` only *writes* the migration; `rails db:migrate` applies it. Skipping the second command is the most common first mistake.

### 2. Decide how it is tenant-scoped

Two shapes — picking the wrong one is the most common *design* mistake:

- **A workspace-level root** (a top-level thing a workspace owns, like `Project`) → `include Tenanted`, which adds `belongs_to :workspace` and a `for_current_workspace` scope.
- **A child of something already tenant-scoped** (e.g. a `Comment` on a `Project`) → just `belongs_to :project`. Do **not** add `Tenanted` or a `workspace_id`; it inherits its tenant transitively through the parent. This is exactly why `Resource` and `Document` carry no `workspace_id` — they reach the workspace via `resource → project → workspace`.

```ruby
# app/models/milestone.rb — a workspace-level root
class Milestone < ApplicationRecord
  include Tenanted   # adds belongs_to :workspace + the for_current_workspace scope
  belongs_to :created_by, class_name: "User"
  validates :name, presence: true
end
```

> **Scoping is explicit, not automatic.** `Tenanted` deliberately installs **no** `default_scope`. You scope every query yourself (step 3). That avoids `default_scope`'s action-at-a-distance, but it means *you* are responsible for never loading a tenant model unscoped.

### 3. Controller — scope through the workspace, and authorize

Include `WorkspaceScoped` (it resolves `@workspace` from the URL slug and sets `Current.workspace`), then query **through the association** — never `Milestone.all`:

```ruby
# app/controllers/workspaces/milestones_controller.rb
class Workspaces::MilestonesController < ApplicationController
  include WorkspaceScoped

  def index
    authorize Milestone
    @milestones = @workspace.milestones.kept   # scoped via the association
  end

  def create
    authorize Milestone
    @milestone = @workspace.milestones.build(milestone_params)
    @milestone.created_by = Current.user
    # ...
  end
end
```

`@workspace.milestones` is the load-bearing isolation boundary; `Current.workspace` (set by `WorkspaceScoped`) is the defense-in-depth backstop that policies and `for_current_workspace` rely on.

> **The moment a create involves a second row** — a membership, a join record, anything that must exist for the first row to be usable — move the assembly onto the tenant root as a verb: `Workspace#create_milestone(attrs, creator:)` in the `Workspace#create_project` shape (one transaction, `lock!` + guard, both writes, returns the possibly-invalid record for form re-render). Committing the first row and then writing the second outside the transaction is the orphaned-record bug class #660 and #676 closed — a raise between the writes strands a committed record its own creator can't see. See the creation-verb shape under Concurrency in [Architecture](architecture).

#### Only the seven actions

Every routed action is `index`, `show`, `new`, `create`, `edit`, `update`, or `destroy`, with no cited exceptions. A `member do ... end` block with a verb in it is a resource that has not been named yet: archive and unarchive are `create` and `destroy` on a nested singular `archival`; resending an invitation is `create` on a nested `resend`; a two-step ceremony is two creates on two nouns (a passkey's `challenge`, then its `credential`); a static page is `show` on `pages`, keyed by name. The trade is one more small controller for a URL that names the domain, and base took it everywhere (its own `bin/rails routes`, filtered to non-REST actions, prints nothing). The `ModelRails/RestfulActions` cop (`lib/rubocop`) fails a public controller method with any other name on commit, so a helper that belongs below `private` fails too.

### 4. Authorize with a Pundit policy

Every controller action calls `authorize`. Add a policy that extends `ApplicationPolicy`, which provides `membership` (the current user's membership in `Current.workspace`) and `can?("permission")` (reads that member's role-permission flags):

```ruby
# app/policies/milestone_policy.rb
class MilestonePolicy < ApplicationPolicy
  def index?
    membership.present?            # any member of the workspace
  end

  def create?
    can?("manage_projects")        # gated on a role permission
  end

  def update?
    create?
  end

  def destroy?
    record.created_by == user || can?("manage_workspace")
  end
end
```

The permission keys (`manage_projects`, `manage_members`, `manage_workspace`, …) live on each role; see [Workspace Administration](/docs/user/workspaces) for the full list.

### 5. Opt into shared behavior (optional)

Mix in the same concerns the built-in models use, only as needed:

| Concern | Gives you | Requirement |
|---|---|---|
| `Discardable` | Soft delete (`discard!`, `.kept` scope) | — |
| `Trackable` | Activity-log entries when the record changes | — |
| `Broadcastable` | Turbo Stream broadcasts on change | define a private `broadcast_target` (e.g. `workspace` or the parent record) |

`Project` includes all three; `Resource` broadcasts to its `project`. Copy whichever match your model.

#### Per-model traits

A concern that belongs to one model is a **trait**, and it lives with its model, not in `app/models/concerns/`: `app/models/user/avatar.rb` reopens the class and nests the module —

```ruby
class User < ApplicationRecord
  module Avatar
    extend ActiveSupport::Concern
    # ...
  end
end
```

— and the model includes it by its bare name (`include Avatar`). The nested form is required, not stylistic: the compact `module User::Avatar` does not open `User`'s lexical scope, so the trait cannot see the model's constants. `app/models/concerns/` is for concerns a second model also includes (`Discardable`, `Trackable`, `Broadcastable`). What earns a trait is a domain name a user would recognize plus a reason to change that differs from the model's; a slice by Rails artifact type ("validations", "callbacks") does not, and a method that overrides a shared concern's hook or calls `super` stays in the class body, where include order cannot shadow it. Include order is callback registration order, so a trait that registers callbacks is included where its callbacks belonged. Base's own traits under `app/models/{user,invitation,workspace,membership}/` are the exemplars. The `ModelRails/ModelConcernNamespace` cop (`lib/rubocop`) fails a compact-form file under `app/models/<model>/` on commit.

### 6. Outside the request cycle (jobs, rake tasks, machine clients)

Controllers establish `Current.workspace` for you (`WorkspaceScoped` resolves it from the URL slug); **nothing does that automatically anywhere else**. A job, rake task, or any future non-browser entry point doing tenant-scoped work must set it explicitly — and should read it back with `Current.workspace!` (note the bang), which raises `Current::NoWorkspaceError` when context was never established. The plain `Current.workspace` returns `nil` in that situation, and a `nil` inside a `where` clause silently widens the query across tenants — the exact failure the explicit-scoping design exists to prevent.

```ruby
class DigestJob < ApplicationJob
  def perform(workspace_id)
    Current.workspace = Workspace.find(workspace_id)  # establish explicitly
    Current.workspace!.projects.find_each { |p| ... } # read with the bang
  end
end
```

## Cross-workspace queries

Everything above scopes to *one* workspace. Some code legitimately needs the
opposite — a query that spans every workspace on purpose: a maintenance
sweep, a retention job, an operator fixing a single account from the command
line. `Tenanted` installs no `default_scope`, so nothing *stops* a query from
crossing workspaces; the question is where it's safe to write one.

### Where it's safe

`spec/code_smells/no_unscoped_tenant_loads_spec.rb` only scans
`app/controllers/`, `app/helpers/`, and `app/views/` — request-context code,
where `Current.workspace` is ambient and a stray class-level
`Project.find(params[:id])` can hand a signed-in user's role in *their*
workspace the authority to act on someone else's record
(`ApplicationPolicy#record_in_current_workspace?` is the runtime backstop for
that case, but the unscoped load itself is the smell the spec fails on).
**Jobs, rake tasks, and the Rails console are outside that scan** — there's
no ambient `Current.workspace` to leak and no signed-in user's permissions to
misapply. That's the boundary: request-context code always scopes through
the workspace (see [Adding a workspace-scoped
feature](#adding-a-workspace-scoped-feature) above); background code whose
whole job is touching many or all workspaces queries the model directly.

### Pattern 1 — iterate every workspace explicitly

`WorkspaceCapacitySweepJob` walks every kept workspace and reads each one's
own associations — never `Current.workspace`, never `for_current_workspace`:

```ruby
# app/jobs/workspace_capacity_sweep_job.rb
Workspace.kept.find_each do |workspace|
  sweep_members_metric(workspace)   # workspace.memberships.kept.count, etc.
end
```

Reach for this shape when the job genuinely means "every workspace" — quota
checks, per-tenant digests, anything that needs each workspace's own scoped
data one at a time.

> **Trap:** don't call `for_current_workspace` from code like this expecting
> "every record." It reads ambient `Current.workspace`, which is `nil`
> outside a request, so the scope silently becomes `where(workspace: nil)` —
> zero rows, not all of them. Query through the workspace association
> instead (`workspace.memberships.kept`), as above.

### Pattern 2 — a global condition, not a tenant identity

Most of the scheduled sweeps in `app/jobs/` (registered in
`config/recurring.yml`) don't iterate workspaces at all. They query the model
directly on a condition that has nothing to do with tenancy — age, status —
so touching every workspace is just what "in batches" naturally does:

```ruby
# ActivityLogRetentionSweepJob — 12-month retention window, no workspace filter
ActivityLog.where(created_at: ...RETENTION_WINDOW.ago).in_batches(of: 100, &:delete_all)

# WorkspaceInvitationExpiringSweepJob — every workspace's expiring invitations at once
Invitation.where(accepted_at: nil, declined_at: nil)
          .where("expires_at BETWEEN ? AND ?", Time.current, 24.hours.from_now)
          .find_each { |invitation| ... }

# DigestMailerJob — User isn't even Tenanted, but the same shape applies
User.joins(:preferences)
    .where("user_preferences.digest_next_due_at <= ?", Time.current)
    .find_each { |user| ... }
```

This is the same class-level-finder shape the request-context spec forbids
in a controller — legitimate here for the same reason as Pattern 1: no
ambient `Current.workspace` to misapply, and the condition doing the scoping
is global by design rather than standing in for "the current workspace."

### Pattern 3 — operator tools resolve one record by its own identifier

`lib/tasks/admin.rake` and `lib/tasks/tenancy.rake` run outside any request
too, so an operator can resolve a single record with a class-level finder —
something the code-smell spec would flag inside a controller:

```ruby
# lib/tasks/admin.rake
user = User.find_by!(email_address: args[:email])
workspace = Workspace.find_by!(slug: args[:slug])
```

It's safe here because there's no signed-in user whose permissions could
misfire against the result — the operator names the target directly on the
command line, and the task acts on exactly that record, not on "whatever the
current workspace happens to be."

### Rule of thumb

- **Request-context code** (controllers, helpers, views): always scope
  through the workspace association (`@workspace.projects.find_by!(...)`).
  Never a class-level finder on a `Tenanted` model — the code-smell spec
  enforces this.
- **Background code that deliberately spans workspaces** (jobs, rake tasks,
  console): query the model directly — either by iterating `Workspace.kept`
  and reading each workspace's own associations (Pattern 1), or by a
  business condition unrelated to tenant identity (Pattern 2). Never reach
  for `for_current_workspace` there; `Current.workspace` isn't set, and the
  scope will silently return nothing instead of everything.
- **Background code that means to act on one workspace** (the `DigestJob`
  example in step 6 above) sets `Current.workspace` explicitly and reads it
  back with `Current.workspace!` — the opposite of this section, and
  documented there.

## Adding a New Resource Type

The Resource registry uses a polymorphic pattern. To add a new type (e.g., `Slideshow`):

### 1. Create the model

```bash
rails generate model Slideshow
rails db:migrate          # generate writes the migration; this applies it
```

```ruby
# app/models/slideshow.rb
class Slideshow < ApplicationRecord
  has_one :resource, as: :resourceable, dependent: :destroy
  has_many :slides, dependent: :destroy
end
```

A resource type is reached through `resource → project → workspace`, so it needs **no** `workspace_id` and does **not** `include Tenanted` — see [Adding a workspace-scoped feature](#adding-a-workspace-scoped-feature) for when a model does.

### 2. Register the type

In `app/models/resource.rb`, add to the allowlist:

```ruby
ALLOWED_RESOURCEABLE_TYPES = %w[Document Slideshow].freeze
```

### 3. Create view partials

```
app/views/workspaces/projects/resources/types/_slideshow.html.erb
app/views/workspaces/projects/resources/types/_slideshow_form.html.erb
```

The controller automatically renders the correct partial based on `resourceable_type`.

### 4. Add strong parameters

In `ResourcesController#resourceable_params`, add a case:

```ruby
when "Slideshow"
  params.fetch(:slideshow, {}).permit(:title, slides_attributes: [:image, :caption, :position])
```

## Customizing the Site Logo

The app logo is rendered via `app/views/shared/_site_logo.html.erb`, an inline SVG partial used in both the header and footer. It accepts strict locals:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `size` | `:medium` | SVG height — `:small` (h-6), `:medium` (h-8), `:large` (h-10) |
| `color_class` | `"text-sky-700"` | Tailwind color class for the SVG mark (uses `currentColor`) |
| `show_name` | `false` | Show the app name text next to the mark |
| `name_class` | `"text-xl font-bold text-slate-900 dark:text-gray-100"` | Tailwind classes for the name text |

To replace the logo with your own SVG, edit the partial and swap the `<svg>` content. Keep `aria-hidden="true"` and `fill="currentColor"` so theming and accessibility continue to work.

Usage example:

```erb
<%= render "shared/site_logo", size: :small, show_name: true %>
```

## Cookie Consent (GDPR)

The app includes a GDPR cookie consent banner via [biscuit-rails](https://github.com/garethfr/biscuit-rails), overridden at `app/views/biscuit/banner/_banner.html.erb` to fix three gaps in the gem's defaults (#500): **Reject non-essential** is the emphasized default action on first visit (not Accept — rejecting must be at least as easy as accepting), the banner is server-rendered `hidden` when consent already exists so it never flashes, and reopening the preferences panel (footer link) shows the visitor's actual saved choices instead of stale checkboxes. It renders at the bottom of every page and manages consent across 4 categories:

| Category | Required | Purpose |
|----------|:--------:|---------|
| `necessary` | Yes | Session, CSRF, theme preference |
| `analytics` | No | Usage tracking (Google Analytics, etc.) |
| `preferences` | No | Non-essential preference cookies |
| `marketing` | No | Advertising and retargeting pixels |

Configuration is in `config/initializers/biscuit.rb`. The engine is mounted at `/biscuit`.

### Guarding third-party scripts

Wrap any non-essential scripts with the `biscuit_allowed?` helper:

```erb
<% if biscuit_allowed?(:analytics) %>
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXX"></script>
<% end %>

<% if biscuit_allowed?(:marketing) %>
  <!-- Retargeting pixel -->
<% end %>
```

In controllers:

```ruby
Biscuit::Consent.new(cookies).allowed?(:analytics)
```

### Disabling the banner

If your deployment only uses functional cookies (session, theme, CSRF), you can remove the banner by deleting `<%= biscuit_banner %>` from both layouts.

## Invitation Types

The invitation system supports two modes:

- **Email invitations** — enter email addresses, system sends invitation emails with 7-day expiry tokens
- **Magic link invitations** — generate a shareable URL (no email needed), useful for posting in Slack or team docs

Both types create the same `Invitation` record. The difference is whether `email` is present. See [Workspace Administration](/docs/user/workspaces) for full details.

## Adding Custom Workspace Roles

Seed a new role with custom permissions:

```ruby
# db/seeds.rb
Role.find_or_create_by!(slug: "billing_admin", workspace_id: nil) do |r|
  r.name = "Billing Admin"
  r.permissions = { manage_settings: true, manage_billing: true }
end
```

Then check the permission in policies:

```ruby
def manage_billing?
  can?("manage_billing")
end
```

> **Keep Owner a permission superset.** A role can only be granted by someone who
> already holds every permission it confers (`ApplicationPolicy#may_grant?` — this
> is what blocks Admin→Owner escalation). So every permission you introduce —
> `manage_billing` above — must also be added to the **Owner** role, or *no one*,
> not even an Owner, can assign the role that uses it and it silently disappears
> from every role picker. Add the key to Owner in the same seed:
>
> ```ruby
> owner = Role.find_by!(slug: "owner", workspace_id: nil)
> owner.update!(permissions: owner.permissions.merge("manage_billing" => true))
> ```
>
> Editing `seeds.rb` does **not** touch Owner rows already persisted in
> production/staging — backfill those with a data migration.

## Upgrading Project Roles to Role Model

If you need custom project roles beyond creator/editor/viewer:

1. Add `role_id` to `project_memberships`: `rails generate migration AddRoleIdToProjectMemberships role:references`
2. Seed project-specific roles with a `context` column on Role
3. Update `ProjectMembershipPolicy` to use `can?` instead of enum checks
4. Migrate existing data: map enum values to Role records

## Adding Per-Resource Permissions

For fine-grained access (e.g., "can view Document A but not Document B"):

1. Create a `ResourceShare` model: `user_id`, `resource_id`, `permission` (read/write)
2. Update `ResourcePolicy` to check both project membership AND resource shares
3. Resources without shares fall back to project-level permissions

## Project Tools registry

Each project carries a set of tools (tabs in the project navigation). The base template ships `:docs` only. Forks add tools by registering them in `config/initializers/project_tools.rb` **after** building the tool's surface (model + controller + routes + views):

```ruby
# config/initializers/project_tools.rb
Rails.application.config.to_prepare do
  ProjectTools::Registry.reset!

  # Built-in tool — keep this.
  ProjectTools::Registry.register(
    key: :docs,
    path_helper: :workspace_project_resources_path,
    default_enabled: true
  )

  # Your tool — register it here.
  ProjectTools::Registry.register(
    key: :messages,
    path_helper: :workspace_project_messages_path,
    default_enabled: true
  )
end
```

`path_helper` is a project-scoped route helper the project tab bar calls as `helper(workspace, project)`.

Gate a tool's controller so its routes redirect back to project home when the tool is disabled for that project:

```ruby
class Workspaces::Projects::MessagesController < ApplicationController
  include WorkspaceScoped
  include EnforcesProjectTool
  enforces_tool :messages          # redirects if tool_enabled?(:messages) is false

  before_action :set_project       # must run BEFORE the EnforcesProjectTool guard
  # …
end
```

The `EnforcesProjectTool` concern reads `@project.tool_enabled?(key)`, so `set_project` must populate `@project` before the guard fires. See [Project Tools](/docs/user/project-tools) for the full how-to.

## Clientside (external-client area)

The Clientside subsystem lets managers share a read-only project view with external clients — without giving them workspace membership or a seat in workspace policies.

Key extension points:

- **Enable per project.** Clientside is toggled on a per-project basis via the project's Clientside settings (`Workspaces::Projects::ClientsidesController`, `edit_workspace_project_clientside_path`). A project must have `clientside_enabled?` returning `true` before any client-invite or access logic runs.
- **Invite a client.** `Invitation.invite_client!(project:, email:, company_name:, invited_by:)` creates a client-type invitation and dispatches the invite email. The invitation form lives at `new_workspace_project_client_invitation_path` (`Workspaces::Projects::ClientInvitationsController`).
- **Acceptance creates a `ClientAccess`.** When a client accepts via `GET /invitations/:token/accept` (or `POST` if already signed in), `Invitation#accept_client_invitation!` creates a `ClientAccess` row — a deliberate non-`Membership` record so clients never enter workspace policies or member-seat counting.
- **Client area controllers.** `Clientside::BaseController` (namespace `clientside`) resolves projects only through `Current.user.client_accesses.kept` — clients cannot reach workspace-scoped resources. `Clientside::ProjectsController` lists accessible projects; `Clientside::Projects::ResourcesController` shows individual resources that are `client_visible?`. The layout is `clientside`, isolated from the workspace shell.
- **`skip_onboarding_requirement`.** `Clientside::BaseController` calls `skip_onboarding_requirement` so that client users (who have no workspace and therefore no `onboarded_at`) land in the client area rather than being funnelled into the onboarding wizard.

See [Clientside](/docs/user/clientside) for the full configuration and usage guide.

## AI tooling: bring your own

The template ships **no AI-agent configuration** — no `CLAUDE.md`, no `.cursorrules`, no `agent-os/`, nothing. This is a policy, not an omission: AI tooling is a per-developer choice layered onto a fork, not something a fork inherits. An agent-config file committed to the template becomes unexplainable cruft — or worse, doctrine — in every downstream fork, whose own test suite would then be enforcing another developer's tooling choices.

The boundary is enforced by a template invariant in `spec/code_smells/template_invariants_spec.rb`: the suite fails if any AI-agent configuration file (`CLAUDE.md`, `AGENTS.md`, `.claude/`, `.cursorrules`, `.aider`, and similar) becomes tracked in git. If you use AI assistance, keep your agent's configuration local via `.git/info/exclude`, which ignores files without touching the tracked `.gitignore`.

In your own fork you set the policy. If you want agent configuration to ship with your app, extend (or delete) the pattern in that invariant — with a comment saying why — and commit your setup like any other file.

## Next steps

- **[Architecture](/docs/developer/architecture)** — the request flow, tenancy model, and key directories your new code plugs into.
- **[Deployment](/docs/developer/deployment)** — ship it with Kamal once your feature is built.
- Browse the full **[docs index](/docs)** for feature-specific references (workspaces, notifications, identity, background jobs).
