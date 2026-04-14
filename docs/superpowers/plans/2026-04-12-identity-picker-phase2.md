# Identity Picker Phase 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the identity picker modal — a shared hub/switcher for managing user avatars and workspace logos with Cropper.js v2 crop, OKLCH color picker, and dual attachment storage.

**Architecture:** Two-view modal (identity switcher hub + crop editor) driven by three Stimulus controllers (`identity_picker`, `image_cropper`, `modal_closer`). Client-side crop export via Cropper.js v2 `selection.$toCanvas()`. Dual Active Storage attachments (display + original). OKLCH hue slider for initials color. Shared partial parameterized for both User and Workspace. Single `update` controller action handles all flows via Turbo Stream responses.

**Tech Stack:** Rails 8.1, Cropper.js v2 (ESM), Stimulus, Turbo Streams, Active Storage, OKLCH color, RSpec TDD

**Spec:** `docs/superpowers/specs/2026-04-12-identity-picker-rebuild-design.md` (Phase 2)
**UX Brief:** `docs/superpowers/specs/identity-picker-ux-brief.md`

**Important:** All commands in worktree must use `mise exec --` prefix (e.g., `mise exec -- bundle exec rspec`).

---

## File Structure

### Files to Create

- `db/migrate/TIMESTAMP_add_primary_color_to_users.rb` — integer hue column for initials color
- `db/migrate/TIMESTAMP_add_avatar_original_to_users.rb` — add has_one_attached :avatar_original support (no migration needed for Active Storage, but model change required)
- `app/javascript/controllers/image_cropper_controller.js` — Cropper.js v2 wrapper
- `app/javascript/controllers/identity_picker_controller.js` — hub orchestration
- `app/javascript/controllers/modal_closer_controller.js` — auto-close dialog on connect (recreated with focus fix)
- `app/views/shared/_identity_picker.html.erb` — shared identity picker partial
- `app/views/account/avatars/update.turbo_stream.erb` — turbo stream response for avatar updates
- `app/assets/stylesheets/components/cropper.css` — Cropper.js v2 custom styling

### Files to Modify

- `app/models/user.rb` — add `has_one_attached :avatar_original`, `primary_color` validation, update `available_avatar_sources`
- `app/models/workspace.rb` — add `has_one_attached :logo_original`
- `app/helpers/avatar_helper.rb` — OKLCH color rendering in `render_initials_avatar`
- `app/helpers/workspace_helper.rb` — use workspace hex color consistently
- `app/controllers/account/avatars_controller.rb` — handle dual attachment, primary_color, crop coords, turbo stream
- `app/controllers/workspaces/brandings_controller.rb` — handle dual attachment, turbo stream
- `app/views/account/profiles/edit.html.erb` — replace placeholder with identity picker modal
- `app/views/workspaces/brandings/edit.html.erb` — add identity picker modal for logo
- `config/importmap.rb` — pin Cropper.js v2 ESM
- `config/locales/en/account.en.yml` — identity picker locale keys
- `config/locales/en/workspaces.en.yml` — workspace identity picker locale keys
- `spec/requests/account/avatars_spec.rb` — test new params and turbo stream
- `spec/helpers/avatar_helper_spec.rb` — test OKLCH color rendering
- `spec/requests/workspaces/brandings_spec.rb` — test dual attachment + turbo stream

---

### Task 1: Migration — Add primary_color to Users

**Files:**
- Create: `db/migrate/TIMESTAMP_add_primary_color_to_users.rb`
- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing model spec**

