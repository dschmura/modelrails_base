# Cropper.js Image Crop UX Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom pan/zoom image crop controller with Cropper.js v1 to provide draggable selection handles, a live preview, and in-modal crop support.

**Architecture:** A thin Stimulus controller (`image-cropper`) wraps Cropper.js v1, bridging it to the existing `_image_crop` partial and form submission pattern. The backend is untouched — crop coordinates are stored in the same `crop[x,y,w,h]` format. Turbo Streams enable in-modal upload→crop→save transitions.

**Tech Stack:** Rails 8.1, Cropper.js v1 (1.6.x) via importmap, Stimulus, Turbo Streams, Capybara + Playwright for system specs.

**Spec:** `docs/superpowers/specs/2026-04-07-cropperjs-image-crop-design.md`

---

## File Structure

### Create

| File | Responsibility |
|------|---------------|
| `app/javascript/controllers/image_cropper_controller.js` | Stimulus wrapper for Cropper.js v1 — initializes, reads/restores crop data, fills hidden fields on save, handles keyboard shortcuts, manages lifecycle |
| `app/assets/stylesheets/vendor/cropper.css` | Vendored Cropper.js CSS with design token overrides for handles, guides, overlay |
| `app/views/account/avatars/update.turbo_stream.erb` | Turbo Stream response: replaces modal body with crop UI after upload |
| `app/views/account/avatars/save_crop.turbo_stream.erb` | Turbo Stream response: closes modal and updates avatar display |

### Modify

| File | Change |
|------|--------|
| `config/importmap.rb` | Add `pin "cropperjs"` |
| `app/views/shared/_image_crop.html.erb` | Replace custom viewport with Cropper.js-compatible `<img>` + preview element, update controller reference |
| `app/javascript/controllers/modal_controller.js` | Dispatch `modal:opened` event after `animateIn` completes |
| `app/controllers/account/avatars_controller.rb` | Add `respond_to` for turbo_stream in `update` and `save_crop` |
| `app/views/account/avatars/crop.html.erb` | Pass existing crop data to partial |
| `app/views/account/profiles/edit.html.erb` | Add turbo target ID on avatar element |
| `config/locales/en/image_crop.en.yml` | Update instruction text |
| `.gitignore` | Add `.superpowers/` |
| `app/assets/stylesheets/application.css` | Import vendor/cropper.css |

### Delete

| File | Reason |
|------|--------|
| `app/javascript/controllers/image_crop_controller.js` | Replaced by `image_cropper_controller.js` |

### Test Files

| File | Purpose |
|------|---------|
| `spec/requests/account/avatars_spec.rb` | Add turbo_stream format specs for `update` and `save_crop` |
| `spec/system/image_crop_spec.rb` | Update selectors from `image-crop` to `image-cropper`, add Cropper.js interaction tests |

---

## Task 1: Add .superpowers/ to .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add .superpowers/ to .gitignore**

Add this line to `.gitignore`:

```
/.superpowers
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .superpowers/ to .gitignore"
```

---

## Task 2: Pin Cropper.js v1 and vendor its CSS

**Files:**
- Modify: `config/importmap.rb`
- Create: `app/assets/stylesheets/vendor/cropper.css`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Pin cropperjs via importmap**

```bash
bin/importmap pin cropperjs@1.6.2
```

Verify the pin was added to `config/importmap.rb`. It should look like:

```ruby
pin "cropperjs", to: "https://ga.jspm.io/npm:cropperjs@1.6.2/dist/cropper.esm.js"
```

If the automatic pin doesn't resolve to the ESM build, manually add:

```ruby
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.esm.js"
```

- [ ] **Step 2: Vendor the Cropper.js CSS**

Download the Cropper.js CSS and save it to `app/assets/stylesheets/vendor/cropper.css`. Then add design token overrides at the bottom of the file.

The key overrides needed for Tailwind 4 compatibility and design token integration:

```css
/* === Design token overrides === */

/* Tailwind 4 preflight sets img { max-width: 100% } which breaks Cropper.js */
.cropper-container img {
  max-width: none;
}

/* Use design tokens for selection handles instead of hardcoded blue */
.cropper-point {
  background-color: var(--color-interactive);
  opacity: 1;
  width: 10px;
  height: 10px;
}

/* Enlarge handles on touch devices */
@media (pointer: coarse) {
  .cropper-point {
    width: 14px;
    height: 14px;
  }
}

/* Selection border */
.cropper-view-box {
  outline-color: var(--color-interactive);
}

/* Guide lines — dashed white on dark overlay */
.cropper-dashed {
  border-color: rgba(255, 255, 255, 0.4);
}

/* Center crosshair */
.cropper-center {
  opacity: 0.6;
}
```

