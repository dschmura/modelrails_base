# Optional Image Cropping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional user-directed cropping for uploaded images via a dedicated crop page with CSS-based pan/zoom and server-side ImageProcessing.

**Architecture:** Upload modal stays unchanged. After uploading, a "Crop" link appears next to the image. Clicking it opens a dedicated full-page crop view where the user drags to reposition and scrolls to zoom. Crop coordinates (x, y, w, h) are sent as form params and stored in the Active Storage blob's metadata JSON. At render time, a `cropped_variant` helper reads the metadata and applies `ImageProcessing` crop before resize.

**Tech Stack:** Rails 8.1, Stimulus, CSS transforms, Active Storage blob metadata, ImageProcessing/MiniMagick

**Spec:** `docs/superpowers/specs/2026-04-06-image-crop-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `app/helpers/crop_helper.rb` | Create | `cropped_variant(attachment, resize_to:)` — reads blob metadata, applies crop + resize |
| `app/javascript/controllers/image_crop_controller.js` | Create | Pan/zoom via CSS transforms, coordinate calculation, hidden field output |
| `app/views/shared/_image_crop.html.erb` | Create | Reusable crop page partial (image, overlay, form with hidden fields, buttons) |
| `app/views/account/avatars/crop.html.erb` | Create | Avatar crop page wrapper (renders shared partial) |
| `app/views/workspaces/brandings/crop.html.erb` | Create | Workspace logo crop page wrapper |
| `config/routes.rb` | Modify | Add `crop` and `save_crop` routes for avatar and branding |
| `app/controllers/account/avatars_controller.rb` | Modify | Add `#crop` and `#save_crop` actions |
| `app/controllers/workspaces/brandings_controller.rb` | Modify | Add `#crop` and `#save_crop` actions |
| `app/helpers/avatar_helper.rb` | Modify | Use `cropped_variant` in `render_upload_avatar` |
| `app/helpers/workspace_helper.rb` | Modify | Use `cropped_variant` in `render_workspace_logo` |
| `app/views/account/profiles/edit.html.erb` | Modify | Add "Crop" link next to avatar |
| `app/views/workspaces/brandings/edit.html.erb` | Modify | Add "Crop" link next to logo |
| `config/locales/en/image_crop.en.yml` | Create | I18n keys for crop UI |
| `config/locales/en/account.en.yml` | Modify | Add crop/save_crop keys under avatars |
| `config/locales/en/workspaces.en.yml` | Modify | Add crop/save_crop keys under brandings |
| `spec/helpers/crop_helper_spec.rb` | Create | cropped_variant with/without metadata |
| `spec/requests/account/avatars_spec.rb` | Modify | crop and save_crop request specs |
| `spec/requests/workspaces/brandings_spec.rb` | Modify | crop and save_crop request specs |
| `spec/system/image_crop_spec.rb` | Create | End-to-end crop page system specs |

---

## Task 1: I18n Keys

**Goal:** Define all user-facing strings for the crop feature.

**Files:**

- Create: `config/locales/en/image_crop.en.yml`
- Modify: `config/locales/en/account.en.yml`
- Modify: `config/locales/en/workspaces.en.yml`

- [x] **Step 1: Create `config/locales/en/image_crop.en.yml`**

```yaml
en:
  image_crop:
    instructions: "Drag to reposition. Scroll to zoom."
    save: "Save crop"
    cancel: "Cancel"
    no_image: "Upload an image first."
```

- [x] **Step 2: Add avatar crop keys to `config/locales/en/account.en.yml`**

Add under the existing `avatars:` section, after the `sources:` block:

```yaml
      crop:
        title: "Crop avatar"
        link: "Crop"
      save_crop:
        success: "Avatar cropped."
```

- [x] **Step 3: Add branding crop keys to `config/locales/en/workspaces.en.yml`**

Add under the existing `brandings:` section, after the `update:` block:

```yaml
      crop:
        title: "Crop logo"
        link: "Crop"
      save_crop:
        success: "Logo cropped."
```

- [x] **Step 4: Verify keys load**

```bash
bin/rails runner "puts I18n.t('image_crop.save')"
```

Expected output: `Save crop`

- [x] **Step 5: Commit**

