# Identity Picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared identity picker modal for managing user avatars and workspace logos with client-side cropping, dual-attachment storage, and an OKLCH color picker for initials.

**Architecture:** A shared `_identity_picker` partial renders a three-view modal (main/crop/upload) controlled by the existing `mode_switch_controller`. A new `identity_picker_controller` handles source selection, color picker sync, and client-side canvas crop export. Models store both the cropped display image and the original upload as separate ActiveStorage attachments.

**Tech Stack:** Rails 8.1, Stimulus, Turbo Streams, Cropper.js v1, ActiveStorage, OKLCH CSS gradients, TDD with RSpec + Capybara/Playwright.

**Spec:** `docs/superpowers/specs/2026-04-07-identity-picker-design.md`

**User requirement:** TDD (spec-first) for every task. Update documentation when complete.

---

## File Structure

### Create

| File | Responsibility |
|------|---------------|
| `app/javascript/controllers/identity_picker_controller.js` | Source radio selection, color picker sync, canvas export + FormData submission |
| `app/views/shared/_identity_picker.html.erb` | Three-view modal interior (main/crop/upload) with source cards and color picker |
| `app/views/shared/_identity_source_card.html.erb` | Single radio card partial for a source option |
| `app/assets/stylesheets/vendor/hue-slider.css` | OKLCH gradient background + thumb styling for hue range input |
| `config/locales/en/identity_picker.en.yml` | Shared i18n strings for the picker UI |

### Modify

| File | Change |
|------|--------|
| `app/models/user.rb` | Add `has_one_attached :avatar_original`, validation |
| `app/models/workspace.rb` | Add `has_one_attached :logo_original` |
| `app/helpers/avatar_helper.rb` | Serve `avatar` directly (no `cropped_variant`) with fallback chain |
| `app/helpers/workspace_helper.rb` | Serve `logo` directly with fallback chain |
| `app/controllers/account/avatars_controller.rb` | Handle cropped blob + original in `save_crop`, dual-attachment in `update` |
| `app/controllers/workspaces/brandings_controller.rb` | Same dual-attachment pattern |
| `app/javascript/controllers/image_cropper_controller.js` | Add `exportCroppedBlob()` method |
| `app/views/account/profiles/edit.html.erb` | Replace modal content with `render "shared/identity_picker"` |
| `app/views/workspaces/brandings/edit.html.erb` | Same |
| `app/views/layouts/application.html.erb` | Add hue-slider CSS link |

### Test

| File | Purpose |
|------|--------|
| `spec/models/user_spec.rb` | `avatar_original` attachment specs |
| `spec/models/workspace_spec.rb` | `logo_original` attachment specs |
| `spec/requests/account/avatars_spec.rb` | Dual-attachment save, cropped blob upload |
| `spec/requests/workspaces/brandings_spec.rb` | Same |
| `spec/system/identity_picker_spec.rb` | New — end-to-end modal flows |
| `spec/helpers/avatar_helper_spec.rb` | Updated for direct serving |

---

## Task 1: Add `avatar_original` and `logo_original` attachments to models

**Files:**
- Modify: `app/models/user.rb`
- Modify: `app/models/workspace.rb`
- Test: `spec/models/user_spec.rb`, `spec/models/workspace_spec.rb`

- [ ] **Step 1: Write failing model spec for User avatar_original**

Add to `spec/models/user_spec.rb`:

```ruby
describe "avatar_original attachment" do
  let(:user) { create(:user) }

  it "accepts an avatar_original attachment" do
    user.avatar_original.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "original.png",
      content_type: "image/png"
    )
    expect(user.avatar_original).to be_attached
  end

  it "validates content type of avatar_original" do
    user.avatar_original.attach(
      io: StringIO.new("not an image"),
      filename: "doc.txt",
      content_type: "text/plain"
    )
    expect(user).not_to be_valid
    expect(user.errors[:avatar_original]).to be_present
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb -e "avatar_original" --format documentation
```

Expected: FAIL — `avatar_original` method not found.

- [ ] **Step 3: Add avatar_original to User model**

In `app/models/user.rb`, after `has_one_attached :avatar`:

```ruby
has_one_attached :avatar_original
```

And add validation after the existing `validates :avatar` block:

```ruby
validates :avatar_original,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 10.megabytes }
```

(10MB limit for originals since they won't be cropped server-side.)

- [ ] **Step 4: Run spec to verify it passes**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb -e "avatar_original" --format documentation
```

Expected: PASS.

- [ ] **Step 5: Write failing spec for Workspace logo_original**

Add to `spec/models/workspace_spec.rb`:

```ruby
describe "logo_original attachment" do
  let(:workspace) { create(:workspace) }

  it "accepts a logo_original attachment" do
    workspace.logo_original.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "original.png",
      content_type: "image/png"
    )
    expect(workspace.logo_original).to be_attached
  end
