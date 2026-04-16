# Workspace Icon Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the workspace logo/icon system to structural parity with the user avatar system — add persistent `logo_source`, missing validations, RESTful destroy, and view cleanup.

**Architecture:** Two chunks. Chunk 1 (Tasks 1-4) adds the `logo_source` column, model methods, controller guards, and view updates. Chunk 2 (Tasks 5-8) extracts logo removal to a RESTful `destroy` action, fixes the show page, adds purge-on-failed-save, and updates turbo streams.

**Tech Stack:** Rails 8.1, RSpec (TDD), Active Storage, Turbo Streams, Pundit

**Spec:** `docs/superpowers/specs/2026-04-16-workspace-icon-parity-design.md`

**Important:** All commands must use `mise exec --` prefix (e.g., `mise exec -- bundle exec rspec`).

---

## File Structure

### Files to Create

- `db/migrate/TIMESTAMP_add_logo_source_to_workspaces.rb` — schema migration
- `db/migrate/TIMESTAMP_backfill_logo_source_on_workspaces.rb` — data backfill
- `app/views/workspaces/brandings/destroy.turbo_stream.erb` — turbo stream for logo removal

### Files to Modify

- `app/models/workspace.rb` — `logo_source` validation, `available_logo_sources` method
- `app/models/user.rb` — `avatar_original` validation (reverse gap)
- `app/controllers/workspaces/brandings_controller.rb` — source guard, persist `logo_source`, `destroy` action, purge-on-fail
- `app/policies/workspaces/branding_policy.rb` — `destroy?` method
- `config/routes.rb` — add `:destroy` to branding resource
- `config/locales/en/workspaces.en.yml` — `brandings.destroy.success` key
- `app/views/shared/_identity_picker.html.erb` — use `logo_source` instead of `logo.attached?` inference
- `app/views/workspaces/brandings/edit.html.erb` — use `available_logo_sources`, update remove button
- `app/views/workspaces/show.html.erb` — use `workspace_icon_for` helper
- `app/views/workspaces/brandings/update.turbo_stream.erb` — add show page target

### Test Files

- `spec/models/workspace_spec.rb` — `logo_source` + `available_logo_sources` tests
- `spec/models/user_spec.rb` — `avatar_original` validation test
- `spec/requests/workspaces/brandings_spec.rb` — destroy action, source guard, purge tests
- `spec/policies/workspaces/branding_policy_spec.rb` — `destroy?` test

---

### Task 1: Migration — add `logo_source` column + backfill

**Files:**
- Create: `db/migrate/TIMESTAMP_add_logo_source_to_workspaces.rb`
- Create: `db/migrate/TIMESTAMP_backfill_logo_source_on_workspaces.rb`
- Test: `spec/models/workspace_spec.rb`

- [ ] **Step 1: Write the failing model spec**

Add to `spec/models/workspace_spec.rb` inside the `RSpec.describe Workspace` block:

```ruby
describe "logo_source" do
  it "defaults to initials" do
    workspace = create(:workspace)
    expect(workspace.logo_source).to eq("initials")
  end

  it "validates inclusion in upload and initials" do
    workspace = build(:workspace, logo_source: "upload")
    expect(workspace).to be_valid

    workspace.logo_source = "invalid"
    expect(workspace).not_to be_valid
  end
end

describe "#available_logo_sources" do
  it "returns upload and initials" do
    workspace = build(:workspace)
    expect(workspace.available_logo_sources).to eq(%w[upload initials])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/models/workspace_spec.rb --format documentation
```

Expected: FAIL — `logo_source` column doesn't exist.

- [ ] **Step 3: Create the schema migration**

```bash
mise exec -- bin/rails generate migration AddLogoSourceToWorkspaces logo_source:string
```

Edit the generated file to set the default and null constraint:

```ruby
class AddLogoSourceToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :logo_source, :string, default: "initials", null: false
  end
end
```

- [ ] **Step 4: Create the backfill migration**

```bash
mise exec -- bin/rails generate migration BackfillLogoSourceOnWorkspaces
```

Edit the generated file:

```ruby
class BackfillLogoSourceOnWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.joins(:logo_attachment).update_all(logo_source: "upload")
  end

  def down
    # No-op: column default handles the reverse
  end
end
```

- [ ] **Step 5: Run both migrations**

```bash
mise exec -- bin/rails db:migrate
```