```bash
git add config/locales/en/image_crop.en.yml config/locales/en/account.en.yml config/locales/en/workspaces.en.yml
git commit -m "feat: add I18n keys for image crop feature"
```

---

## Task 2: CropHelper (TDD)

**Goal:** Create the helper that reads crop metadata from a blob and applies it as a variant.

**Files:**

- Create: `spec/helpers/crop_helper_spec.rb`
- Create: `app/helpers/crop_helper.rb`

- [ ] **Step 1: Write specs**

Create `spec/helpers/crop_helper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CropHelper, type: :helper do
  let(:user) { create(:user) }

  before do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
  end

  describe "#cropped_variant" do
    context "without crop metadata" do
      it "returns a variant with resize_to_fill only" do
        variant = helper.cropped_variant(user.avatar, resize_to: [128, 128])
        expect(variant).to be_a(ActiveStorage::VariantWithRecord)
        expect(variant.variation.transformations).to include(resize_to_fill: [128, 128])
        expect(variant.variation.transformations).not_to have_key(:crop)
      end
    end

    context "with crop metadata" do
      before do
        user.avatar.blob.update!(
          metadata: user.avatar.blob.metadata.merge("crop" => { "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
        )
      end

      it "returns a variant with crop and resize_to_fill" do
        variant = helper.cropped_variant(user.avatar, resize_to: [128, 128])
        expect(variant).to be_a(ActiveStorage::VariantWithRecord)
        expect(variant.variation.transformations).to include(
          crop: "100x100+10+20",
          resize_to_fill: [128, 128]
        )
      end
    end

    context "with partial crop metadata" do
      before do
        user.avatar.blob.update!(
          metadata: user.avatar.blob.metadata.merge("crop" => { "x" => 0 })
        )
      end

      it "falls back to resize-only when crop data is incomplete" do
        variant = helper.cropped_variant(user.avatar, resize_to: [128, 128])
        expect(variant.variation.transformations).not_to have_key(:crop)
      end
    end
  end
end
```

- [x] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/helpers/crop_helper_spec.rb
```

- [x] **Step 3: Implement CropHelper**

Create `app/helpers/crop_helper.rb`:

```ruby
module CropHelper
  def cropped_variant(attachment, resize_to:)
    crop = attachment.blob.metadata["crop"]

    if crop.present? && %w[x y w h].all? { |k| crop[k].present? }
      attachment.variant(
        crop: "#{crop['w']}x#{crop['h']}+#{crop['x']}+#{crop['y']}",
        resize_to_fill: resize_to
      )
    else
      attachment.variant(resize_to_fill: resize_to)
    end
  end
end
```

- [x] **Step 4: Run specs (expect green)**

```bash
bundle exec rspec spec/helpers/crop_helper_spec.rb
```

- [x] **Step 5: Commit**

```bash
git add app/helpers/crop_helper.rb spec/helpers/crop_helper_spec.rb
git commit -m "feat: add CropHelper with cropped_variant for blob metadata crops"
```

---

## Task 3: Integrate CropHelper into Avatar and Workspace Helpers

**Goal:** Replace direct `variant(resize_to_fill:)` calls with `cropped_variant` so existing avatars and logos respect crop metadata.

**Files:**

- Modify: `app/helpers/avatar_helper.rb`
- Modify: `app/helpers/workspace_helper.rb`

- [ ] **Step 1: Update `render_upload_avatar` in `app/helpers/avatar_helper.rb`**

Replace line 30:

```ruby
    variant = user.avatar.variant(resize_to_fill: [ config[:px], config[:px] ])
```

With:

```ruby
    variant = cropped_variant(user.avatar, resize_to: [ config[:px], config[:px] ])
```

- [x] **Step 2: Update `render_workspace_logo` in `app/helpers/workspace_helper.rb`**

Replace line 23:

```ruby
    variant = workspace.logo.variant(resize_to_fill: [ config[:px], config[:px] ])
```

With:

```ruby
    variant = cropped_variant(workspace.logo, resize_to: [ config[:px], config[:px] ])