end
```

- [ ] **Step 6: Add logo_original to Workspace model**

In `app/models/workspace.rb`, after `has_one_attached :logo`:

```ruby
has_one_attached :logo_original
```

- [ ] **Step 7: Run both specs**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb -e "avatar_original" spec/models/workspace_spec.rb -e "logo_original" --format documentation
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
mise exec -- git add app/models/user.rb app/models/workspace.rb spec/models/user_spec.rb spec/models/workspace_spec.rb
mise exec -- git commit -m "feat: add avatar_original and logo_original attachments for dual-storage"
```

---

## Task 2: Update avatar helper to serve directly (with fallback)

**Files:**
- Modify: `app/helpers/avatar_helper.rb`
- Modify: `app/helpers/workspace_helper.rb`
- Test: `spec/helpers/avatar_helper_spec.rb`

- [ ] **Step 1: Write failing spec for direct-serve avatar**

Add to `spec/helpers/avatar_helper_spec.rb`:

```ruby
describe "upload avatar with avatar_original" do
  let(:user) { create(:user, avatar_source: "upload") }

  before do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "cropped.png",
      content_type: "image/png"
    )
  end

  it "serves avatar directly without cropped_variant" do
    result = helper.avatar_for(user, size: :md)
    # Should contain an img tag with a direct blob URL, not a variant URL
    expect(result).to include("<img")
    expect(result).not_to include("variants")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
mise exec -- bundle exec rspec spec/helpers/avatar_helper_spec.rb -e "avatar_original" --format documentation
```

Expected: FAIL — current code calls `cropped_variant` which generates a variant URL.

- [ ] **Step 3: Update avatar helper**

Replace the `render_upload_avatar` method in `app/helpers/avatar_helper.rb`:

```ruby
def render_upload_avatar(user, config, aria_label)
  return render_initials_avatar(user, config, aria_label) unless user.avatar.attached?

  image_tag user.avatar.representation(resize_to_fill: [config[:px], config[:px]]),
    class: "#{config[:css]} rounded-full object-cover",
    **avatar_aria_attrs(aria_label, alt: "")
end
```

Note: We use `representation(resize_to_fill:)` to serve at the right size, but WITHOUT applying crop coordinates — the avatar attachment is already the cropped image. If `avatar_original` exists, the avatar IS the cropped version. If only `avatar` exists (legacy), `resize_to_fill` handles it.

- [ ] **Step 4: Update workspace helper similarly**

In `app/helpers/workspace_helper.rb`, update `render_workspace_logo`:

```ruby
def render_workspace_logo(workspace, config)
  image_tag workspace.logo.representation(resize_to_fill: [config[:px], config[:px]]),
    class: "#{config[:css]} rounded-full object-cover",
    alt: workspace.name,
    aria: { hidden: true }
end
```

- [ ] **Step 5: Run all helper and avatar specs**

```bash
mise exec -- bundle exec rspec spec/helpers/ spec/system/avatar_spec.rb --format progress
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
mise exec -- git add app/helpers/avatar_helper.rb app/helpers/workspace_helper.rb spec/helpers/avatar_helper_spec.rb
mise exec -- git commit -m "feat: serve avatar/logo directly via resize_to_fill instead of cropped_variant"
```

---

## Task 3: Add canvas export to image_cropper_controller

**Files:**
- Modify: `app/javascript/controllers/image_cropper_controller.js`

- [ ] **Step 1: Add exportCroppedBlob method**

Add this public method to `image_cropper_controller.js` after the `save()` method:

```javascript
  // Export the cropped region as a Blob via canvas.
  // Returns a Promise that resolves with { blob, coordinates }.
  exportCroppedBlob({ width = 512, height = 512, type = "image/png" } = {}) {
    return new Promise((resolve, reject) => {
      if (!this.cropper) return reject(new Error("Cropper not initialized"))

      const data = this.cropper.getData(true)
      const canvas = this.cropper.getCroppedCanvas({ width, height })

      if (!canvas) return reject(new Error("Failed to create cropped canvas"))

      canvas.toBlob((blob) => {
        if (!blob) return reject(new Error("Failed to create blob"))
        resolve({
          blob,
          coordinates: { x: data.x, y: data.y, w: data.width, h: data.height }
        })
      }, type)
    })
  }
```

- [ ] **Step 2: Verify existing specs still pass**

```bash
mise exec -- bundle exec rspec spec/system/image_crop_spec.rb --format progress
```