Add to `spec/models/user_spec.rb` (create if it doesn't exist):

```ruby
require "rails_helper"

RSpec.describe User, type: :model do
  describe "primary_color" do
    it "defaults to 210" do
      user = create(:user)
      expect(user.primary_color).to eq(210)
    end

    it "validates inclusion in 0..360" do
      user = build(:user, primary_color: 180)
      expect(user).to be_valid

      user.primary_color = -1
      expect(user).not_to be_valid

      user.primary_color = 361
      expect(user).not_to be_valid
    end

    it "allows nil" do
      user = build(:user, primary_color: nil)
      expect(user).to be_valid
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: FAIL — `primary_color` column doesn't exist.

- [ ] **Step 3: Create the migration**

```bash
mise exec -- bin/rails generate migration AddPrimaryColorToUsers primary_color:integer
```

Edit the generated migration:

```ruby
class AddPrimaryColorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :primary_color, :integer, default: 210
  end
end
```

Run:

```bash
mise exec -- bin/rails db:migrate
```

- [ ] **Step 4: Add validation to User model**

In `app/models/user.rb`, after the existing validations (around line 37), add:

```ruby
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
```

- [ ] **Step 5: Run test to verify it passes**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb app/models/user.rb spec/models/user_spec.rb
git commit -m "feat: add primary_color (OKLCH hue) to users

Integer column storing hue value 0-360 for initials circle color.
Default 210 (blue) matches the existing bg-interactive token."
```

---

### Task 2: Model — Dual Attachments and available_avatar_sources

**Files:**
- Modify: `app/models/user.rb`
- Modify: `app/models/workspace.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write failing specs**

Add to `spec/models/user_spec.rb`:

```ruby
  describe "avatar_original" do
    it "supports avatar_original attachment" do
      user = create(:user)
      user.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      expect(user.avatar_original).to be_attached
    end
  end

  describe "#available_avatar_sources" do
    it "always includes upload" do
      user = create(:user)
      expect(user.available_avatar_sources).to include("upload")
    end

    it "always includes initials" do
      user = create(:user)
      expect(user.available_avatar_sources).to include("initials")
    end

    it "includes gravatar when user has gravatar" do
      user = create(:user)
      user.update_columns(has_gravatar: true)
      expect(user.available_avatar_sources).to include("gravatar")
    end

    it "excludes gravatar when user has no gravatar" do
      user = create(:user)
      user.update_columns(has_gravatar: false)
      expect(user.available_avatar_sources).not_to include("gravatar")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: FAIL — `avatar_original` not defined, `available_avatar_sources` doesn't always include "upload".

- [ ] **Step 3: Add dual attachment to User**

In `app/models/user.rb`, after `has_one_attached :avatar` (line 8), add:

```ruby
  has_one_attached :avatar_original
```

- [ ] **Step 4: Update available_avatar_sources**

In `app/models/user.rb`, replace the `available_avatar_sources` method (lines 92-97):

```ruby
  def available_avatar_sources
    sources = %w[upload initials]
    sources << "gravatar" if has_gravatar?
    sources
  end
```

This always includes "upload" — selecting it with no image triggers the file picker.

- [ ] **Step 5: Add dual attachment to Workspace**

In `app/models/workspace.rb`, after `has_one_attached :logo` (line 5), add:

```ruby
  has_one_attached :logo_original
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/models/user.rb app/models/workspace.rb spec/models/user_spec.rb
git commit -m "feat: dual attachments and always-available upload source

Add avatar_original/logo_original for preserving originals during
re-crop. Update available_avatar_sources to always include upload
so the identity picker file picker is always accessible."
```

---

### Task 3: Helper — OKLCH Color for Initials

**Files:**
- Modify: `app/helpers/avatar_helper.rb`
- Test: `spec/helpers/avatar_helper_spec.rb`

- [x] **Step 1: Write failing specs**

Add to `spec/helpers/avatar_helper_spec.rb`, inside the `"with initials source"` context:

```ruby
      context "with custom primary_color" do
        before do
          user.update_columns(avatar_source: "initials", primary_color: 270)
        end

        it "renders inline OKLCH background style" do
          result = helper.avatar_for(user, size: :md)
          expect(result).to have_css("span[style*='oklch(0.45 0.2 270)']")
        end

        it "does not include bg-interactive class" do
          result = helper.avatar_for(user, size: :md)
          expect(result).not_to have_css("span.bg-interactive")
        end
      end

      context "with default primary_color (210)" do
        before do
          user.update_columns(avatar_source: "initials", primary_color: 210)
        end

        it "uses bg-interactive class" do
          result = helper.avatar_for(user, size: :md)
          expect(result).to have_css("span.bg-interactive")
        end

        it "does not include inline style" do
          result = helper.avatar_for(user, size: :md)
          expect(result).not_to have_css("span[style]")
        end
      end
```

- [x] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/helpers/avatar_helper_spec.rb --format documentation
```

Expected: FAIL — `primary_color` not used in rendering yet.

- [x] **Step 3: Update render_initials_avatar**

In `app/helpers/avatar_helper.rb`, replace the `render_initials_avatar` method (lines 47-52):

```ruby
  def render_initials_avatar(user, config, aria_label)
    custom_color = user.respond_to?(:primary_color) && user.primary_color.present? && user.primary_color != 210

    classes = "#{config[:css]} #{config[:text]} rounded-full flex items-center justify-center font-semibold"
    if custom_color
      classes += " text-white"
      style = "background-color: oklch(0.45 0.2 #{user.primary_color})"
    else
      classes += " bg-interactive text-text-on-interactive"
      style = nil
    end

    attrs = avatar_aria_attrs(aria_label)
    attrs[:style] = style if style

    content_tag :span, user.initials, class: classes, **attrs
  end
```

- [x] **Step 4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/helpers/avatar_helper_spec.rb --format documentation
```

Expected: PASS

- [x] **Step 5: Run full helper specs to check for regressions**

```bash
mise exec -- bundle exec rspec spec/helpers/ --format documentation
```

Expected: all pass

- [x] **Step 6: Commit**

```bash
git add app/helpers/avatar_helper.rb spec/helpers/avatar_helper_spec.rb
git commit -m "feat: render initials with OKLCH color from primary_color

Custom primary_color renders inline oklch() style. Default (210)
uses bg-interactive design token. Ensures AAA contrast with white
text across all hues via fixed lightness 0.45."
```

---

### Task 4: Cropper.js v2 Setup + CSS

**Files:**
- Modify: `config/importmap.rb`
- Create: `app/assets/stylesheets/components/cropper.css`

- [ ] **Step 1: Pin Cropper.js v2 in importmap**

In `config/importmap.rb`, add after the last pin:

```ruby
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@2/dist/cropper.esm.js"
```

Note: This is the ESM build (`.esm.js`), NOT the UMD build. The v2 ESM module registers Web Components (`cropper-canvas`, `cropper-image`, `cropper-selection`, etc.) on import.

- [ ] **Step 2: Create custom Cropper.js CSS**

Create `app/assets/stylesheets/components/cropper.css`:

```css
/* Cropper.js v2 — container and selection styling */

.cropper-container {
  height: 50vh;
  width: 100%;
  position: relative;
  overflow: hidden;
  background: var(--color-surface-sunken, #f1f5f9);
}

/* Selection handles use design tokens */
cropper-selection [action="resize"] {
  width: 12px;
  height: 12px;
  background: var(--color-interactive, #0284c7);
  border: 2px solid white;
  border-radius: 50%;
}

/* Dimmed overlay outside selection */
cropper-shade {
  display: block !important;
  background: rgba(0, 0, 0, 0.5);
}

/* Selection outline */
cropper-selection[outlined] {
  outline: 2px solid white;
  outline-offset: -1px;
}
```

- [ ] **Step 3: Verify importmap resolves**

```bash
mise exec -- bin/rails runner "puts Rails.application.importmap.to_json" | grep cropperjs
```

Expected: output includes the cropperjs CDN URL.

- [ ] **Step 4: Commit**

```bash
git add config/importmap.rb app/assets/stylesheets/components/cropper.css
git commit -m "feat: pin Cropper.js v2 ESM and add custom crop styles

Pin cropperjs@2 ESM build for importmaps. Add container sizing
(50vh explicit height) and design token integration for selection
handles and overlay."
```

---

### Task 5: image_cropper_controller.js

**Files:**
- Create: `app/javascript/controllers/image_cropper_controller.js`

This is the Cropper.js v2 wrapper. Pure crop concern — knows nothing about identity picker, sources, or forms.

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/image_cropper_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "slider", "liveRegion"]
  static values = { aspectRatio: { type: Number, default: 1 } }

  connect() {
    this._initialized = false
    this._baseTransform = null

    // Defer initialization if element is hidden (v2 produces 0x0 selection on hidden elements)
    if (this.element.closest("[hidden]")) {
      this._observeVisibility()
    } else {
      this._deferredInit()
    }
  }

  disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
    if (this._cropper) {
      this._cropper.getCropperCanvas()?.remove()
      this._cropper = null
    }
    this._initialized = false
  }

  // Public: load a new image (called by identity_picker_controller)
  loadImage(src) {
    if (this._cropper) {
      this._cropper.getCropperCanvas()?.remove()
      this._cropper = null
      this._initialized = false
    }

    const img = this.containerTarget.querySelector("img")
    if (img) {
      img.src = src
      this._deferredInit()
    }
  }

  // Public: export cropped region as blob
  async exportCrop() {
    if (!this._cropper) return null

    const selection = this._cropper.getCropperSelection()
    if (!selection) return null

    const canvas = await selection.$toCanvas({
      beforeDraw(context) {
        context.fillStyle = "#ffffff"
        context.fillRect(0, 0, context.canvas.width, context.canvas.height)
      }
    })

    return new Promise((resolve) => {
      canvas.toBlob((blob) => {
        const coords = this._getCropCoordinates()
        resolve({ blob, coordinates: coords })
      }, "image/png")
    })
  }

  // Zoom slider handler
  handleSlider() {
    if (!this._cropper || !this._baseTransform) return

    const value = parseInt(this.sliderTarget.value, 10)
    const image = this._cropper.getCropperImage()
    const baseScale = this._baseTransform[0]
    const targetScale = baseScale * Math.pow(3, value / 100)

    const newTransform = [...this._baseTransform]
    newTransform[0] = targetScale
    newTransform[3] = targetScale
    image.$setTransform(newTransform)

    // $setTransform doesn't fire actionend — dispatch manually for live preview
    const canvas = this._cropper.getCropperCanvas()
    canvas.dispatchEvent(new CustomEvent("actionend", { bubbles: true }))

    this._announceZoom(value)
  }

  // Keyboard shortcuts
  handleKeydown(event) {
    if (!this._cropper) return

    const selection = this._cropper.getCropperSelection()
    const image = this._cropper.getCropperImage()
    if (!selection || !image) return

    const step = event.shiftKey ? 10 : 1

    switch (event.key) {
      case "ArrowUp":
        event.preventDefault()
        selection.$move(0, -step)
        break
      case "ArrowDown":
        event.preventDefault()
        selection.$move(0, step)
        break
      case "ArrowLeft":
        event.preventDefault()
        selection.$move(-step, 0)
        break
      case "ArrowRight":
        event.preventDefault()
        selection.$move(step, 0)
        break
      case "+":
      case "=":
        event.preventDefault()
        this._adjustZoom(5)
        break
      case "-":
        event.preventDefault()
        this._adjustZoom(-5)
        break
    }
  }

  // Private

  _observeVisibility() {
    const hiddenParent = this.element.closest("[hidden]")
    if (!hiddenParent) return

    this._observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "attributes" && mutation.attributeName === "hidden") {
          if (!hiddenParent.hidden) {
            this._observer.disconnect()
            this._observer = null
            this._deferredInit()
            break
          }
        }
      }
    })

    this._observer.observe(hiddenParent, { attributes: true, attributeFilter: ["hidden"] })
  }

  _deferredInit() {
    // Double rAF ensures browser has reflowed after visibility change
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this._initCropper()
      })
    })
  }

  async _initCropper() {
    if (this._initialized) return

    const { default: Cropper } = await import("cropperjs")

    const img = this.containerTarget.querySelector("img")
    if (!img) return

    this._cropper = new Cropper(img, {
      template: this._cropperTemplate()
    })

    // Wait for image to be ready, then capture baseline transform
    const canvas = this._cropper.getCropperCanvas()
    if (canvas) {
      canvas.addEventListener("actionend", () => {
        this.dispatch("cropChanged")
      })
    }

    // Capture base transform after image loads
    const image = this._cropper.getCropperImage()
    if (image) {
      image.addEventListener("transform", () => {
        if (!this._baseTransform) {
          this._baseTransform = image.$getTransform()
        }
      }, { once: true })
    }

    // Enforce selection bounds
    const selection = this._cropper.getCropperSelection()
    if (selection) {
      selection.addEventListener("change", (event) => {
        this._enforceBounds(event, selection)
      })
    }

    this._initialized = true
    this._announceReady()
  }

  _cropperTemplate() {
    return `
      <cropper-canvas background>
        <cropper-image
          initial-center-size="contain"
          rotatable scalable skewable translatable
        ></cropper-image>
        <cropper-shade hidden></cropper-shade>
        <cropper-handle action="move" plain></cropper-handle>
        <cropper-selection movable resizable outlined
          aspect-ratio="${this.aspectRatioValue}"
          initial-coverage="0.8">
          <cropper-handle action="move"
            style="width:100%;height:100%;background:transparent">
          </cropper-handle>
          <cropper-handle action="resize-top-left"></cropper-handle>
          <cropper-handle action="resize-top-right"></cropper-handle>
          <cropper-handle action="resize-bottom-left"></cropper-handle>
          <cropper-handle action="resize-bottom-right"></cropper-handle>
        </cropper-selection>
      </cropper-canvas>
    `
  }

  _enforceBounds(event, selection) {
    const canvas = this._cropper?.getCropperCanvas()
    if (!canvas) return

    const canvasRect = canvas.getBoundingClientRect()
    const { x, y, width, height } = event.detail

    if (x < 0 || y < 0 ||
        x + width > canvasRect.width ||
        y + height > canvasRect.height) {
      event.preventDefault()
    }
  }

  _getCropCoordinates() {
    const selection = this._cropper?.getCropperSelection()
    if (!selection) return null

    const { x, y, width, height } = selection
    return {
      x: Math.round(x),
      y: Math.round(y),
      w: Math.round(width),
      h: Math.round(height)
    }
  }

  _adjustZoom(delta) {
    if (!this.hasSliderTarget) return
    const current = parseInt(this.sliderTarget.value, 10)
    this.sliderTarget.value = Math.max(0, Math.min(100, current + delta))
    this.handleSlider()
  }

  _announceZoom(value) {
    if (!this.hasLiveRegionTarget) return
    const percent = Math.round(100 + value * 2)
    this.liveRegionTarget.textContent = `Zoom ${percent}%`
  }

  _announceReady() {
    if (!this.hasLiveRegionTarget) return
    this.liveRegionTarget.textContent = "Image loaded. Use arrow keys to move selection, plus and minus to zoom."
  }
}
```

- [ ] **Step 2: Verify controller loads**

```bash
mise exec -- bin/rails runner "puts 'importmap OK'"
```

Then check no syntax errors by examining the stimulus manifest:

```bash
ls app/javascript/controllers/image_cropper_controller.js
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/image_cropper_controller.js
git commit -m "feat: add image_cropper_controller for Cropper.js v2