```

- [x] **Step 3: Run existing helper specs to verify no regressions**

```bash
bundle exec rspec spec/helpers/avatar_helper_spec.rb spec/helpers/crop_helper_spec.rb
```

Expected: all pass (no crop metadata on test fixtures means fallback to resize-only — same behavior as before).

- [x] **Step 4: Commit**

```bash
git add app/helpers/avatar_helper.rb app/helpers/workspace_helper.rb
git commit -m "refactor: use cropped_variant in avatar and workspace helpers"
```

---

## Task 4: Routes

**Goal:** Add crop and save_crop routes for avatar and workspace branding.

**Files:**

- Modify: `config/routes.rb`

- [ ] **Step 1: Update avatar routes**

In `config/routes.rb`, replace:

```ruby
resource :avatar, only: [ :update, :destroy ]
```

With:

```ruby
resource :avatar, only: [ :update, :destroy ] do
  get :crop, on: :member
  patch :save_crop, on: :member
end
```

- [x] **Step 2: Update branding routes**

Replace:

```ruby
resource :branding, only: [ :edit, :update ]
```

With:

```ruby
resource :branding, only: [ :edit, :update ] do
  get :crop, on: :member
  patch :save_crop, on: :member
end
```

- [x] **Step 3: Verify routes**

```bash
bin/rails routes | grep crop
```

Expected output should include:

```
crop_account_avatar     GET    /account/avatar/crop(.:format)                   account/avatars#crop
save_crop_account_avatar PATCH /account/avatar/save_crop(.:format)             account/avatars#save_crop
crop_workspace_branding GET    /workspaces/:workspace_slug/branding/crop(.:format) workspaces/brandings#crop
save_crop_workspace_branding PATCH /workspaces/:workspace_slug/branding/save_crop(.:format) workspaces/brandings#save_crop
```

- [x] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add crop and save_crop routes for avatar and branding"
```

---

## Task 5: Image Crop Stimulus Controller

**Goal:** Build the pan/zoom interaction for the crop page. CSS transforms only — no cropping library.

**Files:**

