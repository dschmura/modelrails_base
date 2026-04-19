# Framework Alignment Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 anti-patterns identified in a DHH-style code review: duplicated controller logic, duplicated model callbacks, raw JS fetch where Turbo works, process-local rate limiter, and copy-pasted controller methods.

**Architecture:** Each task is a small, independent refactor. No migrations, no model changes, no new features. Just aligning existing code with Rails conventions. Order doesn't matter — tasks can run in any sequence.

**Tech Stack:** Rails 8.1, Stimulus, Turbo, RSpec

**Important:** All commands use `mise exec --` prefix.

---

## File Structure

### Files to create

- `app/controllers/concerns/broadcastable.rb` — shared `after_commit :broadcast_changes` pattern
- `app/controllers/concerns/crop_coordinatable.rb` — shared `safe_parse_coordinates` method

### Files to modify

- `app/controllers/workspaces_controller.rb` — include `WorkspaceScoped` instead of duplicating `set_workspace`
- `app/controllers/magic_links_controller.rb` — replace `MemoryStore` with `Rails.cache`
- `app/javascript/controllers/theme_toggle_controller.js` — replace raw fetch with form submission
- `app/controllers/account/theme_preferences_controller.rb` — remove JSON response path
- `app/controllers/account/avatars_controller.rb` — include `CropCoordinatable`, remove private method
- `app/controllers/workspaces/brandings_controller.rb` — include `CropCoordinatable`, remove private method
- `app/models/workspace.rb` — include `Broadcastable`, remove private method
- `app/models/membership.rb` — include `Broadcastable`, remove private method
- `app/models/project.rb` — include `Broadcastable`, remove private method
- `app/models/invitation.rb` — include `Broadcastable`, remove private method
- `app/models/project_membership.rb` — include `Broadcastable`, remove private method
- `app/models/resource.rb` — include `Broadcastable`, remove private method

---

### Task 1: WorkspacesController — include WorkspaceScoped instead of duplicating set_workspace

**Files:**
- Modify: `app/controllers/workspaces_controller.rb`

The controller has its own `set_workspace` (lines 51-57) that's nearly identical to the `WorkspaceScoped` concern. The only difference: `WorkspaceScoped` reads `params[:workspace_slug] || params[:slug]` while the controller reads only `params[:slug]`. Since `WorkspacesController` uses `param: :slug` in routes, `params[:slug]` is correct — and the concern already handles this via the `||` fallback.

- [ ] **Step 1: Include the concern and remove the duplicate**

In `app/controllers/workspaces_controller.rb`, add `include WorkspaceScoped` after the class definition and remove the private `set_workspace` method:

Replace:

```ruby
class WorkspacesController < ApplicationController
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy ]
```

With:

```ruby
class WorkspacesController < ApplicationController
  include WorkspaceScoped

  skip_before_action :set_workspace, only: [ :index, :new, :create ]
```

Wait — `WorkspaceScoped` runs `before_action :set_workspace` on ALL actions. `WorkspacesController` only wants it on `show, edit, update, destroy`. The cleanest approach: keep the explicit `before_action` and just delete the duplicate private method. The concern's `included` block adds the `before_action` automatically, but we can override with `skip_before_action`.

Actually, simpler: just include the concern (which adds `before_action :set_workspace` for all actions), then `skip_before_action :set_workspace` for the actions that don't need it:

```ruby
class WorkspacesController < ApplicationController
  include WorkspaceScoped

  skip_before_action :set_workspace, only: [ :index, :new, :create ]
```

Then delete the entire private `set_workspace` method (lines 51-57).

- [ ] **Step 2: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/ spec/system/ --format progress
```

Expected: All pass — behavior is identical.

- [ ] **Step 3: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/workspaces_controller.rb
git commit -m "refactor: use WorkspaceScoped concern instead of duplicating set_workspace"
```

---

### Task 2: Fix MagicLinksController rate limiter — MemoryStore → Rails.cache

**Files:**
- Modify: `app/controllers/magic_links_controller.rb`

`MemoryStore` is process-local — with multiple Puma workers the rate limit is per-process (effectively `5 × workers`). `Rails.cache` uses Solid Cache (configured in production) which is shared across processes.

- [ ] **Step 1: Replace the store**

In `app/controllers/magic_links_controller.rb`, remove the `RATE_LIMIT_STORE` constant and change the `rate_limit` call:

Replace:

```ruby
class MagicLinksController < ApplicationController
  allow_unauthenticated_access

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 5, within: 3.minutes, only: :create,
    store: RATE_LIMIT_STORE,
    with: -> { redirect_to new_session_path, alert: t("magic_links.create.rate_limited") }
```

With:

```ruby
class MagicLinksController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 5, within: 3.minutes, only: :create,
    store: Rails.cache,
    with: -> { redirect_to new_session_path, alert: t("magic_links.create.rate_limited") }
```

One line removed, one line changed. `Rails.cache` is already configured as `:solid_cache_store` in production and `:memory_store` in test/development (which is fine — dev is single-process).

- [ ] **Step 2: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/magic_links_controller.rb
git commit -m "fix: use Rails.cache for magic link rate limiting instead of process-local MemoryStore"
```

---

### Task 3: Theme toggle — replace raw fetch with Turbo form submission

**Files:**
- Modify: `app/javascript/controllers/theme_toggle_controller.js`
- Modify: `app/controllers/account/theme_preferences_controller.rb`

The theme toggle fires a raw `fetch` with JSON to persist the preference. The server already has `format.turbo_stream`. Use a hidden form + `requestSubmit()` instead.

- [ ] **Step 1: Add a hidden form to the theme toggle view**

First, find where the theme toggle is rendered. Search for `theme-toggle` or `theme_toggle`:

```bash
grep -rn "theme.toggle\|theme_toggle" app/views/ | head -10
```

The toggle button needs a sibling hidden form:

```erb
<%= form_with url: account_theme_preference_path, method: :patch,
      data: { theme_toggle_target: "form", turbo_frame: "_top" },
      class: "hidden" do %>
  <input type="hidden" name="theme" data-theme-toggle-target="themeInput">
<% end %>
```

This form submits via Turbo natively — no JS fetch needed.

- [ ] **Step 2: Update the Stimulus controller**

Replace the `fetch` block in `cycle()` with form submission:

Replace lines 28-39:

```javascript
if (this.signedInValue && this.urlValue) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  fetch(this.urlValue, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "X-CSRF-Token": csrfToken,
      "Accept": "application/json"
    },
    body: `theme=${next}`
  })
}
```

With:

```javascript
if (this.signedInValue && this.hasFormTarget) {
  this.themeInputTarget.value = next
  this.formTarget.requestSubmit()
}
```

Add `"form"` and `"themeInput"` to the `static targets` array. Remove the `url` value (no longer needed).

- [ ] **Step 3: Remove the JSON response from the controller**

In `app/controllers/account/theme_preferences_controller.rb`, remove the `format.json` lines since nothing sends JSON anymore:

Replace:

```ruby
respond_to do |format|
  format.json { render json: { theme: preferences.theme }, status: :ok }
  format.turbo_stream
  format.html { redirect_to edit_account_profile_path, notice: t(".success") }
end
```

With:

```ruby
respond_to do |format|
  format.turbo_stream
  format.html { redirect_to edit_account_profile_path, notice: t(".success") }
end
```

Also remove the JSON error response in the rescue block.

- [ ] **Step 4: Remove `url` value from the view**

Find the view that renders the theme toggle and remove `data-theme-toggle-url-value`. Keep `data-theme-toggle-signed-in-value`.

- [ ] **Step 5: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass. If there's a request spec testing the JSON response, update it to test turbo_stream.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/theme_toggle_controller.js app/controllers/account/theme_preferences_controller.rb app/views/
git commit -m "refactor: theme toggle uses Turbo form submission instead of raw fetch"
```

---

### Task 4: Extract safe_parse_coordinates to a concern

**Files:**
- Create: `app/controllers/concerns/crop_coordinatable.rb`
- Modify: `app/controllers/account/avatars_controller.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`

The identical `safe_parse_coordinates` private method exists in both controllers. Extract to a shared concern.

- [ ] **Step 1: Create the concern**

Create `app/controllers/concerns/crop_coordinatable.rb`:

```ruby
module CropCoordinatable
  extend ActiveSupport::Concern

  private

  def safe_parse_coordinates(raw)
    return nil if raw.blank?

    parsed = JSON.parse(raw)
    return nil unless parsed.is_a?(Hash)
    return nil unless %w[x y w h].all? { |k| parsed[k].is_a?(Numeric) }

    parsed.slice("x", "y", "w", "h")
  rescue JSON::ParserError
    nil
  end
end
```

- [ ] **Step 2: Include in AvatarsController and remove the private method**

In `app/controllers/account/avatars_controller.rb`, add:

```ruby
class AvatarsController < ApplicationController
  include CropCoordinatable
```

