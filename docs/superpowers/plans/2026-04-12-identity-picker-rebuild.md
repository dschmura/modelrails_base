# Identity Picker Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the current Cropper.js v1 avatar/crop UI and start fresh for the identity picker rebuild with Cropper.js v2.

**Architecture:** Full tear-down of all crop/upload UI (Stimulus controllers, view partials, vendor CSS, routes, controller actions, specs). Keep model layer, general-purpose controllers (modal, mode_switch), and avatar/workspace helpers (modified to remove crop dependency). Archive old design docs.

**Tech Stack:** Rails 8.1, RSpec, Active Storage, TailwindCSS 4, Stimulus

**Spec:** `docs/superpowers/specs/2026-04-12-identity-picker-rebuild-design.md` (Phase 1: Removal)

---

## File Structure

### Files to Delete

- `app/javascript/controllers/image_cropper_controller.js` — Cropper.js v1 Stimulus wrapper
- `app/javascript/controllers/image_upload_controller.js` — file selection/preview/drag-drop
- `app/javascript/controllers/modal_closer_controller.js` — auto-close dialog on connect
- `app/views/shared/_image_crop.html.erb` — shared crop partial
- `app/views/shared/_image_upload_modal.html.erb` — shared upload modal partial
- `app/views/account/avatars/crop.html.erb` — standalone crop page
- `app/views/account/avatars/update.turbo_stream.erb` — turbo stream after upload
- `app/views/account/avatars/save_crop.turbo_stream.erb` — turbo stream after crop save
- `app/views/workspaces/brandings/crop.html.erb` — standalone logo crop page
- `app/views/workspaces/brandings/update.turbo_stream.erb` — turbo stream after logo upload
- `app/views/workspaces/brandings/save_crop.turbo_stream.erb` — turbo stream after logo crop save
- `app/assets/stylesheets/vendor/cropper.css` — vendored Cropper.js v1 CSS
- `app/helpers/crop_helper.rb` — `cropped_variant` helper
- `spec/system/image_crop_spec.rb` — system tests for crop UI
- `spec/system/image_upload_modal_spec.rb` — system tests for upload modal
- `spec/system/avatar_spec.rb` — end-to-end avatar flow tests
- `spec/helpers/crop_helper_spec.rb` — crop helper unit tests

### Files to Modify