- [ ] **Step 6: Add model validation and method**

In `app/models/workspace.rb`, after the `validates :primary_color` line (line 25-26), add:

```ruby
validates :logo_source, inclusion: { in: %w[upload initials] }

def available_logo_sources
  %w[upload initials]
end
```

Place `available_logo_sources` after the `owner` method (around line 49), in the public section before `private`.

- [ ] **Step 7: Run tests**

```bash
mise exec -- bundle exec rspec spec/models/workspace_spec.rb --format documentation
```

Expected: PASS — all new tests green.

- [ ] **Step 8: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: all pass. If any existing tests fail because they create workspaces without `logo_source`, the column default handles it — but if factories set conflicting values, adjust.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/ app/models/workspace.rb spec/models/workspace_spec.rb db/schema.rb
git commit -m "feat: add logo_source column to workspaces with validation and backfill"
```

---

### Task 2: Add `avatar_original` validation to User (reverse gap)

**Files:**
- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/user_spec.rb`:

```ruby
describe "avatar_original attachment" do
  it "rejects non-image content types" do
    user = create(:user)
    user.avatar_original.attach(
      io: StringIO.new("not an image"),
      filename: "doc.pdf",
      content_type: "application/pdf"
    )
    expect(user).not_to be_valid
    expect(user.errors[:avatar_original]).to be_present
  end

  it "rejects files over 10MB" do
    user = create(:user)
    user.avatar_original.attach(
      io: StringIO.new("x" * 11.megabytes),
      filename: "huge.png",
      content_type: "image/png"
    )
    expect(user).not_to be_valid
    expect(user.errors[:avatar_original]).to be_present
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb -e "avatar_original attachment" --format documentation
```

Expected: FAIL — no validation exists.

- [ ] **Step 3: Add the validation**

In `app/models/user.rb`, after the `validates :avatar` block (line 36-38), add:

```ruby
validates :avatar_original,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 10.megabytes }
```

- [ ] **Step 4: Run tests**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb -e "avatar_original attachment" --format documentation
```

Expected: PASS.

- [ ] **Step 5: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "feat: validate avatar_original content type and size on User"
```

---

### Task 3: Update identity picker partial to use `logo_source`

**Files:**
- Modify: `app/views/shared/_identity_picker.html.erb`
- Modify: `app/views/workspaces/brandings/edit.html.erb`

- [ ] **Step 1: Update `current_source` inference**

In `app/views/shared/_identity_picker.html.erb`, find line 4:

```ruby
current_source = is_user ? model.avatar_source : (model.logo.attached? ? "upload" : "initials")
```

Replace with:

```ruby
current_source = is_user ? model.avatar_source : model.logo_source
```

- [ ] **Step 2: Update branding edit to use `available_logo_sources`**

In `app/views/workspaces/brandings/edit.html.erb`, find the identity picker render (around line 42-45):

```erb
available_sources: %w[upload initials],
```

Replace with:

```erb
available_sources: @workspace.available_logo_sources,
```

- [ ] **Step 3: Run existing system specs to verify**

```bash
mise exec -- bundle exec rspec spec/system/workspaces/brandings_spec.rb --format documentation
```

Expected: 2 examples, 0 failures.