Then delete the private `safe_parse_coordinates` method (search for it — it's near the bottom).

- [ ] **Step 3: Include in BrandingsController and remove the private method**

Same pattern in `app/controllers/workspaces/brandings_controller.rb`.

- [ ] **Step 4: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format progress
```

Expected: All pass — the crop coordinate tests already exercise this method.

- [ ] **Step 5: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/concerns/crop_coordinatable.rb app/controllers/account/avatars_controller.rb app/controllers/workspaces/brandings_controller.rb
git commit -m "refactor: extract safe_parse_coordinates to CropCoordinatable concern"
```

---

### Task 5: Extract broadcast_changes to a Broadcastable concern

**Files:**
- Create: `app/models/concerns/broadcastable.rb`
- Modify: 6 model files

Six models have near-identical `broadcast_changes` patterns. The only difference is WHAT they broadcast to:
- `Workspace` → broadcasts to `self`
- `Membership`, `Project` → broadcasts to `workspace`
- `Invitation` → broadcasts to `invitable_type == "Project" ? invitable.workspace : invitable`
- `ProjectMembership`, `Resource` → broadcasts to `project`

The concern needs to be flexible about the broadcast target. The simplest approach: each model declares its target via a class method or by overriding a method.

- [ ] **Step 1: Create the concern**

Create `app/models/concerns/broadcastable.rb`:

```ruby
module Broadcastable
  extend ActiveSupport::Concern

  included do
    after_commit :broadcast_changes, on: broadcast_events
  end

  class_methods do
    # Override in models that only broadcast on specific events.
    # Default: create and update (most common pattern).
    def broadcast_events
      [ :create, :update ]
    end
  end

  private

  # Override in each model to specify the broadcast target.
  # Default: broadcast to self.
  def broadcast_target
    self
  end

  def broadcast_changes
    broadcast_refresh_to broadcast_target
  rescue => e
    Rails.logger.warn("Broadcast failed for #{self.class.name}##{id}: #{e.message}")
  end
end
```

- [ ] **Step 2: Include in Workspace**

In `app/models/workspace.rb`, add `include Broadcastable` and override `broadcast_events` and remove the private method:

```ruby
class Workspace < ApplicationRecord
  include Discardable
  include Trackable
  include Broadcastable
```

Override the events (Workspace only broadcasts on update, not create):

```ruby
def self.broadcast_events
  [ :update ]
end
```

Delete the private `broadcast_changes` method and the `after_commit :broadcast_changes, on: [ :update ]` line (the concern handles both).

- [ ] **Step 3: Include in Membership**

In `app/models/membership.rb`:

```ruby
include Broadcastable
```

Override the target:

```ruby
private

def broadcast_target
  workspace
end
```

Delete `after_commit :broadcast_changes, on: [ :create, :update ]` and the private `broadcast_changes` method.

- [ ] **Step 4: Include in Project**

```ruby
include Broadcastable

private

def broadcast_target
  workspace
end
```

Delete the old callback + method.

- [ ] **Step 5: Include in Invitation**

```ruby
include Broadcastable

private

def broadcast_target
  invitable_type == "Project" ? invitable.workspace : invitable
end
```

Delete the old callback + method.

- [ ] **Step 6: Include in ProjectMembership**

```ruby
include Broadcastable

def self.broadcast_events
  [ :create, :update, :destroy ]
end

private

def broadcast_target
  project
end
```

Delete the old callback + method. Note: ProjectMembership also broadcasts on `:destroy` (unique among the models).

- [ ] **Step 7: Include in Resource**

```ruby
include Broadcastable

private

def broadcast_target
  project
end
```

Delete the old callback + method.

- [ ] **Step 8: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass — broadcast behavior is identical, just DRY.

- [ ] **Step 9: Commit**

```bash
git add app/models/concerns/broadcastable.rb app/models/workspace.rb app/models/membership.rb app/models/project.rb app/models/invitation.rb app/models/project_membership.rb app/models/resource.rb
git commit -m "refactor: extract broadcast_changes to Broadcastable concern"
```

---

## Self-Review

### Coverage

| Review finding | Task |
|---|---|
| #2: WorkspacesController duplicates WorkspaceScoped | Task 1 ✓ |
| #4: Rate limiter uses MemoryStore | Task 2 ✓ |
| #3: Theme toggle uses raw fetch | Task 3 ✓ |
| #5: safe_parse_coordinates copy-pasted | Task 4 ✓ |
| #6: broadcast_changes copy-pasted in 6 models | Task 5 ✓ |
| #1: Magic link unification | Deferred (separate spec/plan) |

### Placeholder scan

No TBD, TODO, or vague instructions. Task 3 requires finding the theme toggle view — the step includes the grep command to locate it.

### Type consistency

- `CropCoordinatable` — consistent name, included in both controllers
- `Broadcastable` — consistent name, `broadcast_target` and `broadcast_events` patterns used uniformly
- `WorkspaceScoped` — existing concern name, unchanged
