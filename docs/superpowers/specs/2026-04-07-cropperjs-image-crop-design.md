# Cropper.js Image Crop UX Upgrade

**Date:** 2026-04-07
**Status:** Draft
**Replaces:** 2026-04-06-image-crop-design.md (custom pan/zoom approach)

## Summary

Replace the custom pan/zoom image crop controller with Cropper.js v1 to provide a more intuitive, polished crop experience. The new interaction model uses a draggable, resizable selection box on top of the image (matching standard image editing UX) instead of panning the image behind a fixed viewport. Adds a real-time preview, rule-of-thirds guides, and support for cropping inside a modal (upload + crop as one seamless flow).

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

## Edge Cases

- **Large images (10+ MP):** Phone cameras routinely produce 12-20MP images. Cropper.js renders via canvas internally and handles downscaling, but very large images can cause jank on low-end mobile devices. The Stimulus controller should log a warning if `naturalWidth` or `naturalHeight` exceeds 4096px. No blocking behavior — just awareness for future optimization (e.g., client-side downscale before crop) if it becomes a real problem.
- **EXIF orientation:** Photos from mobile devices often include EXIF rotation metadata (portrait stored as landscape + rotation flag). Cropper.js v2 reads EXIF orientation automatically and corrects the display. This must be explicitly tested — upload a portrait phone photo and verify the crop UI shows it upright.
- **Cropper.js CSS vs Tailwind 4 preflight:** Tailwind 4's CSS reset (`img { display: block; max-width: 100% }`, universal box-sizing) can interfere with Cropper.js's internal layout. The vendored CSS must be tested against Tailwind's preflight, and may need scoped specificity overrides (e.g., `.cropper-container img { max-width: none }`).
- **Turbo cache and Cropper.js state:** When Turbo caches a page with an active Cropper.js instance and restores it on back-navigation, the Stimulus controller's `disconnect()` → `connect()` cycle must cleanly destroy and reinitialize. Verify no ghost canvases or duplicate event listeners persist.
- **ActiveStorage URL expiry:** ActiveStorage redirect-mode URLs are short-lived. When Turbo Stream swaps crop UI into a modal, the image URL is freshly rendered server-side, so this is not an issue. However, if the user leaves the crop page idle for an extended period and then saves, the image display may break on the next page load — the crop coordinates themselves are still valid since they reference the blob, not the URL.

## Approach: Cropper.js v1 (1.6.x) via Importmap

Cropper.js v1 is a mature, widely-used library (~30KB gzipped, no dependencies) with a clean class-based API. It provides draggable selection with corner/edge resize handles, pinch-to-zoom, scroll zoom, aspect ratio locking, and a live preview API.

**Why v1, not v2:** Cropper.js v2 is a complete architectural rewrite using Web Components and Shadow DOM. Shadow DOM encapsulation prevents Tailwind classes from penetrating into cropper elements, making design token integration impractical. The v2 API (`<cropper-canvas>`, `<cropper-image>`, `<cropper-selection>` custom elements) adds complexity without benefit for our use case. v1's class-based API (`new Cropper(img, options)` → `getData()` → `destroy()`) is simpler to wrap in Stimulus and easier to style with our design tokens. v1 continues to receive bug fixes.

A thin Stimulus controller (`image-cropper`) wraps Cropper.js v1 and bridges it to the existing partial interface and form submission pattern.

## Architecture

### Component Structure

```
Stimulus: image-cropper controller (~80-100 lines)
  └── Wraps: Cropper.js v1 instance
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

Cropper.js v1 `getData(true)` returns `{ x, y, width, height, rotate, scaleX, scaleY }` as rounded integers. The Stimulus controller maps `width` → `w` and `height` → `h` to match the existing form field names. The backend (`AvatarsController#save_crop`, `CropHelper#cropped_variant`) is completely untouched.

**Restoring previous crop:** When blob metadata already contains crop coordinates, they are passed as the `existingCrop` Stimulus value. After Cropper.js initializes, `cropper.setData({ x, y, width: w, height: h })` positions the selection where the user last saved. The v1 `setData()` method accepts this format directly.

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
| `app/javascript/controllers/image_cropper_controller.js` | Stimulus controller wrapping Cropper.js v1 |
| `app/assets/stylesheets/vendor/cropper.css` | Vendored Cropper.js v1 CSS with design token overrides |
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
