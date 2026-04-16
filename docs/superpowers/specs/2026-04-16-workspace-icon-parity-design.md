# Workspace Icon Parity — Design Spec

**Goal:** Bring the workspace logo/icon system to full structural parity with the user avatar system. Fix missing persistence (`logo_source` column), missing validations, controller gaps, and view inconsistencies.

**Scope:** 6 gaps across 2 chunks. Color rendering gaps (OKLCH vs hex) are explicitly deferred to the planned OKLCH color unification.

---

## Chunk 1: Schema + Model (Gaps 1, 2, 8)

### Gap 1 — Add `logo_source` column to workspaces

The workspace has no persistent record of which identity source is active. The system infers state from `logo.attached?`, which is fragile (purging a blob for any reason silently changes the displayed identity).

**Migration:** Add a `logo_source` string column with default `"initials"`. Backfill existing rows: any workspace with a logo attached gets `"upload"`.

```ruby
class AddLogoSourceToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :logo_source, :string, default: "initials", null: false

    Workspace.where.associated(:logo_attachment).update_all(logo_source: "upload")
  end

  def down
    remove_column :workspaces, :logo_source
  end
end
```

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
current_source = if is_user
                   model.avatar_source
                 elsif model.respond_to?(:logo_source)
                   model.logo_source
                 else
                   model.logo.attached? ? "upload" : "initials"
                 end
```

The `respond_to?` guard maintains backward compatibility during the migration window.

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
resource :branding, only: [:edit, :update, :destroy]
```

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

Create `app/views/workspaces/brandings/destroy.turbo_stream.erb` to replace the logo preview and show a success toast.

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
| `db/migrate/TIMESTAMP_add_logo_source_to_workspaces.rb` | 1 | New: migration + backfill |
| `app/models/workspace.rb` | 1 | Validation, `available_logo_sources` method |
| `app/models/user.rb` | 1 | `avatar_original` validation |
| `app/views/shared/_identity_picker.html.erb` | 1 | `current_source` uses `logo_source` |
| `app/views/workspaces/brandings/edit.html.erb` | 1 | Use `available_logo_sources` |
| `app/controllers/workspaces/brandings_controller.rb` | 1+2 | Source guard, persist `logo_source`, `destroy` action, purge-on-fail |
| `config/routes.rb` | 2 | Add `:destroy` to branding resource |
| `app/views/workspaces/show.html.erb` | 2 | Use `workspace_icon_for` + named element |
| `app/views/workspaces/brandings/destroy.turbo_stream.erb` | 2 | New: turbo stream for logo removal |
| `app/views/workspaces/brandings/update.turbo_stream.erb` | 2 | Add `workspace_logo_show` replace |
| `spec/models/workspace_spec.rb` | 1 | `logo_source` + `available_logo_sources` tests |
| `spec/models/user_spec.rb` | 1 | `avatar_original` validation test |
| `spec/requests/workspaces/brandings_spec.rb` | 1+2 | Source guard, destroy action, purge tests |