Fetch the base CSS:

```bash
curl -o app/assets/stylesheets/vendor/cropper.css \
  "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.min.css"
```

Then append the design token overrides above to the end of the file.

- [ ] **Step 3: Import the CSS in application.css**

Add to `app/assets/stylesheets/application.css`:

```css
/* Cropper.js styles with design token overrides */
/*= require vendor/cropper */
```

Note: If Propshaft is configured to serve all files in `app/assets/stylesheets/`, verify the CSS is loaded by checking the browser network tab. Propshaft may auto-serve it without an explicit require.

- [ ] **Step 4: Verify importmap resolves**

```bash
bin/rails runner "puts Rails.application.importmap.to_json" | grep cropperjs
```

Expected: a JSON entry mapping `"cropperjs"` to its URL.

- [ ] **Step 5: Commit**

```bash
git add config/importmap.rb app/assets/stylesheets/vendor/cropper.css app/assets/stylesheets/application.css
git commit -m "feat: add Cropper.js v1 dependency and vendored CSS with design token overrides"
```

---

## Task 3: Create the image-cropper Stimulus controller

**Files:**
- Create: `app/javascript/controllers/image_cropper_controller.js`

- [ ] **Step 1: Write the Stimulus controller**

Create `app/javascript/controllers/image_cropper_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

export default class extends Controller {
  static targets = ["image", "preview", "x", "y", "w", "h", "slider", "liveRegion"]
  static values = {
    aspectRatio: { type: Number, default: 1 },
    existingCrop: { type: Object, default: {} },
    viewMode: { type: Number, default: 1 }
  }

  connect() {
    this.cropper = null

    if (this.imageTarget.complete && this.imageTarget.naturalWidth > 0) {
      this.#initCropper()
    } else {
      this.imageTarget.addEventListener("load", () => this.#initCropper(), { once: true })
    }

    // Listen for modal:opened in case we're inside a closed dialog
    this.#modalOpenedHandler = () => {
      if (!this.cropper) this.#initCropper()
    }
    document.addEventListener("modal:opened", this.#modalOpenedHandler)
  }

  disconnect() {
    document.removeEventListener("modal:opened", this.#modalOpenedHandler)
    if (this.cropper) {
      this.cropper.destroy()
      this.cropper = null
    }
  }

  save() {
    if (!this.cropper) return
    const data = this.cropper.getData(true)
    this.xTarget.value = data.x
    this.yTarget.value = data.y
    this.wTarget.value = data.width
    this.hTarget.value = data.height
  }

  handleSlider(event) {
    if (!this.cropper) return
    const imageData = this.cropper.getImageData()
    const minZoom = imageData.width / imageData.naturalWidth
    const maxZoom = minZoom * 5
    const value = parseFloat(event.target.value)
    const ratio = minZoom + (maxZoom - minZoom) * (value / 100)
    this.cropper.zoomTo(ratio)
  }

  handleKeydown(event) {
    if (!this.cropper) return
    const step = event.shiftKey ? 10 : 1
    const actions = {
      ArrowLeft: () => this.cropper.move(-step, 0),
      ArrowRight: () => this.cropper.move(step, 0),
      ArrowUp: () => this.cropper.move(0, -step),
      ArrowDown: () => this.cropper.move(0, step),
      "+": () => this.cropper.zoom(0.1),
      "=": () => this.cropper.zoom(0.1),
      "-": () => this.cropper.zoom(-0.1)
    }
    const action = actions[event.key]
    if (action) {
      event.preventDefault()
      action()
    }
  }

  reset() {
    if (!this.cropper) return
    this.cropper.reset()
    this.#syncSlider()
  }

  // Private

  #initCropper() {
    // Guard: if inside a closed dialog, defer initialization
    const dialog = this.element.closest("dialog")
    if (dialog && !dialog.open) return

    const previewSelector = this.hasPreviewTarget
      ? `[data-image-cropper-target="preview"]`
      : undefined

    this.cropper = new Cropper(this.imageTarget, {
      aspectRatio: this.aspectRatioValue,
      viewMode: this.viewModeValue,
      dragMode: "move",
      autoCropArea: 1,
      responsive: true,
      restore: false,
      guides: true,
      center: true,
      highlight: false,
      background: true,
      preview: previewSelector,
      ready: () => {
        this.#restoreExistingCrop()
        this.#syncSlider()
        this.#warnIfLargeImage()
      },
      crop: () => {
        this.#syncSlider()
        this.#announceChange()
      }
    })
  }

  #restoreExistingCrop() {
    const crop = this.existingCropValue
    if (crop && crop.x != null && crop.w > 0 && crop.h > 0) {
      this.cropper.setData({
        x: crop.x,
        y: crop.y,
        width: crop.w,
        height: crop.h
      })
    }
  }

  #syncSlider() {
    if (!this.hasSliderTarget || !this.cropper) return
    const imageData = this.cropper.getImageData()
    const currentZoom = imageData.width / imageData.naturalWidth
    const minZoom = this.cropper.getCanvasData().naturalWidth
      ? imageData.width / imageData.naturalWidth
      : 1
    const maxZoom = minZoom * 5
    const pct = ((currentZoom - minZoom) / (maxZoom - minZoom)) * 100
    this.sliderTarget.value = Math.max(0, Math.min(100, pct))
  }

  #announceChange() {
    if (!this.hasLiveRegionTarget || !this.cropper) return
    const data = this.cropper.getData(true)
    this.liveRegionTarget.textContent =
      `Crop area: ${data.width} by ${data.height} pixels at position ${data.x}, ${data.y}`
  }

  #warnIfLargeImage() {
    const img = this.imageTarget
    if (img.naturalWidth > 4096 || img.naturalHeight > 4096) {
      console.warn(
        `image-cropper: Large image detected (${img.naturalWidth}x${img.naturalHeight}). ` +
        `Consider client-side downscaling for better performance on mobile devices.`
      )
    }
  }
}
```