Pure crop concern: init with custom template, deferred init for
hidden elements via MutationObserver + double rAF, exponential
zoom slider, selection bounds enforcement, keyboard shortcuts,
async blob export via selection.\$toCanvas(). Dispatches
crop:changed custom event for live preview updates."
```

---

### Task 6: modal_closer_controller.js

**Files:**
- Create: `app/javascript/controllers/modal_closer_controller.js`

Recreated from Phase 1 deletion, now dispatches through modal controller's close method to fix focus restoration.

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/modal_closer_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Find the nearest open dialog and close it through the modal controller
    // to ensure proper focus restoration
    const dialog = this.element.closest("dialog")
    if (dialog?.open) {
      const modalController = this.application.getControllerForElementAndIdentifier(
        dialog.closest("[data-controller~='modal']"),
        "modal"
      )

      if (modalController) {
        modalController.close()
      } else {
        dialog.close()
      }
    }

    // Remove self after closing
    this.element.remove()
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/modal_closer_controller.js
git commit -m "feat: recreate modal_closer_controller with focus fix

Dispatches close through modal controller instead of calling
dialog.close() directly. This ensures focus is restored to the
trigger element that opened the modal."
```

---

### Task 7: identity_picker_controller.js

**Files:**
- Create: `app/javascript/controllers/identity_picker_controller.js`