- Create: `app/javascript/controllers/image_crop_controller.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/image_crop_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "container", "x", "y", "w", "h"]
  static values = {
    aspectRatio: { type: Number, default: 1 }
  }

  connect() {
    this.scale = 1
    this.translateX = 0
    this.translateY = 0
    this.dragging = false

    this.imageTarget.addEventListener("load", () => this.#initialize())

    // If image already loaded (cached)
    if (this.imageTarget.complete && this.imageTarget.naturalWidth > 0) {
      this.#initialize()
    }

    this.#bindEvents()
  }

  disconnect() {
    this.#unbindEvents()
  }

  save() {
    this.#calculateCoordinates()
  }

  // Private

  #initialize() {
    this.naturalWidth = this.imageTarget.naturalWidth
    this.naturalHeight = this.imageTarget.naturalHeight

    // Fit image to cover the crop area
    const containerRect = this.containerTarget.getBoundingClientRect()
    const scaleX = containerRect.width / this.naturalWidth
    const scaleY = containerRect.height / this.naturalHeight
    this.minScale = Math.max(scaleX, scaleY)
    this.scale = this.minScale
    this.maxScale = this.minScale * 5

    this.#applyTransform()
  }

  #bindEvents() {
    this._onMouseDown = (e) => this.#startDrag(e.clientX, e.clientY, e)
    this._onMouseMove = (e) => this.#drag(e.clientX, e.clientY, e)
    this._onMouseUp = () => this.#endDrag()
    this._onWheel = (e) => this.#zoom(e)
    this._onTouchStart = (e) => {
      if (e.touches.length === 1) this.#startDrag(e.touches[0].clientX, e.touches[0].clientY, e)
    }
    this._onTouchMove = (e) => {
      if (e.touches.length === 1) this.#drag(e.touches[0].clientX, e.touches[0].clientY, e)
    }
    this._onTouchEnd = () => this.#endDrag()

    this.containerTarget.addEventListener("mousedown", this._onMouseDown)
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
    this.containerTarget.addEventListener("wheel", this._onWheel, { passive: false })
    this.containerTarget.addEventListener("touchstart", this._onTouchStart, { passive: false })
    document.addEventListener("touchmove", this._onTouchMove, { passive: false })
    document.addEventListener("touchend", this._onTouchEnd)
  }

  #unbindEvents() {
    this.containerTarget.removeEventListener("mousedown", this._onMouseDown)
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
    this.containerTarget.removeEventListener("wheel", this._onWheel)
    this.containerTarget.removeEventListener("touchstart", this._onTouchStart)
    document.removeEventListener("touchmove", this._onTouchMove)
    document.removeEventListener("touchend", this._onTouchEnd)
  }

  #startDrag(clientX, clientY, event) {
    event.preventDefault()
    this.dragging = true
    this.dragStartX = clientX - this.translateX
    this.dragStartY = clientY - this.translateY
    this.containerTarget.style.cursor = "grabbing"
  }

  #drag(clientX, clientY, event) {
    if (!this.dragging) return
    event.preventDefault()
    this.translateX = clientX - this.dragStartX
    this.translateY = clientY - this.dragStartY
    this.#clampTranslation()
    this.#applyTransform()
  }

  #endDrag() {
    this.dragging = false
    this.containerTarget.style.cursor = "grab"
  }

  #zoom(event) {
    event.preventDefault()
    const delta = event.deltaY > 0 ? -0.1 : 0.1
    const newScale = Math.min(this.maxScale, Math.max(this.minScale, this.scale + delta))

    // Zoom toward center
    const ratio = newScale / this.scale
    this.translateX *= ratio
    this.translateY *= ratio
    this.scale = newScale

    this.#clampTranslation()
    this.#applyTransform()
  }

  #clampTranslation() {
    const containerRect = this.containerTarget.getBoundingClientRect()
    const scaledW = this.naturalWidth * this.scale
    const scaledH = this.naturalHeight * this.scale
    const maxX = (scaledW - containerRect.width) / 2
    const maxY = (scaledH - containerRect.height) / 2

    this.translateX = Math.min(maxX, Math.max(-maxX, this.translateX))
    this.translateY = Math.min(maxY, Math.max(-maxY, this.translateY))
  }

  #applyTransform() {
    this.imageTarget.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
  }

  #calculateCoordinates() {
    const containerRect = this.containerTarget.getBoundingClientRect()

    // The visible center of the container maps to the crop center
    // Convert screen-space crop area to image-space coordinates
    const cropScreenW = containerRect.width
    const cropScreenH = containerRect.height

    // Image-space position of the top-left corner of the visible area
    const imgX = (cropScreenW / 2 - this.translateX) / this.scale - cropScreenW / (2 * this.scale)
    const imgY = (cropScreenH / 2 - this.translateY) / this.scale - cropScreenH / (2 * this.scale)
    const imgW = cropScreenW / this.scale
    const imgH = cropScreenH / this.scale

    // Clamp to image bounds
    const x = Math.max(0, Math.round(imgX))
    const y = Math.max(0, Math.round(imgY))
    const w = Math.min(Math.round(imgW), this.naturalWidth - x)
    const h = Math.min(Math.round(imgH), this.naturalHeight - y)

    this.xTarget.value = x
    this.yTarget.value = y
    this.wTarget.value = w
    this.hTarget.value = h
  }
}
```

- [x] **Step 2: Commit**

```bash
git add app/javascript/controllers/image_crop_controller.js
git commit -m "feat: add image crop Stimulus controller with pan/zoom via CSS transforms"
```

---

## Task 6: Shared Crop Page Partial

**Goal:** Build the reusable ERB partial that any controller can render for its crop page.

**Files:**

- Create: `app/views/shared/_image_crop.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_image_crop.html.erb`:

```erb
<%# locals: (image:, aspect_ratio: 1.0, shape: :circle, save_url:, cancel_url:, title:) -%>
<%
  overlay_class = shape == :circle ? "rounded-full" : "rounded-md"
%>

<div class="max-w-2xl mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading mb-6">
    <%= title %>
  </h1>

  <%= form_with url: save_url, method: :patch, class: "space-y-6" do |f| %>
    <div data-controller="image-crop"
         data-image-crop-aspect-ratio-value="<%= aspect_ratio %>">

      <%# Crop viewport — fixed aspect ratio, overflow hidden %>
      <div data-image-crop-target="container"
           class="relative overflow-hidden bg-surface-sunken rounded-lg cursor-grab select-none"
           style="aspect-ratio: <%= aspect_ratio %>; max-height: 60vh;">

        <%# The image — positioned via CSS transforms %>
        <%= image_tag url_for(image),
              data: { image_crop_target: "image" },
              class: "absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 max-w-none",
              draggable: false,
              alt: title %>

        <%# Crop overlay — shows the visible crop area %>
        <div class="absolute inset-0 pointer-events-none">
          <div class="absolute inset-0 bg-black/40"></div>
          <div class="absolute inset-[10%] <%= overlay_class %>"
               style="box-shadow: 0 0 0 9999px rgba(0,0,0,0.4);">
          </div>
        </div>
      </div>

      <p class="text-sm text-text-muted text-center">
        <%= t("image_crop.instructions") %>
      </p>

      <%# Hidden fields for crop coordinates %>
      <input type="hidden" name="crop[x]" value="0" data-image-crop-target="x">
      <input type="hidden" name="crop[y]" value="0" data-image-crop-target="y">
      <input type="hidden" name="crop[w]" value="0" data-image-crop-target="w">
      <input type="hidden" name="crop[h]" value="0" data-image-crop-target="h">

      <%# Buttons %>
      <div class="flex flex-col sm:flex-row gap-3">
        <button type="submit"
                data-action="click->image-crop#save"
                class="inline-flex items-center justify-center flex-1
                       min-h-[44px] px-6 py-2 rounded-md
                       text-sm font-semibold text-white
                       bg-interactive hover:bg-interactive-hover
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus">
          <%= t("image_crop.save") %>
        </button>
        <%= link_to t("image_crop.cancel"), cancel_url,
              class: "inline-flex items-center justify-center flex-1
                     min-h-[44px] px-4 py-2 rounded-md
                     border border-border text-sm font-medium text-text-body
                     hover:bg-surface-sunken text-center
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus" %>
      </div>
    </div>
  <% end %>
</div>
```

- [x] **Step 2: Verify the partial renders**

```bash
bin/rails runner "puts 'Partial file exists: ' + File.exist?(Rails.root.join('app/views/shared/_image_crop.html.erb')).to_s"
```

- [x] **Step 3: Commit**

```bash
git add app/views/shared/_image_crop.html.erb
git commit -m "feat: add reusable crop page partial with pan/zoom overlay"
```

---

## Task 7: Avatar Crop Controller Actions (TDD)

**Goal:** Add `#crop` and `#save_crop` actions to the avatars controller.

**Files:**

- Modify: `spec/requests/account/avatars_spec.rb`
- Modify: `app/controllers/account/avatars_controller.rb`
- Create: `app/views/account/avatars/crop.html.erb`

- [ ] **Step 1: Write request specs**

Add to `spec/requests/account/avatars_spec.rb`, inside the `authenticated` context:

```ruby
    describe "GET /account/avatar/crop" do
      it "renders the crop page when avatar is attached" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        get crop_account_avatar_path
        expect(response).to have_http_status(:ok)
      end

      it "redirects when no avatar is attached" do
        get crop_account_avatar_path
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    describe "PATCH /account/avatar/save_crop" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
      end

      it "saves crop coordinates to blob metadata" do
        patch save_crop_account_avatar_path, params: { crop: { x: 10, y: 20, w: 100, h: 100 } }
        metadata = user.avatar.blob.reload.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "redirects when no avatar is attached" do
        user.avatar.purge
        patch save_crop_account_avatar_path, params: { crop: { x: 0, y: 0, w: 50, h: 50 } }
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
```

- [x] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb
```

- [x] **Step 3: Create the crop view**

Create `app/views/account/avatars/crop.html.erb`:

```erb
<% content_for(:title) { t("account.avatars.crop.title") } %>
<%= render "shared/image_crop",
      image: Current.user.avatar,
      aspect_ratio: 1.0,
      shape: :circle,
      save_url: save_crop_account_avatar_path,
      cancel_url: edit_account_profile_path,
      title: t("account.avatars.crop.title") %>
