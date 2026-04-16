# Workspace Icon Parity — Design Spec

**Goal:** Bring the workspace logo/icon system to full structural parity with the user avatar system. Fix missing persistence (`logo_source` column), missing validations, controller gaps, and view inconsistencies.

**Scope:** 6 gaps across 2 chunks. Color rendering gaps (OKLCH vs hex) are explicitly deferred to the planned OKLCH color unification.

---

## Chunk 1: Schema + Model (Gaps 1, 2, 8)

### Gap 1 — Add `logo_source` column to workspaces

The workspace has no persistent record of which identity source is active. The system infers state from `logo.attached?`, which is fragile (purging a blob for any reason silently changes the displayed identity).

**Two migrations** (following project precedent of separating schema from data — see `20260406164212` + `20260406164814`):

Migration 1 — schema only (`def change`):

```ruby
class AddLogoSourceToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :logo_source, :string, default: "initials", null: false
  end
end
```

Migration 2 — data backfill (`def up`/`def down`):

```ruby
class BackfillLogoSourceOnWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.joins(:logo_attachment).update_all(logo_source: "upload")
  end

  def down
    # No-op: column default handles the reverse case
  end
end
```

Uses `joins(:logo_attachment)` rather than `where.associated` for consistency with the project's SQL-leaning backfill style.

**Model changes (`app/models/workspace.rb`):**

```ruby
validates :logo_source, inclusion: { in: %w[upload initials] }

def available_logo_sources
  %w[upload initials]
end
```

**Controller changes (`app/controllers/workspaces/brandings_controller.rb`):**

- Add source validity guard at the top of `update` (analogous to `avatars_controller.rb`):

```ruby
source = params[:avatar_source]
if source.present? && !@workspace.available_logo_sources.include?(source)
  # reject with error
end
```

- Persist `logo_source` when source changes:
  - On crop save (logo attached): `@workspace.logo_source = "upload"`
  - On source switch to initials: `@workspace.logo_source = "initials"`

**View changes (`app/views/shared/_identity_picker.html.erb`):**

Change the `current_source` inference on line 4 from:

```ruby
current_source = is_user ? model.avatar_source : (model.logo.attached? ? "upload" : "initials")
```

To:

```ruby
current_source = is_user ? model.avatar_source : model.logo_source
```

Uses the `is_user` boolean pattern consistent with all other branches in the partial (9 existing uses). No `respond_to?` guard — the migration is atomic, so `logo_source` will always be present once deployed.

**View changes (`app/views/workspaces/brandings/edit.html.erb`):**

Change the hardcoded `available_sources: %w[upload initials]` to:

```ruby
available_sources: @workspace.available_logo_sources
```

### Gap 2 — Add `avatar_original` validation to User (reverse gap)

User validates `avatar` for content type and size but NOT `avatar_original`. Workspace already validates both. Add to `app/models/user.rb`:

```ruby
validates :avatar_original,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 10.megabytes }
```

Limit is 10MB (double the 5MB limit for the cropped `avatar`) since originals can be larger.

### Gap 8 — `available_logo_sources` method

Covered above in Gap 1 model changes. The method returns `%w[upload initials]` — no Gravatar for workspaces (intentional, workspaces have no email).

---

## Chunk 2: View + Controller Cleanup (Gaps 5, 7, 9)

### Gap 5 — `workspaces/show.html.erb` bypasses `workspace_icon_for`

Replace the inline logo rendering (lines 5-12) with:

```erb
<%= workspace_icon_for(@workspace, size: :lg) %>
```

This gets:
- Proper resize variant (not raw blob)
- Owner-avatar fallback for personal workspaces
- Consistent initials rendering
- `logo_source` awareness (once Gap 1 lands)

Wrap it in a named element for turbo stream targeting:

```erb
<span id="workspace_logo_show">
  <%= workspace_icon_for(@workspace, size: :lg) %>
</span>
```

### Gap 7 — Extract logo removal to a `destroy` action

RESTful routing: `DELETE /workspace/:slug/branding` = remove the logo. Currently handled by a `remove_image` param guard in `update`.

**Route change (`config/routes.rb`):**

Ensure the branding resource includes `:destroy`:

```ruby
resource :branding, only: [ :edit, :update, :destroy ]
```

(Note: spaces inside brackets to match project convention at `config/routes.rb:44`.)

**Controller (`app/controllers/workspaces/brandings_controller.rb`):**

Add a `destroy` action:

```ruby
def destroy
  authorize @workspace, policy_class: Workspaces::BrandingPolicy

  @workspace.logo.purge if @workspace.logo.attached?
  @workspace.logo_original.purge if @workspace.logo_original.attached?
  @workspace.update!(logo_source: "initials")

  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to edit_workspace_branding_path(@workspace), notice: t(".success") }
  end
end
```

Remove the `remove_image` guard from `update`. Update the branding edit page's remove button to send `DELETE` instead of `PATCH` with `remove_image`.

**Policy (`app/policies/workspaces/branding_policy.rb`):**

