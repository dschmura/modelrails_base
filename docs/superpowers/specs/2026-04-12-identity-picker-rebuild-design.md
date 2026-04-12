# Identity Picker Rebuild — Design Spec

**Date:** 2026-04-12
**Status:** Draft
**Replaces:** `2026-04-07-identity-picker-design.md` (archived)
**Context:** Rebuild after 58-commit v1 attempt (stashed as `identity-picker-v1-attempt-58-commits`). All Cropper.js v2 API knowledge and UX decisions carried forward from that attempt.

## Overview

A shared identity picker modal for both User avatars and Workspace logos. Replaces the current Cropper.js v1 crop UI, upload modal, and scattered action buttons with a unified hub/switcher pattern.

The rebuild has two phases:

1. **Removal** — full tear-down of the v1 crop/upload UI
2. **Implementation** — identity picker with Cropper.js v2, OKLCH color picker, dual attachment

## Phase 1: Removal

Full tear-down of all avatar/crop/upload UI for both users and workspaces. Goal: clean starting point with working model layer but no crop/upload UI.

### Files to Delete

**Stimulus controllers:**

- `app/javascript/controllers/image_cropper_controller.js`
- `app/javascript/controllers/image_upload_controller.js`
- `app/javascript/controllers/modal_closer_controller.js` (will be recreated in Phase 2 with fix for focus restoration)

**Views:**

- `app/views/shared/_image_crop.html.erb`
- `app/views/shared/_image_upload_modal.html.erb`
- `app/views/account/avatars/crop.html.erb`
- `app/views/account/avatars/update.turbo_stream.erb`
- `app/views/account/avatars/save_crop.turbo_stream.erb`
- `app/views/workspaces/brandings/crop.html.erb`
- `app/views/workspaces/brandings/update.turbo_stream.erb`
- `app/views/workspaces/brandings/save_crop.turbo_stream.erb`

**Vendor assets:**

- `app/assets/stylesheets/vendor/cropper.css`

**Helpers:**

- `app/helpers/crop_helper.rb`

**Specs:**

- `spec/system/image_crop_spec.rb`
- `spec/system/image_upload_modal_spec.rb`
- `spec/system/avatar_spec.rb`
- `spec/helpers/crop_helper_spec.rb`

### Files to Modify

**`config/importmap.rb`** — Remove `cropperjs` pin (v1.6.2).

**`app/assets/stylesheets/application.css`** — Remove `vendor/cropper.css` import if present.

**`config/routes.rb`** — Remove `crop` and `save_crop` member routes from both `avatar` and `brandings` resources.

**`app/controllers/account/avatars_controller.rb`** — Remove `crop` and `save_crop` actions. Keep `update` and `destroy` as stubs (will be rebuilt).

**`app/controllers/workspaces/brandings_controller.rb`** — Remove `crop` and `save_crop` actions. Keep `edit` and `update`.

**`app/helpers/avatar_helper.rb`** — Remove `cropped_variant` call in `render_upload_avatar`. Replace with direct `image_tag user.avatar.variant(resize_to_fill: [config[:px], config[:px]])`. The `cropped_variant` helper is deleted with `crop_helper.rb`.

**`spec/requests/account/avatars_spec.rb`** — Remove crop-specific request specs (test `crop` and `save_crop` actions). Keep `update` and `destroy` specs but update to match stubbed controller.

**`spec/requests/workspaces/brandings_spec.rb`** — Remove crop-specific request specs. Keep remaining specs.

**`spec/helpers/avatar_helper_spec.rb`** — Update to not depend on `cropped_variant`.

### Files to Keep (unchanged)

- `app/javascript/controllers/modal_controller.js` — general-purpose modal
- `app/javascript/controllers/mode_switch_controller.js` — general-purpose view toggler
- `app/models/user.rb` — `has_one_attached :avatar`, `avatar_source` validation, etc.
- `app/models/workspace.rb` — `has_one_attached :logo`

### Documentation to Archive

Move to `docs/superpowers/archive/`:

- `docs/superpowers/specs/2026-04-05-avatar-system-design.md`
- `docs/superpowers/specs/2026-04-05-image-upload-modal-design.md`
- `docs/superpowers/specs/2026-04-06-image-crop-design.md`
- `docs/superpowers/specs/2026-04-07-avatar-crop-ux-polish-design.md`
- `docs/superpowers/specs/2026-04-07-cropperjs-image-crop-design.md`
- `docs/superpowers/specs/2026-04-07-identity-picker-design.md`
- `docs/superpowers/plans/2026-04-05-avatar-system.md`
- `docs/superpowers/plans/2026-04-05-image-upload-modal.md`
- `docs/superpowers/plans/2026-04-06-image-crop.md`
- `docs/superpowers/plans/2026-04-07-avatar-crop-ux-polish.md`
- `docs/superpowers/plans/2026-04-07-cropperjs-image-crop.md`
- `docs/superpowers/plans/2026-04-07-identity-picker.md`

### Post-Removal Verification

After removal, the full test suite must pass with 0 failures. Avatar rendering still works (upload source falls back to `variant(resize_to_fill:)` without crop, initials and gravatar unchanged). No crop or upload modal UI is accessible.

---

## Phase 2: Identity Picker Implementation

### Architecture

#### Dual Attachment

Each model (User, Workspace) has two image attachments:

- `avatar` / `logo` — the cropped display image uploaded from client-side export
- `avatar_original` / `logo_original` — the full original file, preserved for re-cropping

Crop coordinates stored in `avatar_original.blob.metadata["crop"]` as `{x, y, w, h}` so the crop selection can be restored when re-editing.

Both attachments purged together on delete. When switching to initials, the attachments stay attached but unused (not purged) — allows switching back without re-uploading.

#### Client-Side Crop Export

Cropper.js v2 `selection.$toCanvas()` exports the cropped region as a canvas. The canvas is converted to a blob and uploaded as the `avatar` attachment. No server-side image processing for cropping.

Server-side `variant(resize_to_fill:)` is only used for display sizing (rendering the already-cropped image at the correct pixel dimensions for each avatar size).

#### User `primary_color`

Migration adds `primary_color` column to `users` table:

- Type: `integer`, default `210` (blue hue, matching current `bg-interactive` token)
- Stores the OKLCH hue value (0-360) directly — no hex conversion
- Validation: `inclusion: { in: 0..360 }`
- Used by `render_initials_avatar` to set background color via inline `oklch(0.45 0.2 #{hue})` style
- Workspace gets the same column if not already present

#### Available Avatar Sources

- User: `upload`, `gravatar`, `initials` — always all three available regardless of whether an avatar is currently attached
- Workspace: `upload`, `initials` — no gravatar

The current `available_avatar_sources` method conditionally hides "upload" when no avatar is attached. This must change: "upload" is always available (selecting it with no image triggers the file picker).

### Modal UI

Two-view hub/switcher modal. No separate upload view — file picker opens natively.

#### Hub View (main state)

- Large preview (w-32 h-32): photo, gravatar, or initials circle reflecting current selection
- "Last updated" timestamp below preview
- Source cards: radio-style cards for each available source (Photo, Gravatar, Initials)
  - Each card is a `<label>` wrapping a visually hidden `<input type="radio">`
  - Selecting a source updates the preview in real-time
- When **Photo selected + has image**: preview is clickable with hover overlay (pencil icon) — opens crop view
- When **Initials selected**: OKLCH hue slider appears inline below source cards
- "Save & apply" button at bottom, full-width primary — submits source + color via standard form
- No action links on hub — clean switcher only

#### Crop View

Reached by clicking photo preview or Photo card when an image exists.

- Cropper.js v2 crop area in a container with explicit `height: 50vh`
- Zoom slider below crop area
- Live circular preview (48px) next to "Save crop" primary button
- Secondary action links: "Upload new" | "Back to hub" | "Remove photo"
- "Save crop" exports cropped blob, uploads both blobs via fetch, returns to hub with updated preview

#### File Picker (no separate view)

- When Photo selected with no image, or "Upload new" from crop: **native file picker opens immediately**
- Hidden `<input type="file">` triggered programmatically
- After file selection → transitions directly to crop view with selected file
- If user cancels file picker → stays on current view
- Client-side validation: accepted types (`image/png`, `image/jpeg`, `image/gif`, `image/webp`), max 5MB