Expected: all pass (we only added a method, didn't change existing behavior).

- [ ] **Step 3: Commit**

```bash
mise exec -- git add app/javascript/controllers/image_cropper_controller.js
mise exec -- git commit -m "feat: add exportCroppedBlob() to image-cropper controller for client-side crop"
```

---

## Task 4: Create hue slider CSS and identity picker locale

**Files:**
- Create: `app/assets/stylesheets/vendor/hue-slider.css`
- Create: `config/locales/en/identity_picker.en.yml`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Create the hue slider CSS**

Create `app/assets/stylesheets/vendor/hue-slider.css`:

```css
/* OKLCH hue slider — full 360° hue wheel at fixed lightness/chroma */
input[type="range"].hue-slider {
  -webkit-appearance: none;
  appearance: none;
  width: 100%;
  height: 12px;
  border-radius: 6px;
  outline: none;
  background: linear-gradient(
    to right,
    oklch(0.65 0.15 0),
    oklch(0.65 0.15 30),
    oklch(0.65 0.15 60),
    oklch(0.65 0.15 90),
    oklch(0.65 0.15 120),
    oklch(0.65 0.15 150),
    oklch(0.65 0.15 180),
    oklch(0.65 0.15 210),
    oklch(0.65 0.15 240),
    oklch(0.65 0.15 270),
    oklch(0.65 0.15 300),
    oklch(0.65 0.15 330),
    oklch(0.65 0.15 360)
  );
}

input[type="range"].hue-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: white;
  border: 2px solid var(--color-border-strong, #475569);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
  cursor: pointer;
}

input[type="range"].hue-slider::-moz-range-thumb {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: white;
  border: 2px solid var(--color-border-strong, #475569);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
  cursor: pointer;
}

input[type="range"].hue-slider:focus-visible::-webkit-slider-thumb {
  outline: 2px solid var(--color-interactive-focus);
  outline-offset: 2px;
}

input[type="range"].hue-slider:focus-visible::-moz-range-thumb {
  outline: 2px solid var(--color-interactive-focus);
  outline-offset: 2px;
}
```

- [ ] **Step 2: Add stylesheet link to layout**

In `app/views/layouts/application.html.erb`, after the cropper CSS link:

```erb
<%= stylesheet_link_tag "vendor/hue-slider", "data-turbo-track": "reload" %>
```

- [ ] **Step 3: Create identity picker locale file**

Create `config/locales/en/identity_picker.en.yml`:

```yaml
en:
  identity_picker:
    sources:
      upload: "Photo"
      initials: "Initials"
    actions:
      upload_new: "Upload photo"
      edit_crop: "Edit crop"
      delete: "Remove photo"
      delete_confirm: "Are you sure you want to remove this photo?"
    color_picker:
      label: "Color"
      aria_label: "Choose initials color"
    metadata:
      last_updated: "Last updated %{time}"
      never_updated: "Not set"
    crop:
      save: "Save & apply"
      cancel: "Cancel"
      upload_instead: "Upload new instead"
    upload:
      title: "Upload a photo"
      drop_zone: "Click to upload or drag and drop"
      constraints: "%{types} up to %{max_size}MB"
```

- [ ] **Step 4: Commit**

```bash
mise exec -- git add app/assets/stylesheets/vendor/hue-slider.css config/locales/en/identity_picker.en.yml app/views/layouts/application.html.erb
mise exec -- git commit -m "feat: add OKLCH hue slider CSS and identity picker locale strings"
```

---

## Task 5: Create the identity_picker Stimulus controller

**Files:**
- Create: `app/javascript/controllers/identity_picker_controller.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/identity_picker_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "sourceCard",          // Each radio card
    "uploadActions",       // Upload/Edit/Delete button group
    "initialsActions",     // Color picker section
    "displayAvatar",       // Large identity display at top
    "initialsPreview",     // Small color circle in initials radio card
    "displayInitials",     // Large initials circle at top when initials selected
    "hueSlider",           // Range input for hue
    "huePreview",          // Preview bar below slider
    "colorField",          // Hidden field for color value
    "editButton",          // Edit crop button (disabled when no image)
    "deleteButton"         // Delete button (disabled when no image)
  ]

  static values = {
    source: { type: String, default: "initials" },
    hue: { type: Number, default: 210 },
    hasImage: { type: Boolean, default: false }
  }

  connect() {
    this.#syncActionsVisibility()
    this.#syncButtonStates()
    this.#applyHueColor()
  }

  selectSource(event) {
    this.sourceValue = event.currentTarget.value || event.params.source
    this.#syncActionsVisibility()
    this.#syncButtonStates()
  }

  updateHue(event) {
    this.hueValue = parseInt(event.currentTarget.value)
    this.#applyHueColor()
  }

  async saveCrop() {
    // Find the image-cropper controller in the crop view
    const cropperEl = this.element.querySelector("[data-controller~='image-cropper']")
    if (!cropperEl) return

    const cropperController = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
    if (!cropperController) return

    try {
      const { blob, coordinates } = await cropperController.exportCroppedBlob({
        width: 512, height: 512, type: "image/png"
      })

      const formData = new FormData()
      formData.append("cropped_image", blob, "cropped.png")
      formData.append("crop[x]", coordinates.x)
      formData.append("crop[y]", coordinates.y)
      formData.append("crop[w]", coordinates.w)
      formData.append("crop[h]", coordinates.h)

      const saveUrl = this.element.dataset.identityPickerSaveUrlValue
      const token = document.querySelector("meta[name='csrf-token']")?.content

      const response = await fetch(saveUrl, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: formData
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error("identity-picker: crop save failed", error)
    }
  }

  // Private

  #syncActionsVisibility() {
    if (this.hasUploadActionsTarget) {
      this.uploadActionsTarget.hidden = this.sourceValue !== "upload"
    }
    if (this.hasInitialsActionsTarget) {
      this.initialsActionsTarget.hidden = this.sourceValue !== "initials"
    }
  }

  #syncButtonStates() {
    if (this.hasEditButtonTarget) {
      this.editButtonTarget.disabled = !this.hasImageValue
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.disabled = !this.hasImageValue
    }
  }

  #applyHueColor() {
    const color = `oklch(0.65 0.15 ${this.hueValue})`

    if (this.hasHuePreviewTarget) {
      this.huePreviewTarget.style.backgroundColor = color
    }
    if (this.hasInitialsPreviewTarget) {
      this.initialsPreviewTarget.style.backgroundColor = color
    }
    if (this.hasDisplayInitialsTarget) {
      this.displayInitialsTarget.style.backgroundColor = color
    }
    if (this.hasColorFieldTarget) {
      // Convert OKLCH to hex for storage (approximate)
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = 1
      const ctx = canvas.getContext("2d")
      ctx.fillStyle = color
      ctx.fillRect(0, 0, 1, 1)
      const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data
      this.colorFieldTarget.value = `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)}`
    }
  }
}
```