- `config/importmap.rb:9` — remove `cropperjs` pin
- `config/routes.rb:24-27,47-50` — remove `crop`/`save_crop` member routes
- `app/controllers/account/avatars_controller.rb` — remove `crop`/`save_crop` actions, simplify `update`
- `app/controllers/workspaces/brandings_controller.rb` — remove `crop`/`save_crop` actions, simplify `update`
- `app/helpers/avatar_helper.rb:30` — replace `cropped_variant` with direct `variant`
- `app/helpers/workspace_helper.rb:23` — replace `cropped_variant` with direct `variant`
- `app/views/account/profiles/edit.html.erb` — replace crop/upload modal with simple avatar display + placeholder
- `app/views/workspaces/brandings/edit.html.erb:22-29` — remove upload modal render
- `spec/requests/account/avatars_spec.rb` — remove crop/save_crop/turbo_stream specs
- `spec/requests/workspaces/brandings_spec.rb` — remove crop/save_crop/turbo_stream specs
- `spec/helpers/avatar_helper_spec.rb` — no changes needed (doesn't test cropped_variant directly)

### Files to Move (Archive)

Move from `docs/superpowers/specs/` and `docs/superpowers/plans/` to `docs/superpowers/archive/`:

- `2026-04-05-avatar-system-design.md`
- `2026-04-05-avatar-system.md`
- `2026-04-05-image-upload-modal-design.md`
- `2026-04-05-image-upload-modal.md`
- `2026-04-06-image-crop-design.md`
- `2026-04-06-image-crop.md`
- `2026-04-07-avatar-crop-ux-polish-design.md`
- `2026-04-07-avatar-crop-ux-polish.md`
- `2026-04-07-cropperjs-image-crop-design.md`
- `2026-04-07-cropperjs-image-crop.md`
- `2026-04-07-identity-picker-design.md`
- `2026-04-07-identity-picker.md`

---

### Task 1: Delete Stimulus Controllers and Vendor CSS

**Files:**
- Delete: `app/javascript/controllers/image_cropper_controller.js`
- Delete: `app/javascript/controllers/image_upload_controller.js`
- Delete: `app/javascript/controllers/modal_closer_controller.js`
- Delete: `app/assets/stylesheets/vendor/cropper.css`

- [ ] **Step 1: Delete the four files**

```bash
rm app/javascript/controllers/image_cropper_controller.js
rm app/javascript/controllers/image_upload_controller.js
rm app/javascript/controllers/modal_closer_controller.js
rm app/assets/stylesheets/vendor/cropper.css
```

- [ ] **Step 2: Remove the cropperjs pin from importmap**

In `config/importmap.rb`, delete line 9:

```ruby
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.esm.js"
```

The file should now end after line 8 (`pin "lexxy", to: "lexxy.js"`).

- [ ] **Step 3: Verify no remaining references to deleted controllers**

```bash
grep -r "image.cropper\|image_cropper\|image.upload\|image_upload\|modal.closer\|modal_closer\|cropperjs" app/javascript/controllers/ config/importmap.rb --include="*.js" --include="*.rb" 2>/dev/null
```

Expected: no matches (all references are in views/specs, handled in later tasks).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete Cropper.js v1 controllers and vendor CSS

Remove image_cropper, image_upload, and modal_closer Stimulus
controllers. Delete vendored cropper.css and importmap pin.
Preparing for identity picker rebuild with Cropper.js v2."
```

---

### Task 2: Delete View Partials and Template Files

**Files:**
- Delete: `app/views/shared/_image_crop.html.erb`
- Delete: `app/views/shared/_image_upload_modal.html.erb`
- Delete: `app/views/account/avatars/crop.html.erb`
- Delete: `app/views/account/avatars/update.turbo_stream.erb`
- Delete: `app/views/account/avatars/save_crop.turbo_stream.erb`
- Delete: `app/views/workspaces/brandings/crop.html.erb`
- Delete: `app/views/workspaces/brandings/update.turbo_stream.erb`
- Delete: `app/views/workspaces/brandings/save_crop.turbo_stream.erb`

- [ ] **Step 1: Delete all eight view files**

```bash
rm app/views/shared/_image_crop.html.erb
rm app/views/shared/_image_upload_modal.html.erb
rm app/views/account/avatars/crop.html.erb
rm app/views/account/avatars/update.turbo_stream.erb
rm app/views/account/avatars/save_crop.turbo_stream.erb
rm app/views/workspaces/brandings/crop.html.erb
rm app/views/workspaces/brandings/update.turbo_stream.erb
rm app/views/workspaces/brandings/save_crop.turbo_stream.erb
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: delete crop and upload view templates

Remove shared image_crop/image_upload_modal partials, standalone
crop pages, and turbo_stream templates for both avatars and
workspace brandings."
```

---

### Task 3: Delete Crop Helper and Its Spec

**Files:**
- Delete: `app/helpers/crop_helper.rb`
- Delete: `spec/helpers/crop_helper_spec.rb`

- [ ] **Step 1: Delete both files**

```bash
rm app/helpers/crop_helper.rb
rm spec/helpers/crop_helper_spec.rb
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: delete crop_helper and its spec

Server-side cropping via blob metadata is replaced by client-side
crop export in the identity picker rebuild."
```

---

### Task 4: Update Avatar Helper to Remove cropped_variant Dependency

**Files:**
- Modify: `app/helpers/avatar_helper.rb:30`

- [ ] **Step 1: Update render_upload_avatar in avatar_helper.rb**

Replace line 30:

```ruby
    variant = cropped_variant(user.avatar, resize_to: [ config[:px], config[:px] ])
```

With:

```ruby
    variant = user.avatar.variant(resize_to_fill: [ config[:px], config[:px] ])
```

- [ ] **Step 2: Update render_workspace_logo in workspace_helper.rb**

In `app/helpers/workspace_helper.rb`, replace line 23:

```ruby
    variant = cropped_variant(workspace.logo, resize_to: [ config[:px], config[:px] ])
```

With:

```ruby
    variant = workspace.logo.variant(resize_to_fill: [ config[:px], config[:px] ])
```

- [ ] **Step 3: Run the helper specs to verify nothing breaks**

```bash
bundle exec rspec spec/helpers/avatar_helper_spec.rb spec/helpers/workspace_helper_spec.rb --format documentation
```

Expected: all existing specs pass. The avatar helper spec doesn't call `cropped_variant` directly — it tests `avatar_for` which now uses `variant` instead.

- [ ] **Step 4: Commit**

```bash
git add app/helpers/avatar_helper.rb app/helpers/workspace_helper.rb
git commit -m "fix: replace cropped_variant with direct variant calls

Avatar and workspace helpers now use variant(resize_to_fill:)
directly since crop_helper.rb has been removed."
```

---

### Task 5: Remove crop/save_crop Routes

**Files:**
- Modify: `config/routes.rb:24-27,47-50`

- [ ] **Step 1: Simplify avatar routes**

In `config/routes.rb`, replace lines 24-27:

```ruby
    resource :avatar, only: [ :update, :destroy ] do
      get :crop, on: :member
      patch :save_crop, on: :member
    end
```

With:

```ruby
    resource :avatar, only: [ :update, :destroy ]
```

- [ ] **Step 2: Simplify branding routes**

In `config/routes.rb`, replace lines 47-50:

```ruby
      resource :branding, only: [ :edit, :update ] do
        get :crop, on: :member
        patch :save_crop, on: :member
      end
```

With:

```ruby
      resource :branding, only: [ :edit, :update ]
```

- [ ] **Step 3: Verify routes compile**

```bash
bin/rails routes | grep -E "avatar|branding"
```

Expected: avatar routes show only `PATCH /account/avatar` and `DELETE /account/avatar`. Branding routes show only `GET /workspaces/:workspace_slug/branding/edit` and `PATCH /workspaces/:workspace_slug/branding`.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "chore: remove crop and save_crop routes

Simplify avatar and branding resources to only update/destroy
and edit/update respectively. Crop routes will be replaced by
the identity picker's single update action."
```

---

### Task 6: Gut Avatars Controller

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`

- [ ] **Step 1: Remove crop and save_crop actions, simplify update**

Replace the entire contents of `app/controllers/account/avatars_controller.rb` with:

```ruby
module Account
  class AvatarsController < ApplicationController
    def update
      if params[:avatar].present?
        Current.user.avatar.attach(params[:avatar])
        Current.user.avatar_source = "upload"

        if Current.user.save
          redirect_to edit_account_profile_path, notice: t(".success")
        else
          Current.user.avatar.purge
          redirect_to edit_account_profile_path, alert: Current.user.errors.full_messages.to_sentence
        end
      elsif params[:avatar_source].present?
        source = params[:avatar_source]
        unless Current.user.available_avatar_sources.include?(source)
          redirect_to edit_account_profile_path, alert: t("account.avatars.source_unavailable")
          return
        end

        if Current.user.update(avatar_source: source)
          redirect_to edit_account_profile_path, notice: t("account.avatars.source_updated")
        else
          redirect_to edit_account_profile_path, alert: Current.user.errors.full_messages.to_sentence
        end
      else
        redirect_to edit_account_profile_path
      end
    end

    def destroy
      Current.user.avatar.purge
      Current.user.update!(avatar_source: "initials")
      redirect_to edit_account_profile_path, notice: t(".success")
    end
  end
end
```

Key changes: removed `crop` action (lines 3-8), removed `save_crop` action (lines 10-30), removed turbo_stream response from `update` (redirects only now — turbo_stream templates are deleted), removed `redirect_to crop_account_avatar_path` (route no longer exists).

- [ ] **Step 2: Commit**

```bash
git add app/controllers/account/avatars_controller.rb
git commit -m "chore: remove crop/save_crop from avatars controller

Simplify to update (upload + source change) and destroy only.
Turbo stream responses removed — will be rebuilt with identity
picker."
```

---

### Task 7: Gut Brandings Controller

**Files:**
- Modify: `app/controllers/workspaces/brandings_controller.rb`

- [ ] **Step 1: Remove crop and save_crop actions, simplify update**

Replace the entire contents of `app/controllers/workspaces/brandings_controller.rb` with:

```ruby
module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      if params.dig(:workspace, :logo).present?
        @workspace.logo.attach(params[:workspace][:logo])
      end

      if @workspace.update(branding_params)
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    end
  end
end
```

Key changes: removed `crop` action (lines 9-15), removed `save_crop` action (lines 17-39), removed turbo_stream responses and separate modal upload path from `update`, consolidated logo upload into the standard form flow.

- [ ] **Step 2: Commit**

```bash
git add app/controllers/workspaces/brandings_controller.rb
git commit -m "chore: remove crop/save_crop from brandings controller

Simplify to edit and update only. Logo upload consolidated into
standard form flow. Turbo stream responses removed."
```

---

### Task 8: Update Profile Edit View

**Files:**
- Modify: `app/views/account/profiles/edit.html.erb:7-170`

- [ ] **Step 1: Replace the avatar management section**

The current avatar section (lines 7-170) contains the modal with crop and upload modes, references to deleted controllers (`image-cropper`, `image-upload`, `mode-switch`), and renders deleted partials (`_image_crop`, `_image_upload_modal`).

Replace lines 7-170 (from `<%# Avatar management — modal-first %>` through the closing `</div>` before the profile form) with a simple avatar display:

```erb
  <%# Avatar — placeholder until identity picker is implemented %>
  <div class="flex items-center gap-6 mt-8 mb-8">
    <span id="user_avatar_profile" class="shrink-0">
      <%= avatar_for(@user, size: :xl) %>
    </span>
    <div>
      <p class="text-lg font-semibold text-text-heading"><%= @user.full_name %></p>
      <p class="text-sm text-text-muted mt-1"><%= t("account.avatars.edit.identity_picker_coming_soon") %></p>
    </div>
  </div>
```

- [ ] **Step 2: Add the placeholder I18n key**

Check the locale file for the avatars namespace and add the new key. Find the locale file:

```bash
grep -r "account.avatars" config/locales/ -l
```

Add under the appropriate path in the locale file:

```yaml
      edit:
        identity_picker_coming_soon: "Avatar management coming soon"
```

- [ ] **Step 3: Commit**

```bash
git add app/views/account/profiles/edit.html.erb config/locales/
git commit -m "chore: replace avatar modal with placeholder in profile edit

Remove references to deleted crop/upload controllers and partials.
Simple avatar display with placeholder text until identity picker
is implemented."
```

---

### Task 9: Update Branding Edit View

**Files:**
- Modify: `app/views/workspaces/brandings/edit.html.erb:7-31`

- [ ] **Step 1: Replace the logo upload modal section**

Replace lines 7-31 (the logo section with `_image_upload_modal` render) with a simple logo display that uses the existing branding form for upload:

```erb
  <%# Logo section — simplified until identity picker is implemented %>
  <div class="mt-8 space-y-2">
    <p class="block text-sm font-medium text-text-body">
      <%= t("workspaces.brandings.edit.logo_label") %>
    </p>
    <div class="flex items-center gap-4">
      <span id="workspace_logo_branding"><%= workspace_icon_for(@workspace, size: :lg) %></span>
      <p class="text-sm text-text-muted"><%= t("workspaces.brandings.edit.identity_picker_coming_soon") %></p>
    </div>
  </div>
```

- [ ] **Step 2: Add the placeholder I18n key**

Find the branding locale file:

```bash
grep -r "workspaces.brandings" config/locales/ -l
```

Add under the appropriate path:

```yaml
      edit:
        identity_picker_coming_soon: "Logo management coming soon"
```

- [ ] **Step 3: Commit**

```bash
git add app/views/workspaces/brandings/edit.html.erb config/locales/
git commit -m "chore: replace logo upload modal with placeholder in branding edit

Remove reference to deleted _image_upload_modal partial. Simple
logo display until identity picker is implemented."
```

---

### Task 10: Delete System Specs

**Files:**
- Delete: `spec/system/image_crop_spec.rb`
- Delete: `spec/system/image_upload_modal_spec.rb`
- Delete: `spec/system/avatar_spec.rb`

- [ ] **Step 1: Delete the three system spec files**

```bash
rm spec/system/image_crop_spec.rb
rm spec/system/image_upload_modal_spec.rb
rm spec/system/avatar_spec.rb
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: delete crop/upload/avatar system specs

These test the v1 crop/upload UI which has been removed.
New system specs will be written TDD-style with the identity
picker implementation."
```

---

### Task 11: Update Request Specs

**Files:**
- Modify: `spec/requests/account/avatars_spec.rb`
- Modify: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Rewrite avatars request spec**

Replace the entire contents of `spec/requests/account/avatars_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe "Account Avatars", type: :request do
  describe "unauthenticated access" do
    it "redirects PATCH /account/avatar to sign in" do
      patch account_avatar_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/avatar to sign in" do
      delete account_avatar_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "PATCH /account/avatar" do
      it "uploads an avatar" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "rejects invalid content type" do
        file = Rack::Test::UploadedFile.new(
          StringIO.new("not an image"), "text/plain", true, original_filename: "document.txt"
        )
        patch account_avatar_path, params: { avatar: file }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar).not_to be_attached
      end

      it "rejects oversized file" do
        large_io = StringIO.new("x" * 6.megabytes)
        file = Rack::Test::UploadedFile.new(
          large_io, "image/png", true, original_filename: "oversized.png"
        )
        patch account_avatar_path, params: { avatar: file }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar).not_to be_attached
      end

      it "changes avatar source without uploading a file" do
        user.update_columns(has_gravatar: true)
        patch account_avatar_path, params: { avatar_source: "gravatar" }
        expect(user.reload.avatar_source).to eq("gravatar")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "rejects invalid avatar source" do
        patch account_avatar_path, params: { avatar_source: "invalid" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
      end

      it "rejects upload source when no avatar is attached" do
        patch account_avatar_path, params: { avatar_source: "upload" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar_source).to eq("initials")
      end

      it "rejects gravatar source when user has no Gravatar" do
        user.update_columns(has_gravatar: false)
        patch account_avatar_path, params: { avatar_source: "gravatar" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar_source).to eq("initials")
      end

      it "redirects when no params provided" do
        patch account_avatar_path
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "prioritizes file upload when both file and source are provided" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file, avatar_source: "gravatar" }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
      end
    end

    describe "DELETE /account/avatar" do
      it "removes the avatar and falls back to initials" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
        delete account_avatar_path
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "handles destroy gracefully when no avatar is attached" do
        delete account_avatar_path
        expect(user.reload.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end
end
```

Key changes: removed `GET /account/avatar/crop` specs (lines 115-129), removed `PATCH /account/avatar/save_crop` specs (lines 131-151), removed turbo_stream specs (lines 153-184), updated upload test to expect redirect to `edit_account_profile_path` instead of `crop_account_avatar_path`.

- [ ] **Step 2: Rewrite brandings request spec**

Replace the entire contents of `spec/requests/workspaces/brandings_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe "Workspace Brandings", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/branding/edit to sign in" do
      get edit_workspace_branding_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "GET /workspaces/:workspace_slug/branding/edit" do
      it "renders the branding form" do
        get edit_workspace_branding_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding" do
      it "updates the primary color" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }
        expect(workspace.reload.primary_color).to eq("#6366f1")
      end

      it "uploads a logo" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          workspace: { logo: file }
        }
        expect(workspace.reload.logo).to be_attached
      end

      it "redirects with success message" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end

      it "updates both logo and color" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          workspace: { logo: file, primary_color: "#0d9488" }
        }
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.primary_color).to eq("#0d9488")
      end

      it "removes the logo when remove_image is sent" do
        workspace.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png", content_type: "image/png"
        )
        patch workspace_branding_path(workspace), params: { remove_image: "1" }
        expect(workspace.reload.logo).not_to be_attached
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end

    describe "authorization" do
      it "rejects non-owner/admin access" do
        viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
        viewer = create(:user)
        create(:membership, user: viewer, workspace: workspace, role: viewer_role)
        sign_in(viewer)
        get edit_workspace_branding_path(workspace)
        expect(response).to redirect_to(workspace_path(workspace))
      end
    end
  end
end
```

Key changes: removed `GET /workspaces/:slug/branding/crop` specs (lines 91-105), removed `PATCH save_crop` specs (lines 107-121), removed turbo_stream specs (lines 123-152), removed separate "via upload modal" describe block (consolidated logo upload into standard form flow).

- [ ] **Step 3: Run the updated request specs**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: all specs pass.

- [ ] **Step 4: Commit**

```bash
git add spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb
git commit -m "test: update request specs to match simplified controllers

Remove crop, save_crop, and turbo_stream specs. Update avatar
upload expectation to redirect to profile edit instead of crop
page."
```

---

### Task 12: Archive Old Documentation

**Files:**
- Move: 12 files from `docs/superpowers/specs/` and `docs/superpowers/plans/` to `docs/superpowers/archive/`

- [ ] **Step 1: Create archive directory and move files**

```bash
mkdir -p docs/superpowers/archive
mv docs/superpowers/specs/2026-04-05-avatar-system-design.md docs/superpowers/archive/
mv docs/superpowers/specs/2026-04-05-image-upload-modal-design.md docs/superpowers/archive/
mv docs/superpowers/specs/2026-04-06-image-crop-design.md docs/superpowers/archive/
mv docs/superpowers/specs/2026-04-07-avatar-crop-ux-polish-design.md docs/superpowers/archive/
mv docs/superpowers/specs/2026-04-07-cropperjs-image-crop-design.md docs/superpowers/archive/
mv docs/superpowers/specs/2026-04-07-identity-picker-design.md docs/superpowers/archive/
mv docs/superpowers/plans/2026-04-05-avatar-system.md docs/superpowers/archive/
mv docs/superpowers/plans/2026-04-05-image-upload-modal.md docs/superpowers/archive/
mv docs/superpowers/plans/2026-04-06-image-crop.md docs/superpowers/archive/
mv docs/superpowers/plans/2026-04-07-avatar-crop-ux-polish.md docs/superpowers/archive/
mv docs/superpowers/plans/2026-04-07-cropperjs-image-crop.md docs/superpowers/archive/
mv docs/superpowers/plans/2026-04-07-identity-picker.md docs/superpowers/archive/
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "docs: archive v1 avatar/crop/upload specs and plans

Move 12 design and plan documents to docs/superpowers/archive/.
These are superseded by the identity picker rebuild spec at
docs/superpowers/specs/2026-04-12-identity-picker-rebuild-design.md"
```

---

### Task 13: Run Full Test Suite and Verify

- [ ] **Step 1: Run the full test suite**

```bash
bundle exec rspec --format progress
```

Expected: 0 failures. All remaining specs pass. The crop/upload UI is gone but the model layer, helper rendering, and simplified controllers still work.

- [ ] **Step 2: Verify no dangling references**

```bash
grep -r "image.cropper\|image_cropper\|image.upload\|image_upload\|modal.closer\|modal_closer\|cropped_variant\|_image_crop\|_image_upload_modal\|crop_account_avatar\|save_crop\|cropperjs" app/ config/ spec/ --include="*.rb" --include="*.erb" --include="*.js" --include="*.css" 2>/dev/null
```

Expected: no matches in app/, config/, or spec/ (only matches should be in docs/superpowers/archive/ if any).

- [ ] **Step 3: Start the dev server and manually verify**

```bash
bin/dev
```

Verify:
1. Profile edit page loads without errors — avatar displays correctly
2. Branding edit page loads without errors — workspace logo displays correctly
3. No JavaScript console errors related to missing controllers
4. Browser DevTools Network tab shows no 404s for cropper assets

- [ ] **Step 4: Commit any remaining fixes (if needed)**

If the grep in step 2 found any remaining references, fix them and commit:

```bash
git add -A
git commit -m "fix: clean up remaining references to removed crop UI"
```