- [ ] **Step 2: Verify the controller is registered**

The `pin_all_from "app/javascript/controllers"` in `config/importmap.rb` auto-discovers new controllers. Verify by starting the Rails server and checking the browser console for Stimulus controller registration.

```bash
bin/rails server
```

Open browser console, look for: `stimulus: connected image-cropper` (or no errors).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/image_cropper_controller.js
git commit -m "feat: add image-cropper Stimulus controller wrapping Cropper.js v1"
```

---

## Task 4: Dispatch modal:opened event from modal controller

**Files:**
- Modify: `app/javascript/controllers/modal_controller.js`

- [ ] **Step 1: Add event dispatch after animateIn completes**

In `app/javascript/controllers/modal_controller.js`, update the `animateIn()` method to dispatch a custom event after the animation completes.

For the non-reduced-motion path, add the dispatch after the transition. For the reduced-motion path, dispatch immediately.

Replace the `animateIn()` method:

```javascript
  animateIn() {
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = "scale(1)"
      document.dispatchEvent(new CustomEvent("modal:opened"))
      return
    }

    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = "scale(0.95)"
    requestAnimationFrame(() => {
      const duration = getComputedStyle(document.documentElement)
        .getPropertyValue("--modal-animation-duration").trim() || "200ms"
      this.panelTarget.style.transition = `opacity ${duration} ease-out, transform ${duration} ease-out`
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = "scale(1)"

      const ms = parseInt(duration, 10) || 200
      setTimeout(() => {
        document.dispatchEvent(new CustomEvent("modal:opened"))
      }, ms)
    })
  }
```

- [ ] **Step 2: Verify existing modal tests still pass**

```bash
bundle exec rspec spec/system/modal_spec.rb
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/modal_controller.js
git commit -m "feat: dispatch modal:opened event after animation completes"
```

---

## Task 5: Update locale strings

**Files:**
- Modify: `config/locales/en/image_crop.en.yml`

- [ ] **Step 1: Update instruction text**

Replace the contents of `config/locales/en/image_crop.en.yml`:

```yaml
en:
  image_crop:
    instructions: "Drag to reposition · Resize corners to zoom"
    instructions_circle: "Image will be cropped to a circle"
    instructions_rect: "Image will be cropped to a rectangle"
    zoom: "Zoom"
    save: "Save crop"
    saving: "Saving..."
    skip: "Skip cropping"
    cancel: "Cancel"
    reset: "Reset"
    upload_different: "Upload a different image"
    use_initials: "Use initials instead"
    remove_photo: "Remove photo"
    remove_confirm: "Are you sure you want to remove this photo?"
    no_image: "Upload an image first."
    preview: "Preview:"
    crop_area_label: "Image cropper"
    crop_area_description: "Use arrow keys to move, plus and minus to zoom, or drag to reposition"