Hub orchestration — manages source selection, color picker, file picker, crop flow.

- [x] **Step 1: Create the controller**

Create `app/javascript/controllers/identity_picker_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",          // large preview circle
    "sourceField",      // hidden input for avatar_source
    "colorField",       // hidden input for primary_color
    "colorSlider",      // range input for hue
    "colorPanel",       // color picker panel (shown/hidden)
    "colorHex",         // hex display span
    "fileInput",        // hidden file input
    "initialsPreview",  // initials circle in preview
    "photoPreview",     // photo img in preview
    "gravPreview",      // gravatar img in preview
    "cropPreview",      // small circular preview in crop view
    "form"              // the hub form
  ]

  static values = {
    formUrl: String,
    currentSource: String,
    hasImage: Boolean
  }

  connect() {
    this._pendingFile = null
  }

  // Source card selection
  selectSource(event) {
    const source = event.currentTarget.querySelector("input[type='radio']")?.value
      || event.params.source
    if (!source) return

    this.currentSourceValue = source
    this.sourceFieldTarget.value = source
    this._updatePreview()
    this._updateContextualControls()

    // Photo + no image → open file picker immediately
    if (source === "upload" && !this.hasImageValue) {
      this.openFilePicker()
    }
  }

  // Click on photo preview → open crop view
  openCrop() {
    if (this.currentSourceValue !== "upload" || !this.hasImageValue) return
    this._switchMode("crop")
  }

  // Open native file picker
  openFilePicker() {
    this.fileInputTarget.click()
  }

  // File selected from native picker
  handleFileSelected(event) {
    const file = event.target.files[0]
    if (!file) return

    // Client-side validation
    const validTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
    if (!validTypes.includes(file.type)) {
      this._announce("Invalid file type. Please select a PNG, JPEG, GIF, or WebP image.")
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      this._announce("File is too large. Maximum size is 5 MB.")
      return
    }

    this._pendingFile = file
    const objectUrl = URL.createObjectURL(file)

    // Load the image into the cropper
    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (cropperEl) {
      const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      if (cropper) {
        cropper.loadImage(objectUrl)
      }
    }

    this._switchMode("crop")

    // Reset file input so same file can be re-selected
    event.target.value = ""
  }

  // "Save crop" button clicked
  async saveCrop() {
    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (!cropperEl) return

    const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
    if (!cropper) return

    const result = await cropper.exportCrop()
    if (!result) return

    const { blob, coordinates } = result

    const formData = new FormData()
    formData.append("avatar", blob, "cropped-avatar.png")

    if (this._pendingFile) {
      formData.append("avatar_original", this._pendingFile)
      this._pendingFile = null
    }

    formData.append("avatar_source", "upload")
    formData.append("crop_coordinates", JSON.stringify(coordinates))

    // Add CSRF token
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    }

    const response = await fetch(this.formUrlValue, {
      method: "PATCH",
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      body: formData
    })

    if (response.ok) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
      this.hasImageValue = true
    }

    this._switchMode("hub")
    this._updatePreview()
  }

  // "Remove photo" from crop view
  removePhoto() {
    this.hasImageValue = false
    this.currentSourceValue = "initials"
    this.sourceFieldTarget.value = "initials"
    this._switchMode("hub")
    this._updatePreview()
    this._updateContextualControls()
  }

  // "Back to hub" from crop view
  backToHub() {
    this._pendingFile = null
    this._switchMode("hub")
  }

  // Color slider changed
  handleColorChange() {
    const hue = parseInt(this.colorSliderTarget.value, 10)
    this.colorFieldTarget.value = hue

    // Update preview
    if (this.hasInitialsPreviewTarget) {
      this.initialsPreviewTarget.style.backgroundColor = `oklch(0.45 0.2 ${hue})`
    }

    // Update hex display
    if (this.hasColorHexTarget) {
      this.colorHexTarget.textContent = this._hueToColorName(hue)
    }

    this._announceColor(hue)
  }

  // Crop view dispatches this when crop changes (for live preview)
  updateCropPreview(event) {
    if (!this.hasCropPreviewTarget) return

    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (!cropperEl) return

    const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
    if (!cropper?._cropper) return

    const selection = cropper._cropper.getCropperSelection()
    if (!selection) return

    selection.$toCanvas({ width: 48, height: 48 }).then((canvas) => {
      this.cropPreviewTarget.src = canvas.toDataURL()
    }).catch(() => {})
  }

  // Private

  _switchMode(mode) {
    const modeSwitch = this.element.querySelector("[data-controller~='mode-switch']")
    if (modeSwitch) {
      const ctrl = this.application.getControllerForElementAndIdentifier(modeSwitch, "mode-switch")
      if (ctrl) ctrl.modeValue = mode
    }
  }

  _updatePreview() {
    // Show/hide the correct preview element based on source
    if (this.hasInitialsPreviewTarget) {
      this.initialsPreviewTarget.hidden = this.currentSourceValue !== "initials"
    }
    if (this.hasPhotoPreviewTarget) {
      this.photoPreviewTarget.hidden = this.currentSourceValue !== "upload"
    }
    if (this.hasGravPreviewTarget) {
      this.gravPreviewTarget.hidden = this.currentSourceValue !== "gravatar"
    }
  }

  _updateContextualControls() {
    if (this.hasColorPanelTarget) {
      this.colorPanelTarget.hidden = this.currentSourceValue !== "initials"
    }
  }

  _hueToColorName(hue) {
    if (hue < 30) return "Red"
    if (hue < 60) return "Orange"
    if (hue < 90) return "Yellow"
    if (hue < 150) return "Green"
    if (hue < 210) return "Cyan"
    if (hue < 270) return "Blue"
    if (hue < 330) return "Purple"
    return "Pink"
  }

  _announceColor(hue) {
    const liveRegion = this.element.querySelector("[aria-live='polite']")
    if (liveRegion) {
      liveRegion.textContent = `Color: ${this._hueToColorName(hue)}`
    }
  }

  _announce(message) {
    const liveRegion = this.element.querySelector("[aria-live='polite']")
    if (liveRegion) {
      liveRegion.textContent = message
    }
  }
}
```

- [x] **Step 2: Commit**

```bash
git add app/javascript/controllers/identity_picker_controller.js
git commit -m "feat: add identity_picker_controller for hub orchestration

Manages source card selection, OKLCH color slider, native file
picker trigger, crop save via fetch + FormData, live preview
updates, and hub/crop view transitions via mode_switch."
```

---