#### Modal Flow

```
Modal opens → Hub (preview + source cards + Save)
  Photo + has image → click preview → Crop view
    Save crop → Hub | Upload new → file picker → Crop | Remove → Hub | Back → Hub
  Photo + no image → click Photo card → file picker → Crop → Hub
  Initials → color picker inline → Save
  Gravatar → just select + Save
```

### Cropper.js v2 Integration

#### ESM Import

Pin in importmap: `https://cdn.jsdelivr.net/npm/cropperjs@2/dist/cropper.esm.js`

This is the ESM build — NOT `cropper.js` (UMD). Works with Rails importmaps.

#### Custom Template

The default Cropper.js v2 template has `action="select"` on the canvas handle, which creates new selections on drag. Must override:

```html
<cropper-canvas background>
  <cropper-image
    initial-center-size="contain"
    rotatable scalable skewable translatable
  ></cropper-image>
  <cropper-shade hidden></cropper-shade>
  <cropper-handle action="move" plain></cropper-handle>
  <cropper-selection movable resizable outlined>
    <cropper-handle action="move"
      style="width:100%;height:100%;background:transparent">
    </cropper-handle>
    <!-- corner + edge resize handles -->
  </cropper-selection>
</cropper-canvas>
```

Key attributes:
- `action="move"` on canvas handle — dragging pans the image
- `initial-center-size="contain"` on image — centers and fits on load
- `movable resizable` on selection — user can drag and resize the crop area
- Full-area transparent move handle inside selection — ensures entire selection area is draggable

#### Container Sizing

The crop container needs an explicit `height: 50vh`. v2 Web Components use `height: 100%` which collapses to 0 if the parent has no explicit height. Do NOT use `max-height`.

#### Hidden Element Initialization

v2 cannot initialize on hidden elements (produces 0x0 selection). When the crop view is hidden (via mode_switch), initialization must be deferred:

1. MutationObserver watches the crop view's parent for `hidden` attribute removal
2. When `hidden` is removed, wait for browser reflow via double `requestAnimationFrame`
3. Then initialize Cropper.js

No setTimeout hacks — they cause visible jumps.

#### Selection Bounds Enforcement

v2 has no `viewMode` equivalent. Enforce bounds manually:

- Listen for `change` event on `cropper-selection`
- If the new selection position/size exceeds image bounds, call `event.preventDefault()`

#### Zoom

- Exponential curve: `Math.pow(3, sliderValue / 100)` for perceptually smooth zoom
- Capture `_baseTransform` on ready via `image.$getTransform()`
- `_baseTransform[0]` is the initial auto-fit scaleX — this is the zoom baseline
- Compute target scale: `baseScale * Math.pow(3, sliderValue / 100)`
- Apply via `image.$setTransform(...)` from base transform to preserve center position
- Slider must manually dispatch `actionend` event on `cropper-canvas` since `$setTransform` doesn't fire it

#### Export

- `selection.$toCanvas()` for cropped region — NOT `canvas.$toCanvas()` (exports full canvas)
- No fixed dimensions — export at natural resolution to preserve source pixels
- `beforeDraw` callback fills white background before drawing (prevents transparent PNG artifacts)
- Returns a Promise (async) — `await selection.$toCanvas()`
- Convert canvas to blob: `canvas.toBlob(callback, 'image/png')`

#### Live Preview