- [ ] **Step 4: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/views/shared/_identity_picker.html.erb app/views/workspaces/brandings/edit.html.erb
git commit -m "refactor: use logo_source instead of logo.attached? inference"
```

---

### Task 4: Persist `logo_source` in BrandingsController

**Files:**
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Test: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Write failing tests**

Add to `spec/requests/workspaces/brandings_spec.rb` inside the `context "authenticated"` block:

```ruby
describe "logo_source persistence" do
  it "sets logo_source to upload when a logo is saved via crop" do
    file = fixture_file_upload("avatar.png", "image/png")
    patch workspace_branding_path(workspace), params: {
      avatar: file,
      avatar_original: file,
      avatar_source: "upload",
      crop_coordinates: '{"x":0,"y":0,"w":100,"h":100}'
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    workspace.reload
    expect(workspace.logo_source).to eq("upload")
  end

  it "sets logo_source to initials when source is switched" do
    workspace.update!(logo_source: "upload")
    workspace.logo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "logo.png",
      content_type: "image/png"
    )

    patch workspace_branding_path(workspace), params: {
      avatar_source: "initials"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    workspace.reload
    expect(workspace.logo_source).to eq("initials")
  end

  it "rejects invalid source values" do
    patch workspace_branding_path(workspace), params: {
      avatar_source: "invalid_source"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb -e "logo_source persistence" --format documentation
```

Expected: FAIL — controller doesn't persist `logo_source` or guard invalid sources.

- [ ] **Step 3: Add source guard and `logo_source` persistence**

In `app/controllers/workspaces/brandings_controller.rb`, update the `update` action. After the `authorize` line (line 10), add the source guard:

```ruby
# Guard: reject invalid source values
if params[:avatar_source].present? && !@workspace.available_logo_sources.include?(params[:avatar_source])
  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.append("toast-cards",
        partial: "shared/toast_card",
        locals: { type: :error, message: t("workspaces.brandings.source_unavailable") }),
             status: :forbidden
    end
    format.html { redirect_to edit_workspace_branding_path(@workspace), alert: t("workspaces.brandings.source_unavailable") }
  end
  return
end
```

In the logo attachment block (around lines 26-28), after `@workspace.logo.attach(cropped_image)`, add:

```ruby
@workspace.logo_source = "upload"
```

In the source-switch block (around lines 45-51), after the purge lines, add:

```ruby
@workspace.logo_source = source
```

Add the locale key to `config/locales/en/workspaces.en.yml` under `brandings:`:

```yaml
source_unavailable: "That identity source is not available."
```

- [ ] **Step 4: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 5: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/workspaces/brandings_controller.rb config/locales/en/workspaces.en.yml spec/requests/workspaces/brandings_spec.rb
git commit -m "feat: persist logo_source and guard invalid source values"
```

---

### Task 5: Add `destroy?` to BrandingPolicy

**Files:**
- Modify: `app/policies/workspaces/branding_policy.rb`
- Test: `spec/policies/workspaces/branding_policy_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/policies/workspaces/branding_policy_spec.rb`, inside the `describe "for owner"` block:

```ruby
it "allows destroy" do
  expect(described_class.new(user, workspace).destroy?).to be true
end
```

And inside the `describe "for member"` block:

```ruby
it "denies destroy" do
  expect(described_class.new(user, workspace).destroy?).to be false
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/policies/workspaces/branding_policy_spec.rb --format documentation
```

Expected: FAIL — `destroy?` falls through to `ApplicationPolicy#destroy?` which returns `false` for both.

- [ ] **Step 3: Add the policy method**

In `app/policies/workspaces/branding_policy.rb`, after the `update?` method (line 7-9), add:

```ruby
def destroy?
  can?("manage_settings")
end
```

- [ ] **Step 4: Run tests**

```bash
mise exec -- bundle exec rspec spec/policies/workspaces/branding_policy_spec.rb --format documentation
```

Expected: PASS — all 6 policy specs green.

- [ ] **Step 5: Commit**

```bash
git add app/policies/workspaces/branding_policy.rb spec/policies/workspaces/branding_policy_spec.rb
git commit -m "feat: add destroy? to BrandingPolicy"
```

---

### Task 6: Extract logo removal to RESTful `destroy` action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Create: `app/views/workspaces/brandings/destroy.turbo_stream.erb`
- Modify: `config/locales/en/workspaces.en.yml`
- Modify: `app/views/workspaces/brandings/edit.html.erb`
- Test: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/requests/workspaces/brandings_spec.rb`:

```ruby
describe "DELETE /workspaces/:workspace_slug/branding" do
  before do
    workspace.logo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "logo.png",
      content_type: "image/png"
    )
    workspace.logo_original.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "original.png",
      content_type: "image/png"
    )
    workspace.update!(logo_source: "upload")
  end

  it "purges both logo blobs and sets logo_source to initials" do
    delete workspace_branding_path(workspace),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    workspace.reload
    expect(workspace.logo).not_to be_attached
    expect(workspace.logo_original).not_to be_attached
    expect(workspace.logo_source).to eq("initials")
  end

  it "redirects for HTML requests" do
    delete workspace_branding_path(workspace)

    expect(response).to redirect_to(edit_workspace_branding_path(workspace))
    workspace.reload
    expect(workspace.logo_source).to eq("initials")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb -e "DELETE" --format documentation
