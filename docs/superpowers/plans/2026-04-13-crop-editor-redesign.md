# Crop Editor Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the crop editor view within the identity picker modal — dark immersive viewport, circular crop overlay, responsive two-column layout, and polished controls with visual hierarchy.

**Architecture:** Pure frontend changes across four layers: CSS (`cropper.css`), ERB (crop view section of `_identity_picker.html.erb`), Stimulus JS (dimension badge + zoom percentage in `image_cropper_controller.js`, modal size toggle in `identity_picker_controller.js`), and locale keys. No backend, no new controllers, no model changes.

**Tech Stack:** TailwindCSS 4, Cropper.js v2 Web Components, Stimulus, ERB partials, I18n YAML

**Spec:** `docs/superpowers/specs/2026-04-13-crop-editor-redesign.md`

**Important:** All commands in worktree must use `mise exec --` prefix (e.g., `mise exec -- bundle exec rspec`).

---

## File Structure

### Files to Modify

- `app/assets/stylesheets/components/cropper.css` — Dark viewport, circular selection, two-column container layout
- `app/views/shared/_identity_picker.html.erb` — Crop view section rewrite (lines 224-344), modal size data attribute
- `app/javascript/controllers/image_cropper_controller.js` — Dimension badge target + update logic, zoom percentage target + update logic
- `app/javascript/controllers/identity_picker_controller.js` — Modal panel size toggle on mode switch
- `config/locales/en/account.en.yml` — New locale keys, remove `back_to_hub`

---

### Task 1: Add New Locale Keys

**Files:**
- Modify: `config/locales/en/account.en.yml:72-102`

- [ ] **Step 1: Add new keys and update existing ones**

In `config/locales/en/account.en.yml`, replace the `identity_picker` block (lines 72-102) with:

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
    zoom_label: "Zoom Level"
    zoom_aria_label: "Zoom level"
    color_label: "Circle color"
    color_aria_label: "Circle color hue"
    result_label: "Result"
    result_description: "Circular preview"
    preview_title: "Circular Result"
    preview_description: "This is how your profile photo will look on the dashboard."
    reset_crop: "Reset"
    upload_new: "Upload new"
    remove_photo: "Remove photo"
    back: "Back"
    cancel: "Cancel"
    crop_hint: "Drag to move · Pinch to zoom"
    image_quality_tip: "High quality images work best. We recommend using a photo where your face is centered and clearly visible."
    edit_profile_picture: "Edit profile picture"
    edit_workspace_logo: "Edit workspace logo"
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

Changes from the original:
- `zoom_label` updated to "Zoom Level" (visible label, capitalized)
- Added `zoom_aria_label` for the range input's `aria-label` (keep lowercase for screen readers)
- Added `preview_title`, `preview_description`
- Added `cancel` (replaces `back_to_hub`)
- Added `crop_hint`, `image_quality_tip`
- Removed `back_to_hub`

- [ ] **Step 2: Run tests to verify locale keys don't break anything**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All 920 tests pass. Any test referencing `back_to_hub` will fail — if so, update the test to use `cancel`.

- [ ] **Step 3: Commit**

```bash
git add config/locales/en/account.en.yml
git commit -m "feat: add crop editor redesign locale keys"
```

---

### Task 2: Dark Viewport and Circular Overlay CSS

**Files:**
- Modify: `app/assets/stylesheets/components/cropper.css`

- [ ] **Step 1: Rewrite cropper.css**

Replace the entire contents of `app/assets/stylesheets/components/cropper.css` with:

```css
/* Cropper.js v2 — crop editor styling */

/* ── Dark immersive viewport ── */

.cropper-container {
  height: min(50vh, 400px);
  width: 100%;
  position: relative;
  overflow: hidden;
  background: var(--neutral-900);
  border-radius: var(--radius-lg, 0.5rem);
}

.dark .cropper-container {
  background: var(--neutral-950);
}

/* Cropper.js v2 Web Components must fill the container */
.cropper-container cropper-canvas {
  display: block;
  width: 100%;
  height: 100%;
}

/* Canvas background matches container (no flash on init) */
cropper-canvas {
  background: var(--neutral-900);
}

.dark cropper-canvas {
  background: var(--neutral-950);
}

/*
 * Touch/pointer interaction —
 * Cropper.js v2 relies on pointer events for drag, resize, and pinch-zoom.
 * touch-action:none prevents the browser from intercepting these gestures
 * for scrolling or native zoom.
 */
cropper-canvas,
cropper-handle,
cropper-selection,
cropper-shade {
  touch-action: none;
}

/* ── Circular crop overlay ── */

/* Selection clips to circle — export stays rectangular */
cropper-selection {
  border-radius: 50%;
  overflow: hidden;
}

/* Circular white outline */
cropper-selection[outlined] {
  outline: 2px solid white;
  outline-offset: -1px;
}

/* Move handle matches circular shape */
cropper-selection > cropper-handle[action="move"] {
  border-radius: 50%;
}

/* Dimmed overlay outside selection */
cropper-shade {
  background: rgba(0, 0, 0, 0.5);
}

/* Corner resize handles — visible grab points at bounding box corners */
cropper-selection cropper-handle[action$="-resize"] {
  width: 12px;
  height: 12px;
  background: white;
  border: 2px solid var(--color-interactive, #0284c7);
  border-radius: 50%;
}

/* Hide the original img once Cropper.js takes over */
.cropper-container img[data-cropper-image] {
  display: none;
}

/* ── Dimension badge ── */

.crop-dimension-badge {
  position: absolute;
  bottom: 0.5rem;
  left: 0.5rem;
  background: rgba(0, 0, 0, 0.6);
  color: white;
  font-size: 0.75rem;
  line-height: 1rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  padding: 0.25rem 0.5rem;
  border-radius: 0.25rem;
  pointer-events: none;
  z-index: 10;
}

/* ── Two-column layout for crop view ── */

.crop-view-grid {
  display: grid;
  grid-template-columns: 1fr;
  grid-template-rows: auto;
  gap: 1.5rem;
}

@media (min-width: 640px) {
  .crop-view-grid {
    grid-template-columns: 1fr 300px;
  }

  .crop-view-footer {
    grid-column: 1 / -1;
  }
}
```

Key changes:
- Background: `var(--neutral-900)` / `.dark var(--neutral-950)` instead of `var(--color-surface-sunken)`
- `cropper-selection` gets `border-radius: 50%` + `overflow: hidden` for circular mask
- Move handle gets matching `border-radius: 50%`
- Corner handle selector simplified to `[action$="-resize"]` (all resize handles, not just diagonal corners)
- Added `.crop-dimension-badge` for the dimension overlay
- Added `.crop-view-grid` with `@media (min-width: 640px)` two-column layout
- Added `.crop-view-footer` spans full width in grid

- [ ] **Step 2: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All tests pass (CSS changes don't affect request/model specs).

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/components/cropper.css
git commit -m "feat: dark viewport, circular overlay, and two-column grid CSS"
```

---

### Task 3: Modal Size Toggle for Crop View

**Files:**
- Modify: `app/javascript/controllers/identity_picker_controller.js`

The modal panel starts at `max-w-2xl` (672px) for the hub. When entering crop view, expand to `max-w-4xl` (896px) to fit the two-column layout. When returning to hub, shrink back.

- [ ] **Step 1: Add `_toggleModalSize` method and call it from mode switches**

In `app/javascript/controllers/identity_picker_controller.js`, add after the `_announce` method (end of the private section, before the closing `}`):

```javascript
  _toggleModalSize(mode) {
    const panel = this.element.closest("[data-modal-target='panel']")
    if (!panel) return

    if (mode === "crop") {
      panel.classList.remove("max-w-2xl")
      panel.classList.add("max-w-4xl")
    } else {
      panel.classList.remove("max-w-4xl")
      panel.classList.add("max-w-2xl")
    }
  }
```

- [ ] **Step 2: Call `_toggleModalSize` from `_switchMode`**

Update the existing `_switchMode` method to also toggle modal size:

Replace:
```javascript
  _switchMode(mode) {
    // mode-switch is on the same element as identity-picker (data-controller="identity-picker mode-switch")
    // so we can use this.element directly
    const ctrl = this.application.getControllerForElementAndIdentifier(this.element, "mode-switch")
    if (ctrl) ctrl.modeValue = mode
  }
```

With:
```javascript
  _switchMode(mode) {
    const ctrl = this.application.getControllerForElementAndIdentifier(this.element, "mode-switch")
    if (ctrl) ctrl.modeValue = mode
    this._toggleModalSize(mode)
  }
```

- [ ] **Step 3: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/identity_picker_controller.js
git commit -m "feat: toggle modal width between hub and crop views"
```