```

- [x] **Step 4: Add controller actions**

Add to `app/controllers/account/avatars_controller.rb`, before the `update` method:

```ruby
    def crop
      unless Current.user.avatar.attached?
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        return
      end
    end

    def save_crop
      unless Current.user.avatar.attached?
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        return
      end

      crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
      blob = Current.user.avatar.blob
      blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))
      redirect_to edit_account_profile_path, notice: t(".success")
    end
```

- [x] **Step 5: Run specs (expect green)**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/account/avatars_controller.rb app/views/account/avatars/crop.html.erb spec/requests/account/avatars_spec.rb
git commit -m "feat: add avatar crop and save_crop controller actions"
```

---

## Task 8: Workspace Logo Crop Controller Actions (TDD)

**Goal:** Add `#crop` and `#save_crop` actions to the brandings controller.

**Files:**

- Modify: `spec/requests/workspaces/brandings_spec.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Create: `app/views/workspaces/brandings/crop.html.erb`

- [ ] **Step 1: Write request specs**

Add to `spec/requests/workspaces/brandings_spec.rb`, inside the `authenticated` context:

```ruby
    describe "GET /workspaces/:slug/branding/crop" do
      it "renders the crop page when logo is attached" do
        workspace.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png", content_type: "image/png"
        )
        get crop_workspace_branding_path(workspace)
        expect(response).to have_http_status(:ok)
      end

      it "redirects when no logo is attached" do
        get crop_workspace_branding_path(workspace)
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end

    describe "PATCH /workspaces/:slug/branding/save_crop" do
      before do
        workspace.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png", content_type: "image/png"
        )
      end

      it "saves crop coordinates to blob metadata" do
        patch save_crop_workspace_branding_path(workspace), params: { crop: { x: 5, y: 10, w: 80, h: 80 } }
        metadata = workspace.logo.blob.reload.metadata
        expect(metadata["crop"]).to eq("x" => 5, "y" => 10, "w" => 80, "h" => 80)
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end
```

- [x] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/requests/workspaces/brandings_spec.rb
```

- [x] **Step 3: Create the crop view**

Create `app/views/workspaces/brandings/crop.html.erb`:

```erb
<% content_for(:title) { t("workspaces.brandings.crop.title") } %>
<%= render "shared/image_crop",
      image: @workspace.logo,
      aspect_ratio: 1.0,
      shape: :circle,
      save_url: save_crop_workspace_branding_path(@workspace),
      cancel_url: edit_workspace_branding_path(@workspace),
      title: t("workspaces.brandings.crop.title") %>
```

- [x] **Step 4: Add controller actions**

Add to `app/controllers/workspaces/brandings_controller.rb`, before the `update` method:

```ruby
    def crop
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
      unless @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), alert: t("image_crop.no_image")
        return
      end
    end

    def save_crop
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
      unless @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), alert: t("image_crop.no_image")
        return
      end

      crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
      blob = @workspace.logo.blob
      blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))
      redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
    end
```

- [x] **Step 5: Run specs (expect green)**

```bash
bundle exec rspec spec/requests/workspaces/brandings_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/workspaces/brandings_controller.rb app/views/workspaces/brandings/crop.html.erb spec/requests/workspaces/brandings_spec.rb
git commit -m "feat: add workspace logo crop and save_crop controller actions"
```

---

## Task 9: Add "Crop" Links to Profile and Branding Pages

**Goal:** Show a "Crop" link next to the avatar/logo when an image is attached.

**Files:**

- Modify: `app/views/account/profiles/edit.html.erb`
- Modify: `app/views/workspaces/brandings/edit.html.erb`

- [ ] **Step 1: Add crop link to profile page**

In `app/views/account/profiles/edit.html.erb`, after the "Change avatar" button (line 18), add:

```erb
      <% if @user.avatar.attached? %>
        <%= link_to t("account.avatars.crop.link"), crop_account_avatar_path,
              class: "text-sm text-interactive underline hover:no-underline mt-1
                     min-h-[44px] min-w-[44px] inline-flex items-center
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
      <% end %>
```

- [x] **Step 2: Add crop link to branding page**

In `app/views/workspaces/brandings/edit.html.erb`, after the "Change logo" button, add:

```erb
        <% if @workspace.logo.attached? %>
          <%= link_to t("workspaces.brandings.crop.link"), crop_workspace_branding_path(@workspace),
                class: "text-sm text-interactive underline hover:no-underline
                       min-h-[44px] min-w-[44px] inline-flex items-center
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
        <% end %>
```

- [x] **Step 3: Commit**

```bash
git add app/views/account/profiles/edit.html.erb app/views/workspaces/brandings/edit.html.erb
git commit -m "feat: add Crop links to profile and branding pages"
```

---

## Task 10: System Specs

**Goal:** End-to-end specs testing the real crop page.

**Files:**

- Create: `spec/system/image_crop_spec.rb`

- [ ] **Step 1: Write system specs**

Create `spec/system/image_crop_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Image cropping", type: :system do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  def dismiss_banner
    page.execute_script("document.querySelector('[data-biscuit-target=\"banner\"]')?.remove()")
  end

  describe "avatar crop page" do
    before do
      user.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png", content_type: "image/png"
      )
      user.update_columns(avatar_source: "upload")
      sign_in_via_form(user)
    end

    it "shows crop page with image and buttons" do
      visit crop_account_avatar_path
      dismiss_banner
      expect(page).to have_text(I18n.t("account.avatars.crop.title"))
      expect(page).to have_css("[data-controller='image-crop']")
      expect(page).to have_css("img[data-image-crop-target='image']")
      expect(page).to have_button(I18n.t("image_crop.save"))
      expect(page).to have_link(I18n.t("image_crop.cancel"))
    end

    it "saves crop and redirects to profile" do
      visit crop_account_avatar_path
      dismiss_banner
      click_button I18n.t("image_crop.save")
      expect(page).to have_text(I18n.t("account.avatars.save_crop.success"), wait: 5)
    end

    it "cancel returns to profile without saving" do
      visit crop_account_avatar_path
      dismiss_banner
      click_link I18n.t("image_crop.cancel")
      expect(page).to have_current_path(edit_account_profile_path)
    end

    it "shows crop link on profile page" do
      visit edit_account_profile_path
      dismiss_banner
      expect(page).to have_link(I18n.t("account.avatars.crop.link"))
    end
  end
end
```

- [x] **Step 2: Run system specs**

```bash
bundle exec rspec spec/system/image_crop_spec.rb
```

- [x] **Step 3: Commit**

```bash
git add spec/system/image_crop_spec.rb
git commit -m "test: add system specs for image crop page"
```

---

## Task 11: Full Test Suite Verification

**Goal:** Verify no regressions across the entire codebase.

- [ ] **Step 1: Run full non-system test suite**

```bash
bundle exec rspec --exclude-pattern "spec/system/**/*_spec.rb" --format progress
```

Expected: all pass with 0 failures.

- [x] **Step 2: Run all new and related system specs**

```bash
bundle exec rspec spec/system/image_crop_spec.rb spec/system/image_upload_modal_spec.rb spec/system/avatar_spec.rb --format progress
```

Expected: all pass with 0 failures.

- [x] **Step 3: Fix any failures before proceeding**

If any specs fail, investigate and fix. Common issues:

- **Route helper not found:** Ensure `config/routes.rb` changes are correct and `crop` / `save_crop` routes are inside the `do...end` block.
- **Missing view template:** Ensure `app/views/account/avatars/crop.html.erb` exists (not in a `brandings` subdirectory or vice versa).
- **Blob metadata not persisting:** `blob.update!` requires `reload` in specs — use `user.avatar.blob.reload.metadata`.

---

## Dependencies

- **ImageProcessing gem** — already in Gemfile (`gem "image_processing", "~> 1.2"`)
- **Active Storage** — already configured
- **No new gems required**

## Developer Notes

- **Crop coordinates are integers** in image-space pixels. The Stimulus controller converts CSS transform values to image coordinates before submitting.
- **The crop overlay uses `box-shadow: 0 0 0 9999px rgba(0,0,0,0.4)`** to dim the area outside the crop region. The inner div is the "window" — everything outside it is darkened.
- **Re-uploading an image clears crop metadata** automatically because a new blob is created with fresh metadata.
- **The `cropped_variant` helper falls back gracefully** — if no crop metadata exists, it behaves identically to the original `variant(resize_to_fill:)` call.