- [ ] **Step 2: Verify it auto-registers**

```bash
mise exec -- bundle exec rspec spec/system/avatar_spec.rb --format progress
```

Expected: existing specs still pass (controller exists but isn't connected to any views yet).

- [ ] **Step 3: Commit**

```bash
mise exec -- git add app/javascript/controllers/identity_picker_controller.js
mise exec -- git commit -m "feat: add identity_picker Stimulus controller — source selection, color picker, canvas export"
```

---

## Task 6: Create the source card partial

**Files:**
- Create: `app/views/shared/_identity_source_card.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_identity_source_card.html.erb`:

```erb
<%# locals: (source:, label:, selected:, preview_content:, name: "identity_source") -%>

<label class="flex items-center gap-3 p-3 rounded-lg border-2 cursor-pointer transition-colors
              min-h-[44px]
              <%= selected ? 'border-interactive bg-interactive/5' : 'border-border hover:border-border-strong' %>"
       data-identity-picker-target="sourceCard">
  <input type="radio"
         name="<%= name %>"
         value="<%= source %>"
         <%= "checked" if selected %>
         data-action="change->identity-picker#selectSource"
         class="size-4 text-interactive focus:ring-2 focus:ring-interactive-focus">
  <span class="flex-1 text-sm font-medium text-text-body">
    <%= label %>
  </span>
  <span class="shrink-0">
    <%= preview_content %>
  </span>
</label>
```

- [ ] **Step 2: Commit**

```bash
mise exec -- git add app/views/shared/_identity_source_card.html.erb
mise exec -- git commit -m "feat: add identity source card partial — radio card with inline preview"
```

---

## Task 7: Create the identity picker partial

**Files:**
- Create: `app/views/shared/_identity_picker.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/shared/_identity_picker.html.erb`:

```erb
<%# locals: (title:, record:, image_attachment: :avatar, original_attachment: :avatar_original,
             save_url:, sources: [:upload, :initials], current_source: "initials",
             color_field: :primary_color, aspect_ratio: 1.0, shape: :circle,
             initials: nil, current_color: nil) -%>
<%
  image = record.send(image_attachment)
  original = record.send(original_attachment)
  has_image = image.attached?
  existing_crop = original.attached? ? (original.blob.metadata["crop"] || {}) : {}
  display_initials = initials || record.initials
  display_color = current_color || record.try(:primary_color) || "#0284c7"
  hue = color_to_hue(display_color)
  preview_class = shape == :circle ? "rounded-full" : "rounded-md"
  initial_mode = has_image && current_source == "upload" ? "main" : (has_image ? "main" : "upload")
%>

<div data-controller="identity-picker mode-switch"
     data-identity-picker-source-value="<%= current_source %>"
     data-identity-picker-hue-value="<%= hue %>"
     data-identity-picker-has-image-value="<%= has_image %>"
     data-identity-picker-save-url-value="<%= save_url %>"
     data-mode-switch-mode-value="<%= initial_mode %>">

  <%# ═══ VIEW: MAIN ═══ %>
  <div data-mode-switch-target="section" data-mode="main">

    <%# Current identity display %>
    <div class="flex flex-col items-center py-4">
      <% if has_image && current_source == "upload" %>
        <div data-identity-picker-target="displayAvatar">
          <%= image_tag url_for(image),
                class: "w-24 h-24 #{preview_class} object-cover border-2 border-border",
                alt: title %>
        </div>
      <% else %>
        <div data-identity-picker-target="displayInitials"
             class="w-24 h-24 <%= preview_class %> flex items-center justify-center
                    text-2xl font-bold text-white"
             style="background-color: <%= display_color %>;">
          <%= display_initials %>
        </div>
      <% end %>
      <p class="text-xs text-text-muted mt-2">
        <% if has_image %>
          <%= t("identity_picker.metadata.last_updated",
                time: record.updated_at.today? ? "today" : record.updated_at.strftime("%B %d, %Y")) %>
        <% else %>
          <%= t("identity_picker.metadata.never_updated") %>
        <% end %>
      </p>
    </div>

    <%# Source selection cards %>
    <div class="space-y-2 mt-2">
      <% if sources.include?(:upload) %>
        <%= render "shared/identity_source_card",
              source: "upload",
              label: t("identity_picker.sources.upload"),
              selected: current_source == "upload",
              preview_content: (has_image ?
                image_tag(url_for(image), class: "w-8 h-8 #{preview_class} object-cover", alt: "") :
                content_tag(:span, "", class: "block w-8 h-8 #{preview_class} bg-surface-sunken border border-border-strong")) %>
      <% end %>

      <% if sources.include?(:initials) %>
        <%= render "shared/identity_source_card",
              source: "initials",
              label: t("identity_picker.sources.initials"),
              selected: current_source == "initials",
              preview_content: content_tag(:span, display_initials,
                class: "block w-8 h-8 #{preview_class} flex items-center justify-center text-xs font-bold text-white",
                style: "background-color: #{display_color};",
                data: { identity_picker_target: "initialsPreview" }) %>
      <% end %>
    </div>

    <%# Contextual actions — upload source %>
    <div data-identity-picker-target="uploadActions"
         class="mt-4 flex gap-2"
         <%= "hidden" unless current_source == "upload" %>>
      <button type="button"
              data-action="click->mode-switch#switchTo"
              data-mode-switch-mode-param="upload"
              class="flex-1 inline-flex items-center justify-center gap-2
                     min-h-[44px] px-4 py-2 rounded-md border border-border
                     text-sm font-medium text-text-body
                     hover:bg-surface-sunken
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= t("identity_picker.actions.upload_new") %>
      </button>
      <button type="button"
              data-action="click->mode-switch#switchTo"
              data-mode-switch-mode-param="crop"
              data-identity-picker-target="editButton"
              <%= "disabled" unless has_image %>
              class="flex-1 inline-flex items-center justify-center gap-2
                     min-h-[44px] px-4 py-2 rounded-md border border-border
                     text-sm font-medium text-text-body
                     hover:bg-surface-sunken disabled:opacity-50 disabled:cursor-not-allowed
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= t("identity_picker.actions.edit_crop") %>
      </button>
      <%= button_to t("identity_picker.actions.delete"), save_url,
            method: :delete,
            data: {
              identity_picker_target: "deleteButton",
              turbo_confirm: t("identity_picker.actions.delete_confirm")
            },
            disabled: !has_image,
            class: "flex-1 inline-flex items-center justify-center gap-2
                   min-h-[44px] px-4 py-2 rounded-md border border-danger-border
                   text-sm font-medium text-danger
                   hover:bg-danger-surface disabled:opacity-50 disabled:cursor-not-allowed
                   focus:outline-none focus:ring-2 focus:ring-interactive-focus" %>
    </div>

    <%# Contextual actions — initials source %>
    <div data-identity-picker-target="initialsActions"
         class="mt-4 space-y-3"
         <%= "hidden" unless current_source == "initials" %>>
      <label class="block text-sm font-medium text-text-body">
        <%= t("identity_picker.color_picker.label") %>
      </label>
      <input type="range" min="0" max="360"
             value="<%= hue %>"
             data-identity-picker-target="hueSlider"
             data-action="input->identity-picker#updateHue"
             aria-label="<%= t('identity_picker.color_picker.aria_label') %>"
             class="hue-slider w-full">
      <div data-identity-picker-target="huePreview"
           class="h-3 rounded-full"
           style="background-color: <%= display_color %>;"></div>
      <input type="hidden" name="<%= color_field %>"
             value="<%= display_color %>"
             data-identity-picker-target="colorField">
      <%= form_with url: save_url, method: :patch, class: "mt-2" do %>
        <input type="hidden" name="avatar_source" value="initials">
        <input type="hidden" name="<%= color_field %>"
               value="<%= display_color %>"
               data-identity-picker-target="colorField">
        <button type="submit"
                class="inline-flex items-center justify-center w-full
                       min-h-[44px] px-6 py-2.5 rounded-md
                       text-sm font-semibold text-white
                       bg-interactive hover:bg-interactive-hover
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus">
          <%= t("identity_picker.crop.save") %>
        </button>
      <% end %>
    </div>
  </div>

  <%# ═══ VIEW: CROP ═══ %>
  <div data-mode-switch-target="section" data-mode="crop" hidden>
    <% if has_image || original.attached? %>
      <% crop_image = original.attached? ? original : image %>
      <%= render "shared/image_crop",
            image: crop_image,
            aspect_ratio: aspect_ratio,
            shape: shape,
            save_url: save_url,
            cancel_url: "#",
            existing_crop: existing_crop,
            compact: true,
            title: title %>
    <% end %>
    <div class="flex gap-2 mt-3">
      <button type="button"
              data-action="click->mode-switch#switchTo"
              data-mode-switch-mode-param="upload"
              class="text-sm text-text-muted hover:text-interactive underline underline-offset-2
                     min-h-[44px] inline-flex items-center
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
        <%= t("identity_picker.crop.upload_instead") %>
      </button>
      <span class="flex-1"></span>
      <button type="button"
              data-action="click->mode-switch#switchTo"
              data-mode-switch-mode-param="main"
              class="text-sm text-text-muted hover:text-text-body
                     min-h-[44px] inline-flex items-center px-4
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
        <%= t("identity_picker.crop.cancel") %>
      </button>
      <button type="button"
              data-action="click->identity-picker#saveCrop"
              class="inline-flex items-center justify-center
                     min-h-[44px] px-8 py-2.5 rounded-md
                     text-sm font-semibold text-white
                     bg-interactive hover:bg-interactive-hover
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= t("identity_picker.crop.save") %>
      </button>
    </div>
  </div>

  <%# ═══ VIEW: UPLOAD ═══ %>
  <div data-mode-switch-target="section" data-mode="upload" hidden>
    <div data-controller="image-upload"
         data-image-upload-max-file-size-value="5"
         data-image-upload-accepted-types-value="image/png,image/jpeg,image/gif,image/webp"
         data-image-upload-auto-submit-value="true"
         data-error-invalid-type="<%= t('image_upload.errors.invalid_type') %>"
         data-error-file-too-large="<%= t('image_upload.errors.file_too_large', max_size: 5) %>"
         data-uploading-text="<%= t('image_upload.uploading') %>">

      <div data-image-upload-target="error"
           role="alert"
           class="p-3 rounded-md bg-danger-surface text-danger text-sm border border-danger-border mb-4"
           hidden>
      </div>

      <%= form_with url: save_url, method: :patch, multipart: true,
                    data: { image_upload_target: "form" },
                    class: "space-y-4" do |f| %>
        <input type="file"
               name="<%= image_attachment %>"
               accept="image/png,image/jpeg,image/gif,image/webp"
               class="sr-only"
               data-image-upload-target="fileInput"
               data-action="change->image-upload#handleFile">

        <div data-image-upload-target="uploadZone"
             data-action="click->image-upload#selectFile keydown.enter->image-upload#selectFile keydown.space->image-upload#selectFile dragover->image-upload#handleDragOver dragleave->image-upload#handleDragLeave drop->image-upload#handleDrop"
             class="flex flex-col items-center justify-center w-full py-12 px-4
                    border-2 border-dashed border-border-strong rounded-lg cursor-pointer
                    hover:border-interactive-focus hover:bg-surface-sunken/50
                    focus-within:ring-2 focus-within:ring-interactive-focus
                    transition-colors"
             role="button"
             tabindex="0"
             aria-label="<%= t('identity_picker.upload.drop_zone') %>">
          <svg class="w-10 h-10 text-text-muted mb-3" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
          </svg>
          <span class="text-sm font-medium text-text-body"><%= t("identity_picker.upload.drop_zone") %></span>
          <span class="text-xs text-text-muted mt-1">
            <%= t("identity_picker.upload.constraints", types: "PNG, JPEG, GIF, WEBP", max_size: 5) %>
          </span>
        </div>
      <% end %>

      <%# Back to main view %>
      <div class="text-center mt-2">
        <button type="button"
                data-action="click->mode-switch#switchTo"
                data-mode-switch-mode-param="main"
                class="text-sm text-text-muted hover:text-text-body
                       min-h-[44px] inline-flex items-center
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
          <%= t("identity_picker.crop.cancel") %>
        </button>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Create the color_to_hue helper**

Add to `app/helpers/avatar_helper.rb` (or a shared helper):

```ruby
def color_to_hue(hex_color)
  return 210 unless hex_color&.match?(/\A#[0-9a-fA-F]{6}\z/)

  r, g, b = hex_color[1..6].scan(/../).map { |c| c.to_i(16) / 255.0 }
  max = [r, g, b].max
  min = [r, g, b].min
  delta = max - min

  return 210 if delta < 0.001

  hue = if max == r
          60 * (((g - b) / delta) % 6)
        elsif max == g
          60 * (((b - r) / delta) + 2)
        else
          60 * (((r - g) / delta) + 4)
        end

  hue += 360 if hue < 0
  hue.round
end
```

- [ ] **Step 3: Commit**

```bash
mise exec -- git add app/views/shared/_identity_picker.html.erb app/views/shared/_identity_source_card.html.erb app/helpers/avatar_helper.rb
mise exec -- git commit -m "feat: create identity picker partial with three-view modal layout"
```

---

## Task 8: Update controllers for dual-attachment save

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Test: `spec/requests/account/avatars_spec.rb`

- [ ] **Step 1: Write failing spec for cropped blob upload**

Add to `spec/requests/account/avatars_spec.rb`:

```ruby
    describe "PATCH /account/avatar/save_crop with cropped blob" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        user.avatar_original.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "original.png", content_type: "image/png"
        )
      end

      it "saves cropped image as avatar and coordinates to original metadata" do
        cropped_file = fixture_file_upload("avatar.png", "image/png")
        patch save_crop_account_avatar_path, params: {
          cropped_image: cropped_file,
          crop: { x: 10, y: 20, w: 100, h: 100 }
        }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        metadata = user.avatar_original.blob.reload.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end
    end
```

- [ ] **Step 2: Run to verify it fails**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb -e "cropped blob" --format documentation
```

Expected: FAIL — controller doesn't handle `cropped_image` param.

- [ ] **Step 3: Update avatars controller save_crop**

Replace the `save_crop` method in `app/controllers/account/avatars_controller.rb`:

```ruby
    def save_crop
      unless Current.user.avatar.attached? || Current.user.avatar_original.attached?
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        return
      end

      # Client-side crop: receives a pre-cropped blob
      if params[:cropped_image].present?
        Current.user.avatar.attach(params[:cropped_image])
        Current.user.avatar_source = "upload"
        Current.user.save!

        # Save coordinates to original's metadata for re-crop
        if Current.user.avatar_original.attached?
          crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
          blob = Current.user.avatar_original.blob
          blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))
        end
      else
        # Legacy: server-side crop coordinates (standalone crop page)
        attachment = ActiveStorage::Attachment.find_by(
          record_type: "User", record_id: Current.user.id, name: "avatar"
        )
        return redirect_to(edit_account_profile_path, alert: t("image_crop.no_image")) unless attachment

        crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
        blob = ActiveStorage::Blob.find(attachment.blob_id)
        blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_account_profile_path, notice: t(".success") }
      end
    end
```

- [ ] **Step 4: Update the upload action for dual-attachment**

Replace the file upload section of the `update` method:

```ruby
      if file.present?
        # Store original
        Current.user.avatar_original.attach(file)
        # Also attach as avatar (will be replaced after crop)
        Current.user.avatar.attach(file)
        Current.user.avatar_source = "upload"

        if Current.user.save
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to crop_account_avatar_path }
          end
        else
          Current.user.avatar.purge
          Current.user.avatar_original.purge
          redirect_to edit_account_profile_path, alert: Current.user.errors.full_messages.to_sentence
        end
```

- [ ] **Step 5: Run specs**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb --format progress
```

Expected: all pass.

- [ ] **Step 6: Apply same pattern to brandings controller**

Update `save_crop` and `update` in `app/controllers/workspaces/brandings_controller.rb` with the same dual-attachment pattern (using `@workspace.logo` / `@workspace.logo_original`).

- [ ] **Step 7: Run all request specs**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format progress
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
mise exec -- git add app/controllers/account/avatars_controller.rb app/controllers/workspaces/brandings_controller.rb spec/requests/account/avatars_spec.rb
mise exec -- git commit -m "feat: dual-attachment save — cropped blob as display, original preserved with coordinates"
```

---

## Task 9: Wire identity picker to profile page

**Files:**
- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Replace the avatar modal content with identity picker**

Replace the modal section (the `render "shared/modal"` block and its contents) in the profile page with:

```erb
    <%# Modal with identity picker %>
    <%= render "shared/modal", title: t("account.avatars.edit.title"), size: :full do %>
      <%= render "shared/identity_picker",
            title: t("account.avatars.crop.title"),
            record: @user,
            image_attachment: :avatar,
            original_attachment: :avatar_original,
            save_url: account_avatar_path,
            sources: [:upload, :initials],
            current_source: @user.avatar_source,
            color_field: :primary_color,
            aspect_ratio: 1.0,
            shape: :circle,
            initials: @user.initials,
            current_color: @user.primary_color %>
    <% end %>
```

Remove ALL the existing modal content (the mode-switch sections with crop and upload). The identity picker partial handles all of that now.

- [ ] **Step 2: Also update the workspace branding page**

In `app/views/workspaces/brandings/edit.html.erb`, replace the existing upload modal render with:

```erb
    <%# Modal with identity picker %>
    <%= render "shared/modal", title: t("workspaces.brandings.edit.change_logo"), size: :full do %>
      <%= render "shared/identity_picker",
            title: t("workspaces.brandings.crop.title"),
            record: @workspace,
            image_attachment: :logo,
            original_attachment: :logo_original,
            save_url: workspace_branding_path(@workspace),
            sources: [:upload, :initials],
            current_source: @workspace.logo.attached? ? "upload" : "initials",
            color_field: :primary_color,
            aspect_ratio: 1.0,
            shape: :circle,
            initials: @workspace.initials,
            current_color: @workspace.primary_color %>
    <% end %>
```

- [ ] **Step 3: Run specs**

```bash
mise exec -- bundle exec rspec spec/system/avatar_spec.rb spec/system/image_crop_spec.rb --format progress
```

Some specs may need updating for the new markup. Fix as needed.

- [ ] **Step 4: Commit**

```bash
mise exec -- git add app/views/account/profiles/edit.html.erb app/views/workspaces/brandings/edit.html.erb
mise exec -- git commit -m "feat: wire identity picker to profile and workspace branding pages"
```

---

## Task 10: Create system specs for identity picker

**Files:**
- Create: `spec/system/identity_picker_spec.rb`

- [ ] **Step 1: Write the system specs**

Create `spec/system/identity_picker_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Identity picker", type: :system do
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

  describe "user avatar" do
    before { sign_in_via_form(user) }

    context "no avatar uploaded" do
      it "opens modal in upload mode" do
        visit edit_account_profile_path
        dismiss_banner
        click_button I18n.t("account.avatars.edit.change")
        expect(page).to have_css("dialog[open]")
        expect(page).to have_css("[data-image-upload-target='uploadZone']")
      end
    end

    context "avatar uploaded" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
      end

      it "opens modal in main mode with source cards" do
        visit edit_account_profile_path
        dismiss_banner
        click_button I18n.t("account.avatars.edit.change")
        expect(page).to have_css("dialog[open]")
        expect(page).to have_css("[data-controller~='identity-picker']")
        expect(page).to have_text(I18n.t("identity_picker.sources.upload"))
        expect(page).to have_text(I18n.t("identity_picker.sources.initials"))
      end

      it "shows action buttons for upload source" do
        visit edit_account_profile_path
        dismiss_banner
        click_button I18n.t("account.avatars.edit.change")
        expect(page).to have_button(I18n.t("identity_picker.actions.upload_new"))
        expect(page).to have_button(I18n.t("identity_picker.actions.edit_crop"))
        expect(page).to have_button(I18n.t("identity_picker.actions.delete"))
      end
    end
  end
end
```

- [ ] **Step 2: Run the specs**

```bash
mise exec -- bundle exec rspec spec/system/identity_picker_spec.rb --format documentation
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
mise exec -- git add spec/system/identity_picker_spec.rb
mise exec -- git commit -m "test: add identity picker system specs for avatar modal flows"
```

---

## Task 11: Run full test suite, fix breakage, update docs

**Files:** Various (fixups) + documentation

- [ ] **Step 1: Run full test suite**

```bash
mise exec -- bundle exec rspec --format progress
```

Fix any failures. Common issues:
- Old specs referencing removed markup
- Bullet eager loading on new attachments
- Locale key changes

- [ ] **Step 2: Run accessibility audit**

```bash
mise exec -- bundle exec rspec spec/system/identity_picker_spec.rb spec/system/image_crop_spec.rb -e "accessibility" --format documentation
```

- [ ] **Step 3: Update project session memory**

Update the session state memory file to reflect the new feature.

- [ ] **Step 4: Commit any remaining fixups**

```bash
mise exec -- git add -A
mise exec -- git commit -m "chore: fix test breakage and update documentation for identity picker"
```
