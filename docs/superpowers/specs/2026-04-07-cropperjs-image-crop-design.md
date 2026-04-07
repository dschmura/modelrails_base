# Cropper.js Image Crop UX Upgrade

**Date:** 2026-04-07
**Status:** Draft
**Replaces:** 2026-04-06-image-crop-design.md (custom pan/zoom approach)

## Summary

Replace the custom pan/zoom image crop controller with Cropper.js v2 to provide a more intuitive, polished crop experience. The new interaction model uses a draggable, resizable selection box on top of the image (matching standard image editing UX) instead of panning the image behind a fixed viewport. Adds a real-time preview, rule-of-thirds guides, and support for cropping inside a modal (upload + crop as one seamless flow).

## Goals

- Smoother, more intuitive crop interaction with draggable selection handles
- Real-time circular (or shaped) preview that updates as the user adjusts the crop
- Support both standalone crop page and in-modal crop (upload → crop → done without leaving the page)
- Reusable across applications with configurable aspect ratio and shape
- WCAG 2.2 Level AAA compliance
- Dark/light mode support via design tokens
- Full keyboard, touch, and reduced-motion support
- Zero backend changes to crop coordinate storage

## Non-Goals

- Image rotation or flipping (Cropper.js supports it, but out of scope for this iteration)
- Client-side image processing/compression before upload
- Changing the upload flow itself (file selection, validation, drag-and-drop — all unchanged)

## Approach: Cropper.js v2 via Importmap

Cropper.js v2 is a mature, actively maintained library (~30KB gzipped, no dependencies) that ships ESM modules compatible with Rails importmaps. It provides draggable selection with corner/edge resize handles, pinch-to-zoom, scroll zoom, aspect ratio locking, and a live preview API.

A thin Stimulus controller (`image-cropper`) wraps Cropper.js and bridges it to the existing partial interface and form submission pattern.

## Architecture

### Component Structure

```
Stimulus: image-cropper controller (~80-100 lines)
  └── Wraps: Cropper.js v2 instance
  └── Targets: image, container, preview, x, y, w, h, slider (optional)
  └── Values: aspectRatio (Number), shape (String), viewMode (Number),
              previewSelector (String), existingCrop (Object)

Partial: shared/_image_crop.html.erb
  └── Same locals interface as today
  └── Cropper.js-compatible markup replaces custom viewport
  └── Preview element added below crop area

Modal integration:
  └── modal_controller.js dispatches "modal:opened" after animateIn completes
  └── image-cropper supports deferred init: if it connects while inside a closed
      dialog, it waits for "modal:opened" before initializing Cropper.js
  └── In Flow B (Turbo Stream swap), the modal is already open when crop markup
      arrives, so Cropper.js initializes immediately on connect — no deferral needed
  └── Deferred init covers the edge case where crop UI is pre-rendered inside a
      closed dialog that opens later
```

### Data Flow

**Crop coordinate format (unchanged):**
```
crop[x] — integer, top-left X in original image pixels
crop[y] — integer, top-left Y in original image pixels
crop[w] — integer, width in original image pixels
crop[h] — integer, height in original image pixels
```

Cropper.js `getData(true)` returns `{ x, y, width, height }` as rounded integers. The Stimulus controller maps `width` → `w` and `height` → `h` to match the existing form field names. The backend (`AvatarsController#save_crop`, `CropHelper#cropped_variant`) is completely untouched.

**Restoring previous crop:** When blob metadata already contains crop coordinates, they are passed as the `existingCrop` Stimulus value. After Cropper.js initializes, `cropper.setData({ x, y, width: w, height: h })` positions the selection where the user last saved.

## UX Flows

### Flow A: Standalone Crop Page