---

### Task 4: Zoom Percentage and Dimension Badge JS

**Files:**
- Modify: `app/javascript/controllers/image_cropper_controller.js`

Add two new targets (`zoomPercent` and `dimensionBadge`) and update them in the existing handler methods.

- [ ] **Step 1: Add new targets to the static declaration**

Replace:
```javascript
  static targets = ["container", "slider", "liveRegion"]
```

With:
```javascript
  static targets = ["container", "slider", "liveRegion", "zoomPercent", "dimensionBadge"]
```

- [ ] **Step 2: Add `_updateZoomPercent` method**

Add after the `_announceReset` method:

```javascript
  _updateZoomPercent(sliderValue) {
    if (!this.hasZoomPercentTarget) return
    const percent = Math.round(100 * Math.pow(3, sliderValue / 100))
    this.zoomPercentTarget.textContent = `${percent}%`
  }
```

- [ ] **Step 3: Call `_updateZoomPercent` from `handleSlider`**

In the `handleSlider` method, add the call after `this._announceZoom(value)`:

Replace:
```javascript
    this._announceZoom(value)
  }
```

With:
```javascript
    this._announceZoom(value)
    this._updateZoomPercent(value)
  }
```

- [ ] **Step 4: Reset zoom percent on cropper init**

In the `_initCropper` method, after the line `this.sliderTarget.value = 0`, add:

Replace:
```javascript
    if (this.hasSliderTarget) {
      this.sliderTarget.value = 0
    }
```

With:
```javascript
    if (this.hasSliderTarget) {
      this.sliderTarget.value = 0
    }
    this._updateZoomPercent(0)
```

- [ ] **Step 5: Add `_updateDimensionBadge` method**

Add after the `_updateZoomPercent` method:

```javascript
  _updateDimensionBadge(selection) {
    if (!this.hasDimensionBadgeTarget) return
    if (!selection) return

    const w = Math.round(selection.width)
    const h = Math.round(selection.height)
    this.dimensionBadgeTarget.textContent = `${w} × ${h}px`
  }
```

- [ ] **Step 6: Call `_updateDimensionBadge` from the bounds-enforcement handler**

In `_initCropper`, find the selection change event listener. Update it to also call `_updateDimensionBadge`:

Replace:
```javascript
    if (selection) {
      selection.addEventListener("change", (event) => {
        this._enforceBounds(event, selection)
      })
    }
```

With:
```javascript
    if (selection) {
      selection.addEventListener("change", (event) => {
        this._enforceBounds(event, selection)
        this._updateDimensionBadge(selection)
      })
    }
```

- [ ] **Step 7: Update dimension badge on reset**

In the `reset` method, add a dimension badge update after the crop changed dispatch:

Replace:
```javascript
    setTimeout(() => {
      this.dispatch("cropChanged")
    }, 50)
  }
```

With:
```javascript
    setTimeout(() => {
      this.dispatch("cropChanged")
      const sel = this._cropper?.getCropperSelection()
      if (sel) this._updateDimensionBadge(sel)
    }, 50)
  }
```

- [ ] **Step 8: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/image_cropper_controller.js
git commit -m "feat: zoom percentage display and dimension badge updates"
```

---

### Task 5: Rewrite Crop View ERB

**Files:**
- Modify: `app/views/shared/_identity_picker.html.erb` (lines 224-344 — the crop view section)

This is the largest task. Replace the entire crop view section with the new two-column layout, preview section, labeled zoom slider, hint text, info banner, and redesigned footer.

- [ ] **Step 1: Replace the crop view section**

In `app/views/shared/_identity_picker.html.erb`, replace lines 224-344 (from `<%# ═══════ CROP VIEW ═══════ %>` through the closing `</div>` of the crop section) with:

```erb
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

    <%# Two-column grid: crop viewport (left) + controls (right) %>
    <%# image-cropper controller scoped to the grid so targets in both columns are reachable %>
    <div class="crop-view-grid"
         data-controller="image-cropper"
         data-image-cropper-aspect-ratio-value="1"
         data-action="keydown->image-cropper#handleKeydown image-cropper:cropChanged->identity-picker#updateCropPreview"
         tabindex="0"
         aria-label="<%= t('identity_picker.crop_area_label') %>">

      <%# ── Left column: Crop viewport ── %>
      <div>
          <div class="cropper-container rounded-lg"
               data-image-cropper-target="container">
            <% if has_image %>
              <%= image_tag image_url, class: "max-w-full", alt: "" %>
            <% else %>
              <img src="" class="max-w-full" alt="">
            <% end %>
            <%# Dimension badge %>
            <div class="crop-dimension-badge"
                 data-image-cropper-target="dimensionBadge"
                 aria-hidden="true">
              &mdash;
            </div>
          </div>

          <%# ARIA live region %>
          <div data-image-cropper-target="liveRegion"
               aria-live="polite" class="sr-only"></div>
        </div>

        <%# Hint text below crop area %>
        <p class="text-sm text-text-muted text-center mt-2">
          <%= t("identity_picker.crop_hint") %>
        </p>
      </div>

      <%# ── Right column: Controls ── %>
      <div class="space-y-5">
        <%# Preview section %>
        <div>
          <span class="block text-xs uppercase tracking-wider text-text-muted mb-3">
            <%= t("identity_picker.preview") %>
          </span>
          <div class="flex items-center gap-3">
            <div class="w-16 h-16 rounded-full bg-surface-sunken overflow-hidden shrink-0"
                 aria-hidden="true">
              <img src="" alt=""
                   class="w-full h-full object-cover"
                   data-identity-picker-target="cropPreview">
            </div>
            <div>
              <span class="block text-sm font-medium text-text-heading">
                <%= t("identity_picker.preview_title") %>
              </span>
              <span class="block text-xs text-text-muted">
                <%= t("identity_picker.preview_description") %>
              </span>
            </div>
          </div>
        </div>

        <%# Zoom slider with label and percentage %>
        <div>
          <div class="flex items-center justify-between mb-2">
            <span class="inline-flex items-center gap-1.5 text-sm font-medium text-text-heading">
              <%= icon(:magnifying_glass_plus, size: :sm, class: "text-text-muted") %>
              <%= t("identity_picker.zoom_label") %>
            </span>
            <span class="text-sm font-medium text-interactive"
                  data-image-cropper-target="zoomPercent">
              100%
            </span>
          </div>
          <input type="range" min="0" max="100" value="0"
                 data-image-cropper-target="slider"
                 data-action="input->image-cropper#handleSlider"
                 aria-label="<%= t('identity_picker.zoom_aria_label') %>"
                 class="w-full h-2 rounded-full appearance-none cursor-pointer
                        bg-border
                        [&::-webkit-slider-thumb]:appearance-none
                        [&::-webkit-slider-thumb]:w-4 [&::-webkit-slider-thumb]:h-4
                        [&::-webkit-slider-thumb]:rounded-full
                        [&::-webkit-slider-thumb]:bg-white
                        [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-border-strong
                        [&::-webkit-slider-thumb]:shadow">
        </div>

        <%# Reset button %>
        <button type="button"
                data-action="click->identity-picker#resetCrop"
                class="w-full inline-flex items-center justify-center gap-2 px-4 py-2
                       text-sm font-medium text-text-body
                       border border-border rounded-lg
                       hover:bg-surface-sunken
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus
                       min-h-[44px]">
          <%= icon(:arrow_path, size: :sm) %>
          <%= t("identity_picker.reset_crop") %>
        </button>

        <%# Info banner %>
        <div class="flex items-start gap-2.5 p-3 rounded-lg bg-info-subtle text-info text-sm">
          <%= icon(:information_circle, size: :sm, class: "shrink-0 mt-0.5") %>
          <p><%= t("identity_picker.image_quality_tip") %></p>
        </div>
      </div>

      <%# ── Footer: spans both columns ── %>
      <div class="crop-view-footer flex flex-col gap-3 pt-4 border-t border-border">
        <%# Primary row: Cancel + Save crop %>
        <div class="flex items-center justify-end gap-3">
          <button type="button"
                  data-action="click->identity-picker#backToHub"
                  class="inline-flex items-center justify-center px-4 py-2
                         text-sm font-medium text-text-body
                         border border-border rounded-lg
                         hover:bg-surface-sunken
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus
                         min-h-[44px]">
            <%= t("identity_picker.cancel") %>
          </button>
          <button type="button"
                  data-action="click->identity-picker#saveCrop"
                  class="inline-flex items-center gap-2 px-5 py-2 rounded-lg
                         bg-interactive text-text-on-interactive font-medium text-sm
                         hover:bg-interactive-hover
                         focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
                         min-h-[44px]">
            <%= t("identity_picker.save_crop") %>
          </button>
        </div>
        <%# Secondary row: Upload new (left) + Remove photo (right) %>
        <div class="flex items-center justify-between">
          <button type="button"
                  data-action="click->identity-picker#openFilePicker"
                  class="inline-flex items-center gap-1.5 text-sm text-interactive
                         hover:text-interactive-hover
                         min-h-[44px] px-2 rounded
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus">
            <%= icon(:arrow_up_tray, size: :sm) %>
            <%= t("identity_picker.upload_new") %>
          </button>
          <button type="button"
                  data-action="click->identity-picker#removePhoto"
                  class="inline-flex items-center gap-1.5 text-sm text-danger
                         hover:text-danger/80
                         min-h-[44px] px-2 rounded
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus">
            <%= icon(:trash, size: :sm) %>
            <%= t("identity_picker.remove_photo") %>
          </button>
        </div>
      </div>

    </div>
  </div>
```