Add `destroy?` — without it, `ApplicationPolicy#destroy?` returns `false` and every destroy request raises `Pundit::NotAuthorizedError`:

```ruby
def destroy?
  can?("manage_settings")
end
```

Matches the pattern of `edit?` and `update?` in the same file.

**Locale key (`config/locales/en/workspaces.en.yml`):**

Add under `workspaces.brandings`:

```yaml
destroy:
  success: "Logo removed."
```

Following the pattern of `account.avatars.destroy.success: "Avatar removed."`.

**Turbo stream (`app/views/workspaces/brandings/destroy.turbo_stream.erb`):**

New file — first `destroy.turbo_stream.erb` in the project. Follows the structure of `update.turbo_stream.erb` (inline `turbo_stream.replace` block + `turbo_stream.append "toast-pills"` with `toast_pill` partial):

```erb
<%= turbo_stream.replace "workspace_logo_branding" do %>
  <span id="workspace_logo_branding">
    <%= workspace_icon_for(@workspace, size: :lg) %>
  </span>
<% end %>

<%= turbo_stream.replace "workspace_logo_show" do %>
  <span id="workspace_logo_show">
    <%= workspace_icon_for(@workspace, size: :lg) %>
  </span>
<% end %>

<%= turbo_stream.append "toast-pills" do %>
  <%= render "shared/toast_pill", type: :success, message: t(".success") %>
<% end %>
```

### Gap 9 — Purge-on-failed-save

In `brandings_controller.rb#update`, the `else` branch (save failure) should purge any just-attached blobs:

```ruby
else
  @workspace.logo.purge if cropped_image.present?
  @workspace.logo_original.purge if original_image.present?
  # ... existing error response ...
end
```

This matches `avatars_controller.rb`'s pattern and prevents orphaned blobs.

### Turbo stream for show page (bonus from Gap 5)

Add to `app/views/workspaces/brandings/update.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "workspace_logo_show" do %>
  <span id="workspace_logo_show">
    <%= workspace_icon_for(@workspace, size: :lg) %>
  </span>
<% end %>
```

This updates the show page's logo in-place after a branding change (if the user has both pages open, or navigates via Turbo).

---

## What this spec does NOT cover (deferred)

| Item | Reason |
|------|--------|
| Gap 3: Identity picker hue hardcode for workspace | Deferred to OKLCH unification — would add throwaway hex→hue conversion code |
| Gap 4: `workspace_helper` uses hex not OKLCH for initials | Same — interim OKLCH patch would be replaced |
| Gap 10: 8 missing workspace system specs | Add after structural work settles; existing 2 specs cover the critical paths |
| Color strategy coherence | Tracked separately — needs app-wide OKLCH unification per Evil Martians pattern |

---

## Testing strategy

- **Model specs:** TDD for `logo_source` validation, `available_logo_sources`, `avatar_original` validation on User
- **Request specs:** TDD for `destroy` action, source validity guard, purge-on-failed-save, `logo_source` persistence
- **Existing system specs:** Verify the 2 workspace specs still pass after the structural changes
- **Full suite:** Run after each chunk

## Files touched

| File | Chunk | Change |
|------|-------|--------|
| `db/migrate/TIMESTAMP_add_logo_source_to_workspaces.rb` | 1 | New: schema migration (`def change`) |
| `db/migrate/TIMESTAMP_backfill_logo_source_on_workspaces.rb` | 1 | New: data backfill (`def up`/`def down`) |
| `app/models/workspace.rb` | 1 | Validation, `available_logo_sources` method |
| `app/models/user.rb` | 1 | `avatar_original` validation |
| `app/views/shared/_identity_picker.html.erb` | 1 | `current_source` uses `logo_source` |
| `app/views/workspaces/brandings/edit.html.erb` | 1+2 | Use `available_logo_sources`, update remove button to DELETE |
| `app/controllers/workspaces/brandings_controller.rb` | 1+2 | Source guard, persist `logo_source`, `destroy` action, purge-on-fail |
| `app/policies/workspaces/branding_policy.rb` | 2 | Add `destroy?` method |
| `config/routes.rb` | 2 | Add `:destroy` to branding resource |
| `config/locales/en/workspaces.en.yml` | 2 | Add `brandings.destroy.success` key |
| `app/views/workspaces/show.html.erb` | 2 | Use `workspace_icon_for` + named element |
| `app/views/workspaces/brandings/destroy.turbo_stream.erb` | 2 | New: turbo stream for logo removal |
| `app/views/workspaces/brandings/update.turbo_stream.erb` | 2 | Add `workspace_logo_show` replace |
| `spec/models/workspace_spec.rb` | 1 | `logo_source` + `available_logo_sources` tests |
| `spec/models/user_spec.rb` | 1 | `avatar_original` validation test |
| `spec/requests/workspaces/brandings_spec.rb` | 1+2 | Source guard, destroy action, purge tests |
| `spec/policies/workspaces/branding_policy_spec.rb` | 2 | `destroy?` policy test |