### Task 8: Identity Picker Partial + I18n

**Files:**
- Create: `app/views/shared/_identity_picker.html.erb`
- Modify: `config/locales/en/account.en.yml`

This is the shared partial rendered inside a modal, parameterized for both users and workspaces.

- [ ] **Step 1: Create the identity picker partial**

Create `app/views/shared/_identity_picker.html.erb`:

```erb
<%# locals: (model:, form_url:, available_sources:, has_color_picker: false, title:) -%>
<%
  is_user = model.is_a?(User)
  current_source = is_user ? model.avatar_source : (model.logo.attached? ? "upload" : "initials")
  has_image = is_user ? model.avatar.attached? : model.logo.attached?
  current_hue = is_user ? (model.primary_color || 210) : 210
  image_url = if is_user && model.avatar.attached?
               url_for(model.avatar)
             elsif !is_user && model.logo.attached?
               url_for(model.logo)
             end
  gravatar_url = is_user ? model.gravatar_url(size: 256) : nil
  initials = model.initials
%>

<div data-controller="identity-picker mode-switch"
     data-identity-picker-form-url-value="<%= form_url %>"
     data-identity-picker-current-source-value="<%= current_source %>"
     data-identity-picker-has-image-value="<%= has_image %>"
     data-mode-switch-mode-value="hub">

  <%# Hidden file input — triggered programmatically %>
  <input type="file"
         accept="image/png,image/jpeg,image/gif,image/webp"
         class="sr-only"
         data-identity-picker-target="fileInput"
         data-action="change->identity-picker#handleFileSelected"
         aria-label="<%= t('identity_picker.select_file') %>">

  <%# ARIA live region for announcements %>
  <div aria-live="polite" class="sr-only"></div>

  <%# ═══════ HUB VIEW ═══════ %>
  <div data-mode-switch-target="section" data-mode="hub">

    <%# Large preview %>
    <div class="flex flex-col items-center py-6">
      <% if has_image && current_source == "upload" %>
        <button type="button"
                data-action="click->identity-picker#openCrop"
                class="relative w-32 h-32 rounded-full overflow-hidden
                       group cursor-pointer
                       focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus">
          <%= image_tag image_url,
                class: "w-full h-full object-cover",
                alt: "",
                data: { identity_picker_target: "photoPreview" } %>
          <span class="absolute inset-0 bg-black/0 group-hover:bg-black/30
                       flex items-center justify-center transition-colors">
            <%= icon(:pencil, size: :md,
                  class: "text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md") %>
          </span>
        </button>
      <% else %>
        <div class="w-32 h-32 rounded-full flex items-center justify-center text-3xl font-semibold text-white"
             data-identity-picker-target="initialsPreview"
             style="background-color: oklch(0.45 0.2 <%= current_hue %>)"
             <% if current_source == "gravatar" %>hidden<% end %>>
          <%= initials %>
        </div>
        <% if gravatar_url && current_source == "gravatar" %>
          <%= image_tag gravatar_url,
                class: "w-32 h-32 rounded-full object-cover",
                alt: "",
                loading: "lazy",
                data: { identity_picker_target: "gravPreview" } %>
        <% end %>
      <% end %>
      <span class="text-xs text-text-muted mt-2 uppercase tracking-wider">
        <%= t("identity_picker.preview") %>
      </span>
    </div>

    <%# Source selection %>
    <p class="text-sm text-text-muted mb-3"><%= t("identity_picker.choose_source") %></p>

    <%= form_with url: form_url, method: :patch,
          data: { identity_picker_target: "form" },
          class: "space-y-4" do |f| %>

      <input type="hidden" name="avatar_source" value="<%= current_source %>"
             data-identity-picker-target="sourceField">
      <input type="hidden" name="primary_color" value="<%= current_hue %>"
             data-identity-picker-target="colorField">

      <%# Source cards %>
      <div role="radiogroup" aria-label="<%= t('identity_picker.source_label') %>"
           class="space-y-2">

        <%# Photo card %>
        <% if available_sources.include?("upload") %>
          <label data-action="click->identity-picker#selectSource"
                 data-identity-picker-source-param="upload"
                 class="flex items-center gap-4 p-4 rounded-lg border cursor-pointer
                        hover:bg-surface-sunken/50 transition-colors
                        <%= current_source == 'upload' ? 'border-interactive ring-1 ring-interactive' : 'border-border' %>">
            <%= icon(:camera, size: :lg, class: "text-text-muted shrink-0") %>
            <div class="flex-1">
              <span class="block text-sm font-medium text-text-heading">
                <%= t("identity_picker.sources.upload.title") %>
              </span>
              <span class="block text-xs text-text-muted">
                <%= t("identity_picker.sources.upload.description") %>
              </span>
            </div>
            <input type="radio" name="avatar_source_radio"
                   value="upload"
                   <%= "checked" if current_source == "upload" %>
                   class="size-4 text-interactive focus:ring-interactive-focus">
          </label>
        <% end %>

        <%# Gravatar card %>
        <% if available_sources.include?("gravatar") %>
          <label data-action="click->identity-picker#selectSource"
                 data-identity-picker-source-param="gravatar"
                 class="flex items-center gap-4 p-4 rounded-lg border cursor-pointer
                        hover:bg-surface-sunken/50 transition-colors
                        <%= current_source == 'gravatar' ? 'border-interactive ring-1 ring-interactive' : 'border-border' %>">
            <%= icon(:globe_alt, size: :lg, class: "text-text-muted shrink-0") %>
            <div class="flex-1">
              <span class="block text-sm font-medium text-text-heading">
                <%= t("identity_picker.sources.gravatar.title") %>
              </span>
              <span class="block text-xs text-text-muted">
                <%= t("identity_picker.sources.gravatar.description") %>
              </span>
            </div>
            <input type="radio" name="avatar_source_radio"
                   value="gravatar"
                   <%= "checked" if current_source == "gravatar" %>
                   class="size-4 text-interactive focus:ring-interactive-focus">
          </label>
        <% end %>

        <%# Initials card %>
        <% if available_sources.include?("initials") %>
          <label data-action="click->identity-picker#selectSource"
                 data-identity-picker-source-param="initials"
                 class="flex items-center gap-4 p-4 rounded-lg border cursor-pointer
                        hover:bg-surface-sunken/50 transition-colors
                        <%= current_source == 'initials' ? 'border-interactive ring-1 ring-interactive' : 'border-border' %>">
            <span class="w-10 h-10 rounded-full flex items-center justify-center text-xs font-semibold text-white shrink-0"
                  style="background-color: oklch(0.45 0.2 <%= current_hue %>)">
              <%= initials %>
            </span>
            <div class="flex-1">
              <span class="block text-sm font-medium text-text-heading">
                <%= t("identity_picker.sources.initials.title") %>
              </span>
              <span class="block text-xs text-text-muted">
                <%= t("identity_picker.sources.initials.description") %>
              </span>
            </div>
            <input type="radio" name="avatar_source_radio"
                   value="initials"
                   <%= "checked" if current_source == "initials" %>
                   class="size-4 text-interactive focus:ring-interactive-focus">
          </label>
        <% end %>
      </div>

      <%# Color picker panel (shown when Initials selected) %>
      <% if has_color_picker %>
        <div data-identity-picker-target="colorPanel"
             class="p-4 rounded-lg border border-border space-y-3"
             <%= "hidden" unless current_source == "initials" %>>
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-text-heading">
              <%= t("identity_picker.color_label") %>
            </span>
            <span class="text-xs font-mono text-text-muted"
                  data-identity-picker-target="colorHex">
              Blue
            </span>
          </div>
          <input type="range" min="0" max="360" step="1"
                 value="<%= current_hue %>"
                 data-identity-picker-target="colorSlider"
                 data-action="input->identity-picker#handleColorChange"
                 aria-label="<%= t('identity_picker.color_aria_label') %>"
                 aria-valuemin="0" aria-valuemax="360"
                 aria-valuenow="<%= current_hue %>"
                 class="w-full h-3 rounded-full appearance-none cursor-pointer
                        [&::-webkit-slider-thumb]:appearance-none
                        [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:h-5
                        [&::-webkit-slider-thumb]:rounded-full
                        [&::-webkit-slider-thumb]:bg-white
                        [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-border-strong
                        [&::-webkit-slider-thumb]:shadow-md
                        [&::-webkit-slider-thumb]:cursor-pointer"
                 style="background: linear-gradient(to right,
                   oklch(0.45 0.2 0),
                   oklch(0.45 0.2 60),
                   oklch(0.45 0.2 120),
                   oklch(0.45 0.2 180),
                   oklch(0.45 0.2 240),
                   oklch(0.45 0.2 300),
                   oklch(0.45 0.2 360));">
        </div>
      <% end %>

      <%# Save button %>
      <div class="pt-4">
        <%= f.submit t("identity_picker.save"),
              class: "w-full flex items-center justify-center gap-2" %>
      </div>
    <% end %>
  </div>

  <%# ═══════ CROP VIEW ═══════ %>
  <div data-mode-switch-target="section" data-mode="crop" hidden>
    <%# Header with back arrow %>
    <div class="flex items-center gap-3 mb-4">
      <button type="button"
              data-action="click->identity-picker#backToHub"
              class="min-h-[44px] min-w-[44px] inline-flex items-center justify-center
                     rounded-md hover:bg-surface-sunken
                     text-text-muted hover:text-text-body
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus"
              aria-label="<%= t('identity_picker.back') %>">
        <%= icon(:arrow_left, size: :md) %>
      </button>
      <h3 class="text-lg font-semibold text-text-heading">
        <%= t("identity_picker.crop_title") %>
      </h3>
    </div>

    <%# Crop area %>
    <div data-controller="image-cropper"
         data-image-cropper-aspect-ratio-value="1"
         data-action="keydown->image-cropper#handleKeydown image-cropper:cropChanged->identity-picker#updateCropPreview"
         tabindex="0"
         aria-label="<%= t('identity_picker.crop_area_label') %>">
      <div class="cropper-container rounded-lg"
           data-image-cropper-target="container">
        <% if has_image %>
          <%= image_tag image_url, class: "max-w-full", alt: "" %>
        <% else %>
          <img src="" class="max-w-full" alt="">
        <% end %>
      </div>

      <%# Zoom slider %>
      <div class="mt-3 px-2">
        <input type="range" min="0" max="100" value="0"
               data-image-cropper-target="slider"
               data-action="input->image-cropper#handleSlider"
               aria-label="<%= t('identity_picker.zoom_label') %>"
               class="w-full h-2 rounded-full appearance-none cursor-pointer
                      bg-border
                      [&::-webkit-slider-thumb]:appearance-none
                      [&::-webkit-slider-thumb]:w-4 [&::-webkit-slider-thumb]:h-4
                      [&::-webkit-slider-thumb]:rounded-full
                      [&::-webkit-slider-thumb]:bg-white
                      [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-border-strong
                      [&::-webkit-slider-thumb]:shadow">
      </div>

      <%# ARIA live region %>
      <div data-image-cropper-target="liveRegion"
           aria-live="polite" class="sr-only"></div>
    </div>

    <%# Result row %>
    <div class="flex items-center justify-between mt-4">
      <div class="flex items-center gap-3">
        <img src="" alt=""
             class="w-12 h-12 rounded-full object-cover"
             data-identity-picker-target="cropPreview"
             aria-hidden="true">
        <div>
          <span class="block text-sm font-medium text-text-heading">
            <%= t("identity_picker.result_label") %>
          </span>
          <span class="block text-xs text-text-muted">
            <%= t("identity_picker.result_description") %>
          </span>
        </div>
      </div>
      <button type="button"
              data-action="click->identity-picker#saveCrop"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-md
                     bg-interactive text-text-on-interactive font-medium
                     hover:bg-interactive-hover
                     focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
                     min-h-[44px]">
        <%= t("identity_picker.save_crop") %>
      </button>
    </div>

    <%# Secondary actions %>
    <div class="flex flex-col items-center gap-2 mt-4 pt-4 border-t border-border">
      <button type="button"
              data-action="click->identity-picker#openFilePicker"
              class="inline-flex items-center gap-2 text-sm text-interactive
                     hover:text-interactive-hover
                     min-h-[44px] px-2 rounded
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= icon(:arrow_up_tray, size: :sm) %>
        <%= t("identity_picker.upload_new") %>
      </button>
      <button type="button"
              data-action="click->identity-picker#removePhoto"
              class="inline-flex items-center gap-2 text-sm text-danger
                     hover:text-danger/80
                     min-h-[44px] px-2 rounded
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= icon(:trash, size: :sm) %>
        <%= t("identity_picker.remove_photo") %>
      </button>
      <button type="button"
              data-action="click->identity-picker#backToHub"
              class="text-sm text-text-muted hover:text-text-body
                     min-h-[44px] px-2 rounded
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= t("identity_picker.back_to_hub") %>
      </button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Add I18n locale keys**

In `config/locales/en/account.en.yml`, add at the top level (same level as `account:`):

```yaml
  identity_picker:
    preview: "Preview"
    choose_source: "Choose how you're represented"
    source_label: "Identity source"
    select_file: "Select image file"
    save: "Save & apply"
    save_crop: "Save crop"
    crop_title: "Crop your photo"
    crop_area_label: "Crop area — use arrow keys to move selection, plus and minus to zoom"
    zoom_label: "Zoom level"
    color_label: "Circle color"
    color_aria_label: "Circle color hue"
    result_label: "Result"
    result_description: "Circular preview"
    upload_new: "Upload new"
    remove_photo: "Remove photo"
    back: "Back"
    back_to_hub: "Back to identity switcher"
    sources:
      upload:
        title: "Photo"
        description: "Upload or take a custom picture"
      gravatar:
        title: "Gravatar"
        description: "Sync with your gravatar.com profile"
      initials:
        title: "Initials"
        description: "A simple, colored circle with your initials"