1. User uploads image → redirected to `/account/avatar/crop`
2. Page loads, image visible, Cropper.js initializes immediately
3. Draggable selection box with corner/edge handles, aspect ratio locked
4. Checkered transparency background outside image bounds
5. Rule-of-thirds dashed guide lines inside selection
6. Live shaped preview below crop area (updates in real-time)
7. Instruction text: "Drag to reposition · Resize corners to zoom · Image will be cropped to a circle"
8. Zoom slider included by default (primary purpose: keyboard accessibility and precision control; secondary to scroll/pinch zoom for most users)
9. Primary actions: Save / Skip cropping
10. Secondary actions: Upload different (opens modal), Use initials, Remove photo

### Flow B: Upload + Crop in Modal

1. User clicks avatar/upload button → upload modal opens
2. User selects file → auto-submit uploads to server, spinner shows
3. Server responds with Turbo Stream replacing modal body content with crop UI
4. Cropper.js initializes (modal is already visible — no deferred init needed here)
5. Modal uses `size: :lg` minimum to give adequate crop area
6. User adjusts crop → clicks Save
7. Server responds with Turbo Stream: closes modal, updates avatar on underlying page
8. No page navigation occurred — user stays on the profile (or wherever they were)

### Flow C: Standalone Crop Page with Upload Different

Same as today. Crop page has "Upload different" secondary action that opens the upload modal. After upload completes, controller redirects back to crop page with the new image (standard HTML redirect).

### Modal Content Transition Detail

The upload-to-crop transition inside the modal uses Turbo Streams:

- `AvatarsController#update` gains a `respond_to` block:
  - `format.html` — redirects to crop page (standalone flow, unchanged)
  - `format.turbo_stream` — renders `update.turbo_stream.erb` which replaces modal body with crop UI
- `AvatarsController#save_crop` gains a similar block:
  - `format.html` — redirects to profile (standalone flow, unchanged)
  - `format.turbo_stream` — renders `save_crop.turbo_stream.erb` which closes modal and updates avatar

The modal never closes and reopens during the transition. Content swaps in place.

## Cropper.js Configuration

```javascript
new Cropper(imageElement, {
  aspectRatio: this.aspectRatioValue,     // 1.0 for avatars, configurable
  viewMode: 1,                            // restrict crop to canvas bounds
  dragMode: "move",                       // drag image to reposition
  autoCropArea: 1,                        // default selection covers full image
  responsive: true,                       // re-render on window resize
  restore: false,                         // don't restore after resize
  guides: true,                           // rule-of-thirds dashed lines
  center: true,                           // center crosshair indicator
  highlight: false,                       // no white highlight on crop box
  background: true,                       // checkered transparency background
  preview: this.previewSelectorValue,     // CSS selector for live preview element
  crop: (event) => { /* update hidden fields in real-time */ }
})
```

## Accessibility (WCAG 2.2 Level AAA)

### Keyboard Navigation

- `Arrow keys` — move crop selection by 1px (10px with Shift)
- `+` / `-` — zoom in/out incrementally
- `Tab` — cycles focus: crop area → zoom slider → save → skip → secondary actions
- `Escape` — navigate back (standalone) or close modal
- All keyboard shortcuts added by the Stimulus controller, not Cropper.js defaults

### ARIA

- Crop container: `tabindex="0"`, `role="application"`, `aria-roledescription="image cropper"`
- Dynamic `aria-label` on crop area: "Crop selection: {w}x{h} pixels at position {x}, {y}"
- `aria-live="polite"` region announces crop changes for screen reader users
- Zoom slider: `aria-label`, `aria-valuemin`, `aria-valuemax`, `aria-valuenow`
- All buttons meet accessible name requirements

### Touch

- All interactive targets meet 44x44px minimum touch target (WCAG 2.5.8)
- Corner/edge handles enlarged to 14px on mobile (vs 10px desktop)
- Cropper.js handles pinch-to-zoom natively
- Single-finger drag to move selection or image

### Reduced Motion

- `prefers-reduced-motion: reduce`: no transition effects on preview updates, handle hovers, or modal animations (modal controller already handles this)

## Viewport Responsiveness