```

Expected: FAIL — route doesn't exist.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change line 44 from:

```ruby
resource :branding, only: [ :edit, :update ]
```

To:

```ruby
resource :branding, only: [ :edit, :update, :destroy ]
```

- [ ] **Step 4: Add the `destroy` action**

In `app/controllers/workspaces/brandings_controller.rb`, after the `update` action and before `private`, add:

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

- [ ] **Step 5: Add locale key**

In `config/locales/en/workspaces.en.yml`, after the `update:` block (after line 97), add:

```yaml
      destroy:
        success: "Logo removed."
```

- [ ] **Step 6: Create the turbo stream template**

Create `app/views/workspaces/brandings/destroy.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "workspace_logo_branding" do %>
  <span id="workspace_logo_branding" class="block relative">
    <%= workspace_icon_for(@workspace, size: :lg) %>
    <span class="absolute inset-0 rounded-full bg-black/0 group-hover:bg-black/20
                 transition-colors flex items-center justify-center">
      <%= icon(:pencil, size: :sm,
            class: "text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md") %>
    </span>
  </span>
<% end %>

<%= turbo_stream.append "toast-pills" do %>
  <%= render "shared/toast_pill", type: :success, message: t("workspaces.brandings.destroy.success") %>
<% end %>
```

- [ ] **Step 7: Remove `remove_image` guard from `update`**

In `app/controllers/workspaces/brandings_controller.rb`, delete the `remove_image` block (lines 12-18):

```ruby
# Remove logo (from identity picker or form)
if params[:remove_image].present?
  @workspace.logo.purge if @workspace.logo.attached?
  @workspace.logo_original.purge if @workspace.logo_original.attached?
  redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
  return
end
```

- [ ] **Step 8: Update the remove button in the branding edit view**

In `app/views/workspaces/brandings/edit.html.erb`, find the remove logo button/link (if one exists as a form with `remove_image` param). Replace it with a `button_to` that sends DELETE:

Search for any element referencing `remove_image` or `remove_logo` in the edit template. If it's a `button_to` or form, change it to:

```erb
<%= button_to t("workspaces.brandings.edit.remove_logo"),
      workspace_branding_path(@workspace),
      method: :delete,
      class: "inline-flex items-center gap-1.5 text-sm text-danger hover:text-danger/80
             min-h-[44px] px-2 rounded
             focus:outline-none focus:ring-2 focus:ring-interactive-focus" %>
```

If the remove button is currently inside the identity picker modal (handled by JS `removePhoto`), no change is needed for that path — the JS flow sends `avatar_source=initials` via PATCH, which the controller handles in the source-switch block (Task 4). The `destroy` action is for the non-modal removal (e.g., a standalone "Remove logo" link on the branding page).

- [ ] **Step 9: Update the test for remove_image**

In `spec/requests/workspaces/brandings_spec.rb`, find the existing test `"removes the logo when remove_image is sent"` (around line 55). This test sends `PATCH` with `remove_image: "1"`. Now that the `remove_image` guard is gone, update this test to use `DELETE`:

Replace:

```ruby
it "removes the logo when remove_image is sent" do
  ...
  patch workspace_branding_path(workspace), params: { remove_image: "1" }
  ...
end
```

With:

```ruby
it "removes the logo via DELETE" do
  workspace.logo.attach(
    io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
    filename: "logo.png", content_type: "image/png"
  )
  delete workspace_branding_path(workspace)
  expect(workspace.reload.logo).not_to be_attached
  expect(response).to redirect_to(edit_workspace_branding_path(workspace))
end
```

- [ ] **Step 10: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 11: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: all pass.

- [ ] **Step 12: Commit**

```bash
git add config/routes.rb app/controllers/workspaces/brandings_controller.rb app/views/workspaces/brandings/destroy.turbo_stream.erb config/locales/en/workspaces.en.yml app/views/workspaces/brandings/edit.html.erb spec/requests/workspaces/brandings_spec.rb
git commit -m "feat: extract logo removal to RESTful destroy action"
```

---

### Task 7: Fix show page + purge-on-failed-save

**Files:**
- Modify: `app/views/workspaces/show.html.erb`
- Modify: `app/views/workspaces/brandings/update.turbo_stream.erb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`

- [ ] **Step 1: Replace inline logo rendering on show page**

In `app/views/workspaces/show.html.erb`, replace lines 4-12:

```erb
  <div class="flex items-center gap-4">
    <% if @workspace.logo.attached? %>
      <%= image_tag @workspace.logo, class: "w-16 h-16 rounded-full object-cover" %>
    <% else %>
      <div class="w-16 h-16 rounded-full flex items-center justify-center font-bold text-xl text-white"
           style="background: var(--ws-primary, var(--color-interactive));">
        <%= @workspace.initials %>
      </div>
    <% end %>