```

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_identity_picker.html.erb config/locales/en/account.en.yml
git commit -m "feat: add identity picker partial and locale keys

Shared partial for both user avatars and workspace logos. Two-view
hub/switcher with source cards, OKLCH color picker, crop editor
with zoom slider and live preview. All text externalized to I18n."
```

---

### Task 9: Avatars Controller + Turbo Stream

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`
- Create: `app/views/account/avatars/update.turbo_stream.erb`
- Test: `spec/requests/account/avatars_spec.rb`

- [ ] **Step 1: Write failing specs for the new controller behavior**

Add to `spec/requests/account/avatars_spec.rb`, inside the `"authenticated"` context:

```ruby
    describe "PATCH /account/avatar with primary_color" do
      it "updates primary_color when switching to initials" do
        patch account_avatar_path, params: { avatar_source: "initials", primary_color: "270" }
        expect(user.reload.primary_color).to eq(270)
        expect(user.avatar_source).to eq("initials")
      end
    end

    describe "PATCH /account/avatar with cropped image" do
      it "saves both avatar and avatar_original" do
        cropped = fixture_file_upload("avatar.png", "image/png")
        original = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: {
          avatar: cropped,
          avatar_original: original,
          avatar_source: "upload",
          crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}'
        }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        expect(user.avatar_source).to eq("upload")
        metadata = user.avatar_original.blob.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end
    end

    describe "PATCH /account/avatar (turbo_stream)" do
      it "responds with turbo stream that updates avatars and closes modal" do
        patch account_avatar_path, params: { avatar_source: "initials", primary_color: "180" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("user_avatar_profile")
        expect(response.body).to include("user_avatar_header")
        expect(response.body).to include("modal-closer")
      end
    end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb --format documentation
```

Expected: FAIL — controller doesn't handle `primary_color`, `avatar_original`, `crop_coordinates`, or turbo_stream format.

- [ ] **Step 3: Rewrite the avatars controller**

Replace `app/controllers/account/avatars_controller.rb`:

```ruby
module Account
  class AvatarsController < ApplicationController
    def update
      user = Current.user

      # Handle file attachments (from crop save flow)
      if params[:avatar].present?
        user.avatar.attach(params[:avatar])
        user.avatar_source = "upload"
      end

      if params[:avatar_original].present?
        user.avatar_original.attach(params[:avatar_original])
      end

      # Store crop coordinates in original blob metadata
      if params[:crop_coordinates].present? && user.avatar_original.attached?
        coords = JSON.parse(params[:crop_coordinates])
        blob = user.avatar_original.blob
        blob.update!(metadata: blob.metadata.merge("crop" => coords))
      end

      # Handle source + color change (from hub save flow)
      if params[:avatar_source].present?
        source = params[:avatar_source]
        unless user.available_avatar_sources.include?(source)
          redirect_to edit_account_profile_path, alert: t("account.avatars.source_unavailable")
          return
        end
        user.avatar_source = source
      end

      if params[:primary_color].present?
        user.primary_color = params[:primary_color].to_i
      end

      if user.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_account_profile_path, notice: t(".success") }
        end
      else
        user.avatar.purge if params[:avatar].present?
        redirect_to edit_account_profile_path, alert: user.errors.full_messages.to_sentence
      end
    end

    def destroy
      Current.user.avatar.purge
      Current.user.avatar_original.purge if Current.user.avatar_original.attached?
      Current.user.update!(avatar_source: "initials")
      redirect_to edit_account_profile_path, notice: t(".success")
    end
  end