- **Mobile (< 640px):** Crop area fills full width, minimal padding. Preview at 48px. Buttons stack full-width. Touch handles enlarged. Modal goes near-full-screen.
- **Tablet (640-1024px):** Comfortable side padding. Preview at 64px.
- **Desktop (1024+):** Current `max-w-2xl` card layout. Preview at 80px.
- **Crop viewport:** `max-height: 55vh` prevents buttons from being pushed off-screen.
- **Modal crop:** Modal uses `size: :lg` minimum. On mobile, modal expands to `max-w-full`.
- Cropper.js `responsive: true` handles window resize and orientation changes.

## Dark/Light Mode

- Crop overlay (dimmed area outside selection) and checkered background are inherently mode-agnostic — they render on the always-dark crop canvas.
- Selection handles use `bg-interactive` design token (adapts to theme) instead of hardcoded blue.
- Guide lines use `rgba(255,255,255,0.4)` — works on the dark crop overlay in both modes.
- Instruction text, preview label, and buttons use existing token classes (`text-text-muted`, `text-text-heading`, etc.).
- Card chrome (header, borders, background) uses `bg-surface-overlay`, `border-border` — already themed.
- Cropper.js CSS is customized via CSS custom properties to match the design token system.

## File Changes

### Create

| File | Purpose |
|------|---------|
| `app/javascript/controllers/image_cropper_controller.js` | Stimulus controller wrapping Cropper.js v2 |
| `app/assets/stylesheets/vendor/cropper.css` | Vendored Cropper.js CSS with design token overrides |
| `app/views/account/avatars/update.turbo_stream.erb` | Turbo Stream: replace modal content with crop UI |
| `app/views/account/avatars/save_crop.turbo_stream.erb` | Turbo Stream: close modal, update avatar on page |

### Modify

| File | Change |
|------|--------|
| `config/importmap.rb` | Add `pin "cropperjs"` |
| `app/views/shared/_image_crop.html.erb` | Replace custom viewport with Cropper.js markup, add preview element, update controller reference |
| `app/javascript/controllers/modal_controller.js` | Dispatch `modal:opened` custom event after `animateIn` completes |
| `app/controllers/account/avatars_controller.rb` | Add `respond_to` blocks for Turbo Stream in `update` and `save_crop` |
| `app/views/account/avatars/crop.html.erb` | Pass existing crop data and preview selector to partial |
| `app/views/account/profiles/edit.html.erb` | Add Turbo target ID on avatar element for Turbo Stream replacement |
| Locale files (`en.yml` etc.) | Update crop instruction text keys |

### Delete

| File | Reason |
|------|--------|
| `app/javascript/controllers/image_crop_controller.js` | Replaced by `image_cropper_controller.js` |

## Testing

### Controller Specs

- `AvatarsController#update` responds with Turbo Stream when format is `turbo_stream`
- `AvatarsController#update` still redirects to crop page for HTML format
- `AvatarsController#save_crop` responds with Turbo Stream when format is `turbo_stream`
- `AvatarsController#save_crop` still redirects for HTML format
- Crop coordinate saving behavior unchanged (existing specs pass)

### System Specs

- **Standalone crop page:** upload → land on crop page → verify crop container visible → save → verify coordinates in blob metadata
- **Modal flow:** profile page → click upload → select file → verify modal transitions to crop UI → save → verify modal closes and avatar updates on page
- **Keyboard:** tab into crop area → arrow keys move selection → +/- zooms → tab to save button → enter submits
- **Mobile viewport:** verify crop area fills width, buttons stack, touch interactions work
- **Re-crop:** upload → crop → save → return to crop page → verify selection starts at previous position

### Accessibility Audit

- axe-core scan on standalone crop page
- axe-core scan on modal crop state
- Verify all interactive elements have accessible names
- Verify focus management through modal upload → crop → save → close flow
- Verify `aria-live` announcements fire on crop changes
- Verify 7:1 contrast on all text elements