```

- [ ] **Step 2: Commit**

```bash
git add config/locales/en/image_crop.en.yml
git commit -m "feat: update image crop locale strings for Cropper.js UI"
```

---

## Task 6: Replace the _image_crop partial with Cropper.js markup

**Files:**
- Modify: `app/views/shared/_image_crop.html.erb`

- [ ] **Step 1: Rewrite the partial**

Replace the contents of `app/views/shared/_image_crop.html.erb` with:

```erb
<%# locals: (image:, aspect_ratio: 1.0, shape: :circle, save_url:, cancel_url:,
             upload_action: nil, remove_url: nil, remove_method: :delete,
             use_initials_url: nil, use_initials_params: nil,
             existing_crop: {}, title:) -%>
<%
  shape_instruction = shape == :circle ? t("image_crop.instructions_circle") : t("image_crop.instructions_rect")
  preview_class = shape == :circle ? "rounded-full" : "rounded-md"
  has_secondary = upload_action.present? || use_initials_url.present? || remove_url.present?
%>

<div class="max-w-2xl mx-auto px-4 py-12 sm:py-16">

  <%# Card container %>
  <div class="bg-surface-overlay border border-border rounded-xl shadow-lg overflow-hidden">

    <%# Header %>
    <div class="px-6 py-4 border-b border-border">
      <h1 class="text-lg font-semibold text-text-heading"><%= title %></h1>
      <p class="text-sm text-text-muted mt-0.5">
        <%= t("image_crop.instructions") %> · <%= shape_instruction %>
      </p>
    </div>

    <%# Crop form %>
    <%= form_with url: save_url, method: :patch do |f| %>
      <div data-controller="image-cropper"
           data-image-cropper-aspect-ratio-value="<%= aspect_ratio %>"
           data-image-cropper-existing-crop-value="<%= existing_crop.to_json %>"
           data-image-cropper-view-mode-value="1">

        <%# Crop viewport — Cropper.js takes over this container %>
        <div tabindex="0"
             role="application"
             aria-roledescription="<%= t('image_crop.crop_area_label') %>"
             aria-describedby="crop-description"
             data-action="keydown->image-cropper#handleKeydown"
             class="relative overflow-hidden bg-neutral-900
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:ring-inset"
             style="max-height: 55vh;">
          <%= image_tag url_for(image),
                data: { image_cropper_target: "image" },
                class: "block max-w-full",
                draggable: false,
                alt: title %>
        </div>
        <p id="crop-description" class="sr-only"><%= t("image_crop.crop_area_description") %></p>

        <%# Live region for screen reader announcements %>
        <div data-image-cropper-target="liveRegion"
             aria-live="polite"
             aria-atomic="true"
             class="sr-only">
        </div>

        <%# Live preview %>
        <div class="px-6 py-4 border-t border-border text-center">
          <p class="text-sm font-medium text-text-heading mb-2"><%= t("image_crop.preview") %></p>
          <div data-image-cropper-target="preview"
               class="inline-block overflow-hidden <%= preview_class %> border-2 border-border
                      w-12 h-12 sm:w-16 sm:h-16 md:w-20 md:h-20">
          </div>
        </div>

        <%# Zoom controls %>
        <div class="px-6 py-4 border-t border-border">
          <div class="flex items-center gap-4">
            <svg class="w-4 h-4 text-text-muted shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607zM13.5 10.5h-6" />
            </svg>
            <input type="range" min="0" max="100" value="0"
                   data-image-cropper-target="slider"
                   data-action="input->image-cropper#handleSlider"
                   aria-label="<%= t('image_crop.zoom') %>"
                   class="flex-1 h-1.5 rounded-full appearance-none bg-border-strong cursor-pointer
                          [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:w-4
                          [&::-webkit-slider-thumb]:h-4 [&::-webkit-slider-thumb]:rounded-full
                          [&::-webkit-slider-thumb]:bg-interactive [&::-webkit-slider-thumb]:cursor-pointer
                          [&::-webkit-slider-thumb]:shadow-sm [&::-webkit-slider-thumb]:border-2
                          [&::-webkit-slider-thumb]:border-white
                          [&::-moz-range-thumb]:w-4 [&::-moz-range-thumb]:h-4
                          [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-interactive
                          [&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-white
                          [&::-moz-range-thumb]:cursor-pointer">
            <svg class="w-4 h-4 text-text-muted shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607zM10.5 7.5v6m3-3h-6" />
            </svg>
          </div>
          <div class="flex justify-end mt-3">
            <button type="button"
                    data-action="click->image-cropper#reset"
                    class="text-xs text-text-muted hover:text-text-body underline underline-offset-2
                           focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded
                           min-h-[44px] inline-flex items-center px-1">
              <%= t("image_crop.reset") %>
            </button>
          </div>
        </div>

        <%# Hidden crop coordinates %>
        <input type="hidden" name="crop[x]" value="0" data-image-cropper-target="x">
        <input type="hidden" name="crop[y]" value="0" data-image-cropper-target="y">
        <input type="hidden" name="crop[w]" value="0" data-image-cropper-target="w">
        <input type="hidden" name="crop[h]" value="0" data-image-cropper-target="h">

        <%# Primary actions: Save + Skip %>
        <div class="px-6 py-4 border-t border-border bg-surface-sunken/30">
          <div class="flex flex-col sm:flex-row-reverse gap-3">
            <button type="submit"
                    data-action="click->image-cropper#save"
                    data-turbo-submits-with="<%= t('image_crop.saving') %>"
                    class="inline-flex items-center justify-center
                           min-h-[44px] px-8 py-2.5 rounded-md
                           text-sm font-semibold text-white
                           bg-interactive hover:bg-interactive-hover
                           focus:outline-none focus:ring-2 focus:ring-interactive-focus
                           sm:w-auto w-full">
              <%= t("image_crop.save") %>
            </button>
            <%= link_to t("image_crop.skip"), cancel_url,
                  class: "inline-flex items-center justify-center
                         min-h-[44px] px-6 py-2.5 rounded-md
                         text-sm font-medium text-text-muted hover:text-text-body
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus
                         sm:w-auto w-full" %>
          </div>
        </div>

      </div>
    <% end %>

    <%# Secondary actions — OUTSIDE the crop form to avoid nested form issues %>
    <% if has_secondary %>
      <div class="px-6 py-3 border-t border-border
                  flex flex-wrap items-center justify-center gap-x-4 gap-y-1">
        <% if upload_action.present? %>
          <button type="button"
                  data-action="<%= upload_action %>"
                  class="text-sm text-text-muted hover:text-interactive underline underline-offset-2
                         min-h-[44px] inline-flex items-center
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
            <%= t("image_crop.upload_different") %>
          </button>
        <% end %>
        <% if use_initials_url.present? %>
          <%= button_to t("image_crop.use_initials"), use_initials_url,
                method: :patch,
                params: use_initials_params || {},
                class: "text-sm text-text-muted hover:text-interactive underline underline-offset-2
                       min-h-[44px] inline-flex items-center
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
        <% end %>
        <% if remove_url.present? %>
          <%= button_to t("image_crop.remove_photo"), remove_url,
                method: remove_method,
                params: { remove_image: "1" },
                class: "text-sm text-danger hover:text-danger/80 underline underline-offset-2
                       min-h-[44px] inline-flex items-center
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded",
                data: { turbo_confirm: t("image_crop.remove_confirm") } %>
        <% end %>
      </div>
    <% end %>

  </div>
</div>
```

- [ ] **Step 2: Update the crop page to pass existing crop data**

Modify `app/views/account/avatars/crop.html.erb` to read existing crop coordinates from blob metadata and pass them to the partial:

```erb
<% content_for(:title) { t("account.avatars.crop.title") } %>
<%
  existing_crop = Current.user.avatar.blob.metadata["crop"] || {}
%>

<div data-controller="modal"
     data-action="keydown.esc@document->modal#handleEscOnPage">

  <%= render "shared/image_crop",
        image: Current.user.avatar,
        aspect_ratio: 1.0,
        shape: :circle,
        save_url: save_crop_account_avatar_path,
        cancel_url: edit_account_profile_path,
        upload_action: "click->modal#open",
        use_initials_url: account_avatar_path,
        use_initials_params: { avatar_source: "initials" },
        remove_url: account_avatar_path,
        remove_method: :delete,
        existing_crop: existing_crop,
        title: t("account.avatars.crop.title") %>

  <%= render "shared/image_upload_modal",
        title: t("account.avatars.edit.title"),
        form_url: account_avatar_path,
        field_name: :avatar,
        auto_submit: true %>
</div>
```

- [ ] **Step 3: Start the server and visually verify the crop page**

```bash
bin/rails server
```

Visit the profile page, upload an avatar, verify the crop page shows:
- Cropper.js selection box with drag handles
- Checkered transparency background
- Live circular preview below
- Zoom slider syncs with scroll zoom
- Save/Skip buttons work
- Instruction text updated

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_image_crop.html.erb app/views/account/avatars/crop.html.erb
git commit -m "feat: replace custom crop viewport with Cropper.js UI and live preview"
```

---

## Task 7: Delete the old image-crop controller

**Files:**
- Delete: `app/javascript/controllers/image_crop_controller.js`

- [ ] **Step 1: Verify no other files reference image_crop_controller**

Search for references to the old controller name:

```bash
grep -r "image-crop" app/views/ app/javascript/ --include="*.erb" --include="*.js" -l
grep -r "image_crop" app/javascript/controllers/ -l
```

Expected: no matches (the partial was already updated in Task 6).

- [ ] **Step 2: Delete the old controller**

```bash
rm app/javascript/controllers/image_crop_controller.js
```

- [ ] **Step 3: Commit**

```bash
git add -A app/javascript/controllers/image_crop_controller.js
git commit -m "chore: remove old custom image-crop Stimulus controller"
```

---

## Task 8: Update existing specs for new controller selectors

**Files:**
- Modify: `spec/system/image_crop_spec.rb`

- [ ] **Step 1: Update system spec selectors**

The system spec references `data-controller='image-crop'` and `data-image-crop-target='image'` — update these to the new controller name.

Replace the contents of `spec/system/image_crop_spec.rb`:

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

    it "shows crop page with Cropper.js and controls" do
      visit crop_account_avatar_path
      dismiss_banner
      expect(page).to have_text(I18n.t("account.avatars.crop.title"))
      expect(page).to have_css("[data-controller='image-cropper']")
      expect(page).to have_css("img[data-image-cropper-target='image']")
      expect(page).to have_css("[data-image-cropper-target='preview']")
      expect(page).to have_button(I18n.t("image_crop.save"))
      expect(page).to have_link(I18n.t("image_crop.skip"))
    end

    it "saves crop and redirects to profile" do
      visit crop_account_avatar_path
      dismiss_banner
      click_button I18n.t("image_crop.save")
      expect(page).to have_text(I18n.t("account.avatars.save_crop.success"), wait: 5)
    end

    it "skip returns to profile without saving" do
      visit crop_account_avatar_path
      dismiss_banner
      click_link I18n.t("image_crop.skip")
      expect(page).to have_current_path(edit_account_profile_path)
    end

    it "profile page links to crop and upload when avatar exists" do
      visit edit_account_profile_path
      dismiss_banner
      expect(page).to have_link(I18n.t("account.avatars.crop.link"))
      expect(page).to have_button(I18n.t("account.avatars.edit.upload_new"))
    end

    it "restores previous crop position on re-visit" do
      # First crop
      user.avatar.blob.update!(
        metadata: user.avatar.blob.metadata.merge("crop" => { "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
      )
      visit crop_account_avatar_path
      dismiss_banner
      # Verify the existing crop data is present in the DOM
      expect(page).to have_css(
        "[data-image-cropper-existing-crop-value]"
      )
      crop_json = find("[data-controller='image-cropper']")["data-image-cropper-existing-crop-value"]
      crop_data = JSON.parse(crop_json)
      expect(crop_data).to include("x" => 10, "y" => 20, "w" => 100, "h" => 100)
    end
  end
end
```

- [ ] **Step 2: Run the updated specs**

```bash
bundle exec rspec spec/system/image_crop_spec.rb
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add spec/system/image_crop_spec.rb
git commit -m "test: update image crop system specs for Cropper.js controller selectors"
```

---

## Task 9: Add Turbo Stream responses for in-modal crop flow

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`
- Create: `app/views/account/avatars/update.turbo_stream.erb`
- Create: `app/views/account/avatars/save_crop.turbo_stream.erb`
- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Write request spec for turbo_stream format on update**

Add to `spec/requests/account/avatars_spec.rb`, inside the `"authenticated"` context, after the existing `"PATCH /account/avatar"` describe block:

```ruby
    describe "PATCH /account/avatar (turbo_stream)" do
      it "responds with turbo stream containing crop UI after upload" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("image-cropper")
      end
    end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb -e "turbo_stream"
```

Expected: FAIL — currently the controller always redirects.

- [ ] **Step 3: Write request spec for turbo_stream format on save_crop**

Add to `spec/requests/account/avatars_spec.rb`, inside the `"authenticated"` context:

```ruby
    describe "PATCH /account/avatar/save_crop (turbo_stream)" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
      end

      it "responds with turbo stream that updates avatar" do
        patch save_crop_account_avatar_path,
              params: { crop: { x: 10, y: 20, w: 100, h: 100 } },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("user_avatar_profile")
        metadata = user.avatar.blob.reload.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end
    end
```

- [ ] **Step 4: Run it to verify it fails**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb -e "turbo_stream"
```

Expected: both new specs fail.

- [ ] **Step 5: Update the avatars controller with respond_to blocks**

Replace the contents of `app/controllers/account/avatars_controller.rb`:

```ruby
module Account
  class AvatarsController < ApplicationController
    def crop
      unless Current.user.avatar.attached?
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        nil
      end
    end

    def save_crop
      attachment = ActiveStorage::Attachment.find_by(
        record_type: "User",
        record_id: Current.user.id,
        name: "avatar"
      )

      unless attachment
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        return
      end

      crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
      blob = ActiveStorage::Blob.find(attachment.blob_id)
      blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_account_profile_path, notice: t(".success") }
      end
    end

    def update
      file = params[:avatar]

      if file.present?
        Current.user.avatar.attach(file)
        Current.user.avatar_source = "upload"

        if Current.user.save
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to crop_account_avatar_path }
          end
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

- [ ] **Step 6: Create the update turbo_stream template**

Create `app/views/account/avatars/update.turbo_stream.erb`:

```erb
<%
  existing_crop = Current.user.avatar.blob.metadata["crop"] || {}
%>

<%= turbo_stream.replace "modal-body" do %>
  <div class="px-6 py-4 overflow-y-auto flex-1">
    <div data-controller="image-cropper"
         data-image-cropper-aspect-ratio-value="1.0"
         data-image-cropper-existing-crop-value="<%= existing_crop.to_json %>"
         data-image-cropper-view-mode-value="1">

      <%# Crop viewport %>
      <div tabindex="0"
           role="application"
           aria-roledescription="<%= t('image_crop.crop_area_label') %>"
           aria-describedby="modal-crop-description"
           data-action="keydown->image-cropper#handleKeydown"
           class="relative overflow-hidden bg-neutral-900 rounded-lg
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:ring-inset"
           style="max-height: 45vh;">
        <%= image_tag url_for(Current.user.avatar),
              data: { image_cropper_target: "image" },
              class: "block max-w-full",
              draggable: false,
              alt: t("account.avatars.crop.title") %>
      </div>
      <p id="modal-crop-description" class="sr-only"><%= t("image_crop.crop_area_description") %></p>

      <%# Live region %>
      <div data-image-cropper-target="liveRegion" aria-live="polite" aria-atomic="true" class="sr-only"></div>

      <%# Preview %>
      <div class="py-3 text-center">
        <p class="text-sm font-medium text-text-heading mb-2"><%= t("image_crop.preview") %></p>
        <div data-image-cropper-target="preview"
             class="inline-block overflow-hidden rounded-full border-2 border-border w-16 h-16">
        </div>
      </div>

      <%# Instruction text %>
      <p class="text-xs text-text-muted text-center mb-3">
        <%= t("image_crop.instructions") %> · <%= t("image_crop.instructions_circle") %>
      </p>

      <%# Save crop form %>
      <%= form_with url: save_crop_account_avatar_path, method: :patch do |f| %>
        <input type="hidden" name="crop[x]" value="0" data-image-cropper-target="x">
        <input type="hidden" name="crop[y]" value="0" data-image-cropper-target="y">
        <input type="hidden" name="crop[w]" value="0" data-image-cropper-target="w">
        <input type="hidden" name="crop[h]" value="0" data-image-cropper-target="h">
        <div class="flex flex-col gap-2">
          <button type="submit"
                  data-action="click->image-cropper#save"
                  data-turbo-submits-with="<%= t('image_crop.saving') %>"
                  class="inline-flex items-center justify-center
                         min-h-[44px] px-8 py-2.5 rounded-md w-full
                         text-sm font-semibold text-white
                         bg-interactive hover:bg-interactive-hover
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus">
            <%= t("image_crop.save") %>
          </button>
          <button type="button"
                  data-action="click->modal#close"
                  class="inline-flex items-center justify-center
                         min-h-[44px] px-6 py-2.5 rounded-md w-full
                         text-sm font-medium text-text-muted hover:text-text-body
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus">
            <%= t("image_crop.skip") %>
          </button>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 7: Create the save_crop turbo_stream template**

Create `app/views/account/avatars/save_crop.turbo_stream.erb`:

```erb
<%# Update the avatar display on the profile page %>
<%= turbo_stream.replace "user_avatar_profile" do %>
  <span id="user_avatar_profile" class="block relative">
    <%= avatar_for(Current.user, size: :xl) %>
  </span>
<% end %>

<%# Close the modal via a temporary script %>
<%= turbo_stream.append_all "body" do %>
  <template data-turbo-temporary>
    <script>
      document.querySelector("dialog[open]")?.close()
    </script>
  </template>
<% end %>

<%# Show success toast — uses the pill container from shared/toasts %>
<%= turbo_stream.prepend "toast-pills" do %>
  <%= render "shared/toast_pill", type: "notice", message: t(".success") %>
<% end %>
```

- [ ] **Step 8: Add a turbo frame ID to the modal body for targeting**

The `update.turbo_stream.erb` targets `#modal-body`. Add this ID to the modal body div in `app/views/shared/_modal.html.erb`.

In the modal partial, change:

```erb
    <div class="px-6 py-4 overflow-y-auto flex-1">
```

to:

```erb
    <div id="modal-body" class="px-6 py-4 overflow-y-auto flex-1">
```

- [ ] **Step 9: Run the request specs**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb
```

Expected: all pass, including the new turbo_stream format specs.

- [ ] **Step 10: Run the full avatar-related test suite**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb spec/system/image_crop_spec.rb spec/system/avatar_spec.rb
```

Expected: all pass.

- [ ] **Step 11: Commit**

```bash
git add app/controllers/account/avatars_controller.rb \
        app/views/account/avatars/update.turbo_stream.erb \
        app/views/account/avatars/save_crop.turbo_stream.erb \
        app/views/shared/_modal.html.erb \
        spec/requests/account/avatars_spec.rb
git commit -m "feat: add Turbo Stream responses for in-modal crop flow"
```

---

## Task 10: Add turbo_stream avatar target to profile page

**Files:**
- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Verify the avatar span already has the target ID**

Check that the `<span id="user_avatar_profile">` element exists in both branches (avatar attached and not attached) of the profile edit view. Looking at the current code, it already has `id="user_avatar_profile"` in both branches.

No changes needed — the ID is already in place. The `save_crop.turbo_stream.erb` from Task 9 targets this element.

- [ ] **Step 2: Commit (skip if no changes)**

No commit needed — the ID was already present.

---

## Task 11: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run the complete test suite**

```bash
bundle exec rspec
```

Expected: all specs pass, zero failures.

- [ ] **Step 2: Manually test the standalone crop flow**

1. Start the server: `bin/rails server`
2. Sign in and navigate to profile
3. Upload an avatar image
4. Verify redirect to crop page
5. Verify Cropper.js UI: drag handles, selection box, checkered background
6. Drag to reposition, resize corners
7. Verify live preview updates in real-time
8. Verify zoom slider syncs with scroll zoom
9. Click Save — verify redirect to profile with cropped avatar
10. Click Crop link — verify selection restores to previous position

- [ ] **Step 3: Test EXIF orientation**

Upload a photo taken on a phone in portrait mode (EXIF orientation flag set). Verify the crop UI displays the image upright, not rotated. Cropper.js v1 has `checkOrientation: true` by default which handles this.

- [ ] **Step 4: Manually test keyboard accessibility**

1. Tab to crop area — verify focus ring
2. Arrow keys move the crop selection
3. Shift+Arrow moves by 10px
4. `+`/`-` zoom in/out
5. Tab to slider, save button, skip link — verify full tab order

- [ ] **Step 5: Manually test the in-modal flow (if applicable)**

Note: The in-modal flow requires the upload form to submit as turbo_stream. The current upload modal uses `auto_submit: true` which calls `formTarget.requestSubmit()`. Verify that the form's `data-turbo` attribute or Turbo's default behavior sends the request as turbo_stream format. If the form inside the modal doesn't automatically send turbo_stream format, you may need to set `data: { turbo_stream: true }` on the form.

1. On profile page, click "Upload new" button
2. Select an image in the modal
3. Verify the modal content transitions to show crop UI
4. Crop and save — verify modal closes and avatar updates

- [ ] **Step 6: Commit any fixups**

If any issues were found in manual testing, fix and commit them individually with descriptive messages.

---

## Task 12: Accessibility audit

**Files:**
- Modify (if issues found): various view files

- [ ] **Step 1: Run axe-core on the crop page**

Add a temporary spec or use the existing accessibility test infrastructure:

```ruby
# In spec/system/image_crop_spec.rb, add:
it "passes accessibility audit" do
  visit crop_account_avatar_path
  dismiss_banner
  # Wait for Cropper.js to initialize
  expect(page).to have_css(".cropper-container", wait: 5)
  expect(page).to be_axe_clean
end
```

```bash
bundle exec rspec spec/system/image_crop_spec.rb -e "accessibility"
```

- [ ] **Step 2: Fix any accessibility issues found**

Address any violations reported by axe-core. Common issues:
- Missing labels on interactive elements
- Contrast ratios below 7:1 (AAA)
- Missing ARIA attributes

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: add accessibility audit for crop page, fix any violations"
```