end
```

- [ ] **Step 4: Create the turbo stream template**

Create `app/views/account/avatars/update.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "user_avatar_profile" do %>
  <%= avatar_for(Current.user, size: :xl) %>
<% end %>

<%= turbo_stream.replace "user_avatar_header" do %>
  <%= avatar_for(Current.user, size: :md) %>
<% end %>

<%= turbo_stream.append "modal-body" do %>
  <div data-controller="modal-closer"></div>
<% end %>

<%= turbo_stream.prepend "flash" do %>
  <%= render "shared/toast_pill", type: :success, message: t("account.avatars.update.success") %>
<% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb --format documentation
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/account/avatars_controller.rb app/views/account/avatars/update.turbo_stream.erb spec/requests/account/avatars_spec.rb
git commit -m "feat: avatars controller handles dual attachment and turbo stream

Accepts avatar, avatar_original, crop_coordinates, avatar_source,
and primary_color params. Stores crop coords in original blob
metadata. Turbo stream response updates all avatar instances on
page and closes the modal."
```

---

### Task 10: Profile Edit View Integration

**Files:**
- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Replace the placeholder with the identity picker modal**

In `app/views/account/profiles/edit.html.erb`, replace lines 7-16 (the placeholder section):

```erb
  <%# Avatar — opens identity picker modal %>
  <div class="flex items-center gap-6 mt-8 mb-8"
       data-controller="modal">

    <button data-action="click->modal#open"
            type="button"
            class="shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2
                   focus:ring-interactive-focus cursor-pointer group"
            aria-label="<%= t('account.avatars.edit.change') %>">
      <span id="user_avatar_profile" class="block relative">
        <%= avatar_for(@user, size: :xl) %>
        <span class="absolute inset-0 rounded-full bg-black/0 group-hover:bg-black/20
                     transition-colors flex items-center justify-center">
          <%= icon(:pencil, size: :md,
                class: "text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md") %>
        </span>
      </span>
    </button>

    <div>
      <p class="text-lg font-semibold text-text-heading"><%= @user.full_name %></p>
      <button data-action="click->modal#open"
              type="button"
              class="text-sm text-interactive underline hover:no-underline mt-1
                     min-h-[44px] min-w-[44px]
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
        <%= t("account.avatars.edit.change") %>
      </button>
    </div>

    <%= render "shared/modal", title: t("identity_picker.edit_profile_picture"), size: :lg do %>
      <%= render "shared/identity_picker",
            model: @user,
            form_url: account_avatar_path,
            available_sources: @user.available_avatar_sources,
            has_color_picker: true,
            title: t("identity_picker.edit_profile_picture") %>
    <% end %>
  </div>