```

With:

```erb
  <div class="flex items-center gap-4">
    <span id="workspace_logo_show">
      <%= workspace_icon_for(@workspace, size: :lg) %>
    </span>
```

- [ ] **Step 2: Add show page target to update turbo stream**

In `app/views/workspaces/brandings/update.turbo_stream.erb`, after the existing `turbo_stream.replace "workspace_logo_branding"` block (after line 10), add:

```erb
<%= turbo_stream.replace "workspace_logo_show" do %>
  <span id="workspace_logo_show">
    <%= workspace_icon_for(@workspace, size: :lg) %>
  </span>
<% end %>
```

Also add the same block to `app/views/workspaces/brandings/destroy.turbo_stream.erb` (already included in Task 6's template — verify it's there).

- [ ] **Step 3: Add purge-on-failed-save**

In `app/controllers/workspaces/brandings_controller.rb`, find the `else` branch after `if @workspace.update(branding_params)`. Add purge lines at the top of the `else` block:

```ruby
else
  @workspace.logo.purge if cropped_image.present?
  @workspace.logo_original.purge if original_image.present?

  error_message = @workspace.errors.full_messages.to_sentence
  # ... rest of existing error handling ...
```

- [ ] **Step 4: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/views/workspaces/show.html.erb app/views/workspaces/brandings/update.turbo_stream.erb app/views/workspaces/brandings/destroy.turbo_stream.erb app/controllers/workspaces/brandings_controller.rb
git commit -m "fix: show page uses workspace_icon_for, add turbo stream targets, purge-on-fail"
```

---

### Task 8: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: 961+ examples, 0 failures (test count will be higher from new tests).

- [ ] **Step 2: Run system specs with CI=true**

```bash
CI=true mise exec -- bundle exec rspec spec/system/workspaces/brandings_spec.rb --format documentation
```

Expected: 2 examples, 0 failures (existing specs still pass with the structural changes).

- [ ] **Step 3: Visual verification**

Start the dev server and check:

1. **Workspace show page** — logo renders via `workspace_icon_for` (proper resize, owner fallback)
2. **Branding edit page** — identity picker modal opens, crop saves, logo_source persists
3. **Remove logo** — DELETE action works (via standalone button), turbo stream updates both pages
4. **Source switch** — switching to Initials in the modal persists `logo_source = "initials"`
5. **Invalid source** — sending a bogus source value returns 403

---

## Self-Review

### Spec coverage check

| Spec requirement | Task |
|-----------------|------|
| Gap 1: `logo_source` column + backfill | Task 1 ✓ |
| Gap 1: Model validation + `available_logo_sources` | Task 1 ✓ |
| Gap 1: Controller source guard | Task 4 ✓ |
| Gap 1: Controller persists `logo_source` | Task 4 ✓ |
| Gap 1: Identity picker uses `logo_source` | Task 3 ✓ |
| Gap 1: Branding edit uses `available_logo_sources` | Task 3 ✓ |
| Gap 2: User `avatar_original` validation | Task 2 ✓ |
| Gap 5: Show page uses `workspace_icon_for` | Task 7 ✓ |
| Gap 7: RESTful `destroy` action | Task 6 ✓ |
| Gap 7: `BrandingPolicy#destroy?` | Task 5 ✓ |
| Gap 7: `brandings.destroy.success` locale key | Task 6 ✓ |
| Gap 7: `destroy.turbo_stream.erb` | Task 6 ✓ |
| Gap 8: `available_logo_sources` method | Task 1 ✓ |
| Gap 9: Purge-on-failed-save | Task 7 ✓ |
| Turbo stream for show page | Task 7 ✓ |

All spec requirements covered.

### Placeholder scan

No TBD, TODO, or vague instructions. All steps have exact code.

### Type consistency

- `logo_source` — defined in Task 1, used in Tasks 3, 4, 6. Consistent.
- `available_logo_sources` — defined in Task 1, used in Tasks 3, 4. Consistent.
- `destroy?` — defined in Task 5, used by Task 6's controller action. Consistent.
- `workspace_logo_show` — defined as element ID in Task 7, targeted in turbo streams in Tasks 6, 7. Consistent.