- Lives on `identity_picker_controller` (preview element is outside the crop partial's DOM scope)
- `selection.$toCanvas({width: size, height: size})` for rendered preview at display size
- Listen for `actionend` on `cropper-canvas` to trigger preview update
- Zoom slider must manually dispatch `actionend` since `$setTransform` doesn't fire it

### OKLCH Color Picker

Inline hue slider on the hub view, shown only when Initials source is selected and model has `primary_color` column.

**Slider:**

- Range input: `min="0"` `max="360"` `step="1"`
- Gradient preview bar showing the full OKLCH hue range at fixed lightness (0.45) and chroma (0.2)
- Fixed lightness 0.45 ensures AAA contrast (7:1 ratio) with white text across all hues
- Live preview updates the initials circle background in real-time via inline style

**Color storage:**

- Store the OKLCH hue value directly as an integer (0-360) in `primary_color` column, not hex
- Column type: `integer`, default `210` (blue, matching current `#0284c7`)
- Validation: `0..360` range
- Background color rendered as: `oklch(0.45 0.2 ${hue})`
- Slider value maps directly to stored value — no hex conversion needed

**Accessibility:**

- `role="slider"` with `aria-valuemin="0"`, `aria-valuemax="360"`, `aria-valuenow`
- `aria-valuetext` maps hue ranges to color names:
  - 0-30: Red, 30-60: Orange, 60-90: Yellow, 90-150: Green, 150-210: Cyan, 210-270: Blue, 270-330: Purple, 330-360: Pink
- `aria-live="polite"` region announces color changes
- Keyboard: Left/Right arrows adjust hue, Shift modifier for 10-step increments

**Rendering in `render_initials_avatar`:**

- When user has a custom `primary_color` (non-default): inline `style="background-color: oklch(0.45 0.2 #{primary_color})"` on the initials span
- When using default (210): `bg-interactive` class (design token, preserves AAA contrast)

### Stimulus Controllers

Three controllers with clear single responsibilities:

#### `identity_picker_controller.js` — Hub orchestration

Manages the modal's hub logic, source selection, color picker, and coordinates between views.

**Responsibilities:**
- Source card radio selection → syncs hidden `avatar_source` form field
- Updates large preview on source change (shows photo, gravatar, or initials)
- Triggers native file picker when Photo selected with no image or "Upload new"
- Handles file selection → creates object URL for crop view, transitions to crop mode
- Receives `crop:save` custom event from image_cropper → uploads both blobs (cropped + original) via fetch with FormData
- Color picker slider → live preview update + syncs hidden `primary_color` field
- Manages crop view ↔ hub view transitions via mode_switch

**Targets:** preview, sourceField, colorField, colorSlider, colorPreview, fileInput, initialsPreview

**Values:** formUrl (String), hasImage (Boolean)

#### `image_cropper_controller.js` — Cropper.js v2 wrapper

Pure crop concern. Knows nothing about identity picker, sources, or forms.

**Responsibilities:**
- Initializes Cropper.js v2 with custom template
- MutationObserver for hidden element detection + double rAF init
- Zoom slider with exponential curve
- Selection bounds enforcement via `change` event
- Keyboard shortcuts (arrow keys for selection move, +/- for zoom, Shift = 10x)
- Exports cropped blob via `selection.$toCanvas()` → dispatches `crop:save` custom event with `{blob, coordinates}` detail
- ARIA live region for accessibility announcements

**Targets:** container, slider, liveRegion

**Values:** aspectRatio (Number, default 1)

**Custom event dispatched:** `crop:save` with `detail: {blob, coordinates: {x, y, w, h}}`

#### `mode_switch_controller.js` — View toggling (existing, unchanged)

General-purpose controller already in the codebase. Toggles `hidden` attribute on sections by mode name.

### Form Submission & Server Integration

#### Single `update` Action

Both "Save & apply" (hub) and "Save crop" (crop view) submit through the same `update` controller action. No separate `save_crop` route.

**Parameters accepted:**

| Parameter | Type | When sent |
|-----------|------|-----------|
| `avatar` | file | New upload + crop, re-crop |
| `avatar_original` | file | New upload only |
| `avatar_source` | string | Always (source selection) |
| `primary_color` | integer | Initials source with color change (hue 0-360) |
| `crop_coordinates` | JSON string | With any crop operation |

**Submission flows:**

| User action | Params sent |
|-------------|-------------|
| Switch to initials + change color | `avatar_source=initials`, `primary_color=270` |
| Switch to gravatar | `avatar_source=gravatar` |
| New upload + crop | `avatar` (cropped blob), `avatar_original` (full file), `avatar_source=upload`, `crop_coordinates` |
| Re-crop existing image | `avatar` (cropped blob), `crop_coordinates` |
| Remove photo | `avatar_source=initials` (attachments stay attached but unused) |

**Crop save flow (fetch):**
1. `identity_picker_controller` builds FormData with cropped blob, original file (if new), coordinates
2. Sends PATCH to `update` action with `Accept: text/vnd.turbo-stream.html`
3. Server saves attachments, stores crop coords in `avatar_original.blob.metadata["crop"]`
4. Returns Turbo Stream: replaces all avatar instances on page, closes modal, shows toast

**Hub save flow (standard form):**
1. "Save & apply" submits the form normally (standard Rails form submission)
2. Hidden fields carry `avatar_source` and `primary_color`
3. Server updates the user/workspace record
4. Returns Turbo Stream: replaces all avatar instances on page, closes modal, shows toast

#### Response Format

**Turbo Stream response:**
- Replace all avatar rendering targets on the page (profile, nav header, any other instances)
- Close modal via `modal_closer_controller` appended to stream
- Prepend success toast

**HTML fallback:**
- Redirect to profile/settings page

#### Workspace Brandings

Identical pattern to avatars. Same parameters, same response format. The identity picker partial is shared, parameterized by:
- `model` — the User or Workspace instance
- `form_url` — the controller action URL
- `available_sources` — array of source strings
- `has_color_picker` — boolean (true for User, true for Workspace if it has `primary_color`)

### Accessibility (WCAG 2.2 AAA)

#### Modal

- Native `<dialog>` with proper focus trap
- Focus moves to first interactive element on open
- Focus restored to trigger element on close
- `modal_closer_controller` must dispatch through modal controller's `close` method (v1 bug: bypassed focus restoration)
- ESC closes modal at all times
- Modal title announces context: "Edit profile picture" / "Edit workspace logo"

#### Source Cards

- `role="radiogroup"` with `aria-label="Avatar source"` on container
- Each card: `<label>` wrapping visually hidden `<input type="radio">`
- Arrow keys navigate between cards (native radio group keyboard behavior)
- Selected state announced via radio semantics

#### Crop View

- Zoom slider: `role="slider"`, `aria-valuemin`, `aria-valuemax`, `aria-valuenow`, `aria-label="Zoom level"`
- Crop area: `aria-label="Crop area — use arrow keys to move selection, plus and minus to zoom"`
- Keyboard shortcuts announced via ARIA live region (`aria-live="polite"`)
- Live preview: `aria-hidden="true"` (decorative — crop area is the functional element)

#### Color Picker

- As specified in the OKLCH Color Picker section above

#### Contrast

- All text meets 7:1 ratio (AAA) against backgrounds
- Initials circles: OKLCH lightness 0.45 ensures 7:1 with white text across all hues
- Interactive elements meet 3:1 non-text contrast against adjacent colors

#### Screen Reader Flow

- Modal title announces context on open
- Source change announced via radio group semantics
- Color change announced via live region with color name
- Crop save confirmed via toast + live region
- Zoom level announced via slider semantics

### Testing Strategy

TDD throughout — specs written before implementation, testing behaviors and outcomes.

#### Request Specs

- `avatars#update` — each submission flow: source switch to initials, source switch to gravatar, new upload with crop, re-crop existing, remove photo
- Verify both attachments saved correctly, crop metadata stored, Turbo Stream replaces correct targets
- `brandings#update` — mirrors avatar cases
- Pundit authorization enforced on all actions
- Invalid params rejected (bad color format, oversized file, wrong content type)

#### Helper Specs

- `avatar_for` renders correct markup for each source at each size
- `avatar_for` with custom `primary_color` renders inline OKLCH style
- `avatar_for` without custom color uses `bg-interactive` class
- `workspace_icon_for` — same coverage pattern

#### System Specs

- Open modal → select initials → adjust color slider → save → verify page avatars updated with new color
- Open modal → select photo (no image) → file picker → crop → save → verify both attachments created + page updated
- Open modal → click existing photo preview → re-crop → save → verify avatar updated
- Open modal → crop view → "Upload new" → file picker → crop → save → verify original replaced
- Open modal → crop view → "Remove photo" → verify fallback to initials, attachments preserved
- Keyboard navigation through source cards (arrow keys), crop controls, color slider
- Screen reader announcements via ARIA live regions

#### What Not to Test

- Cropper.js v2 internals (third-party library)
- Canvas rendering fidelity
- Implementation details of Stimulus controller wiring

Use real file attachments via fixtures. No Active Storage mocks.