```

- [ ] **Step 2: Add missing locale key**

In `config/locales/en/account.en.yml`, add under `identity_picker:`:

```yaml
    edit_profile_picture: "Edit profile picture"
    edit_workspace_logo: "Edit workspace logo"
```

- [ ] **Step 3: Verify the page renders**

```bash
mise exec -- bundle exec rspec spec/requests/account/profiles_spec.rb --format documentation
```

Expected: PASS — profile edit page renders without errors.

- [ ] **Step 4: Commit**

```bash
git add app/views/account/profiles/edit.html.erb config/locales/en/account.en.yml
git commit -m "feat: wire identity picker modal into profile edit page

Replace placeholder with clickable avatar that opens the identity
picker modal. Supports all three sources, OKLCH color picker,
and crop editor."
```

---

### Task 11: Workspace Branding Integration

**Files:**
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Modify: `app/views/workspaces/brandings/edit.html.erb`
- Create: `app/views/workspaces/brandings/update.turbo_stream.erb`
- Test: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Write failing specs**

Add to `spec/requests/workspaces/brandings_spec.rb`, inside `"authenticated"`:

```ruby
    describe "PATCH /workspaces/:workspace_slug/branding with logo + original" do
      it "saves both logo and logo_original" do
        cropped = fixture_file_upload("avatar.png", "image/png")
        original = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          logo: cropped,
          logo_original: original,
          crop_coordinates: '{"x":5,"y":10,"w":80,"h":80}'
        }
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.logo_original).to be_attached
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding (turbo_stream)" do
      it "responds with turbo stream that updates logo and closes modal" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("workspace_logo_branding")
        expect(response.body).to include("modal-closer")
      end
    end
```

- [ ] **Step 2: Update the brandings controller**

Replace `app/controllers/workspaces/brandings_controller.rb`:

```ruby
module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      # Remove logo (from identity picker or form)
      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        @workspace.logo_original.purge if @workspace.logo_original.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Handle logo attachments (from identity picker crop flow)
      if params[:logo].present?
        @workspace.logo.attach(params[:logo])
      end

      if params[:logo_original].present?
        @workspace.logo_original.attach(params[:logo_original])
      end

      # Store crop coordinates
      if params[:crop_coordinates].present? && @workspace.logo_original.attached?
        coords = JSON.parse(params[:crop_coordinates])
        blob = @workspace.logo_original.blob
        blob.update!(metadata: blob.metadata.merge("crop" => coords))
      end

      # Handle nested form params (branding form)
      if params.dig(:workspace, :logo).present?
        @workspace.logo.attach(params[:workspace][:logo])
      end

      if @workspace.update(branding_params)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_workspace_branding_path(@workspace), notice: t(".success") }
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    rescue ActionController::ParameterMissing
      {}
    end
  end
end
```

- [ ] **Step 3: Create the turbo stream template**

Create `app/views/workspaces/brandings/update.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "workspace_logo_branding" do %>
  <%= workspace_icon_for(@workspace, size: :lg) %>
<% end %>

<%= turbo_stream.append "modal-body" do %>
  <div data-controller="modal-closer"></div>
<% end %>

<%= turbo_stream.prepend "flash" do %>
  <%= render "shared/toast_pill", type: :success, message: t("workspaces.brandings.update.success") %>
<% end %>
```

- [ ] **Step 4: Add identity picker to branding edit view**

In `app/views/workspaces/brandings/edit.html.erb`, replace the logo section (the `<%# Logo section %>` div) with:

```erb
  <%# Logo section — identity picker modal %>
  <div class="mt-8 space-y-2">
    <p class="block text-sm font-medium text-text-body">
      <%= t("workspaces.brandings.edit.logo_label") %>
    </p>
    <div class="flex items-center gap-4" data-controller="modal">
      <button data-action="click->modal#open"
              type="button"
              class="shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2
                     focus:ring-interactive-focus cursor-pointer group">
        <span id="workspace_logo_branding" class="block relative">
          <%= workspace_icon_for(@workspace, size: :lg) %>
          <span class="absolute inset-0 rounded-full bg-black/0 group-hover:bg-black/20
                       transition-colors flex items-center justify-center">
            <%= icon(:pencil, size: :sm,
                  class: "text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md") %>
          </span>
        </span>
      </button>
      <button data-action="click->modal#open"
              type="button"
              class="text-sm text-interactive underline hover:no-underline
                     min-h-[44px] min-w-[44px]
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
        <%= t("workspaces.brandings.edit.change_logo") %>
      </button>

      <%= render "shared/modal", title: t("identity_picker.edit_workspace_logo"), size: :lg do %>
        <%= render "shared/identity_picker",
              model: @workspace,
              form_url: workspace_branding_path(@workspace),
              available_sources: %w[upload initials],
              has_color_picker: false,
              title: t("identity_picker.edit_workspace_logo") %>
      <% end %>
    </div>
  </div>
```

- [ ] **Step 5: Run specs**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/workspaces/brandings_controller.rb app/views/workspaces/brandings/update.turbo_stream.erb app/views/workspaces/brandings/edit.html.erb spec/requests/workspaces/brandings_spec.rb
git commit -m "feat: wire identity picker into workspace branding page

Workspace logo uses the shared identity picker with upload and
initials sources (no gravatar, no color picker). Turbo stream
response updates logo display and closes modal."
```

---

### Task 12: Full Verification

- [ ] **Step 1: Run the full non-system test suite**

```bash
mise exec -- bundle exec rspec --exclude-pattern "spec/system/**/*_spec.rb" --format progress
```

Expected: 0 failures.

- [ ] **Step 2: Check for dangling references or missing translations**

```bash
grep -r "identity_picker_coming_soon" app/ config/ --include="*.erb" --include="*.yml" 2>/dev/null
```

If found in views, the placeholder text should have been replaced. Remove any remaining references.

```bash
grep -r "translation missing" tmp/log/test.log 2>/dev/null | tail -5
```

Check for missing I18n keys.

- [ ] **Step 3: Verify routes**

```bash
mise exec -- bin/rails routes | grep -E "avatar|branding"
```

Expected: avatar routes show PATCH and DELETE. Branding routes show GET edit and PATCH update.

- [ ] **Step 4: Start dev server and manually verify**

```bash
mise exec -- bin/dev
```

Verify:
1. Profile edit page loads — clicking avatar opens identity picker modal
2. Source cards switch the preview
3. Color slider appears for initials, updates preview in real-time
4. File picker opens when selecting Photo with no image
5. Crop editor loads with Cropper.js v2 when image selected
6. Save crop uploads and returns to hub
7. Save & apply closes modal and updates page avatars
8. Workspace branding page — logo identity picker works (upload + initials only)
9. No JavaScript console errors
10. Keyboard navigation works (arrow keys on source cards, zoom slider)

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: address verification findings"
```