Key structural changes from the original:
- Wrapped crop area + controls in `div.crop-view-grid` (CSS grid, single → two columns at 640px)
- Left column: crop container + dimension badge (inside) + hint text (below)
- Right column: preview section (larger, richer), zoom slider (labeled with percentage), reset button (outlined), info banner
- Footer: spans both columns via `.crop-view-footer`, destructive actions spatially separated from constructive
- Removed the old vertically-stacked secondary actions section
- "Back to identity switcher" replaced with "Cancel" button in footer

**Note on Stimulus target scope:** The `data-controller="image-cropper"` is on the `crop-view-grid` wrapper (not on the inner crop-area div) so that targets in both the left column (`container`, `dimensionBadge`, `liveRegion`) and the right column (`slider`, `zoomPercent`) are all within scope.

- [ ] **Step 2: Verify the image-cropper controller scope**

Double-check that these targets are all inside the `data-controller="image-cropper"` element:
- `data-image-cropper-target="container"` — in the left column ✓
- `data-image-cropper-target="dimensionBadge"` — in the left column ✓
- `data-image-cropper-target="liveRegion"` — in the left column ✓
- `data-image-cropper-target="slider"` — in the right column ✓
- `data-image-cropper-target="zoomPercent"` — in the right column ✓

All must be descendants of the element with `data-controller="image-cropper"`.

- [ ] **Step 3: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All tests pass. If any test references `back_to_hub` locale key, update it to `cancel`.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_identity_picker.html.erb
git commit -m "feat: rewrite crop view with two-column layout and polished controls"
```

---

### Task 6: Run Full Suite and Visual Verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: 920 examples, 0 failures.

- [ ] **Step 2: Start the dev server**

```bash
mise exec -- bin/dev
```

- [ ] **Step 3: Visual verification checklist**

Open the profile edit page and click the avatar to open the identity picker modal. Verify:

1. **Hub view** — modal is `max-w-2xl` (672px), hub displays correctly (unchanged)
2. **Click photo → crop view** — modal expands to `max-w-4xl` (896px), smooth transition
3. **Dark viewport** — crop area has dark background in both light and dark mode
4. **Circular overlay** — white circle around crop selection, dimmed area outside
5. **Corner handles** — visible at bounding box corners, white with blue border
6. **Dimension badge** — lower-left of crop area, shows pixel dimensions, updates on resize
7. **Hint text** — "Drag to move · Pinch to zoom" below crop area
8. **Preview** — right column, "PREVIEW" label, 64px circle, "Circular Result" title, description text
9. **Zoom slider** — "Zoom Level" label, magnifying glass icon, percentage updates on drag
10. **Reset button** — outlined button below zoom slider, resets crop and zoom
11. **Info banner** — blue info box with tip text
12. **Footer** — "Cancel" and "Save crop" right-aligned, "Upload new" and "Remove photo" below
13. **Two-column layout** — side-by-side on desktop, stacks on mobile (resize browser to test)
14. **Back to hub** — both "Cancel" and back arrow return to hub, modal shrinks back to 672px
15. **Dark mode toggle** — switch theme, verify dark viewport stays dark, tokens adapt

- [ ] **Step 4: Commit all remaining changes if any fixups were needed**

```bash
git add -A
git commit -m "fix: crop editor visual polish adjustments"
```

(Skip this step if no fixups were needed.)
