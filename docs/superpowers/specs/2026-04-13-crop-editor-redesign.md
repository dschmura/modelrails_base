# Crop Editor View — Redesign Spec

**Scope:** Visual and layout redesign of the crop editor view within the identity picker modal. No changes to the hub/identity switcher view, controller logic, or backend.

**Goal:** Bring the crop editor to a polished, professional standard inspired by the reference screenshots. Dark immersive viewport, circular crop overlay, responsive two-column layout, and clear visual hierarchy for controls.

**Branch:** `feature/identity-picker` (worktree at `.worktrees/identity-picker`)

**Files affected:**
- `app/views/shared/_identity_picker.html.erb` (crop view section only, lines 225-343)
- `app/assets/stylesheets/components/cropper.css`
- `app/javascript/controllers/image_cropper_controller.js` (dimension badge updates)
- `app/javascript/controllers/identity_picker_controller.js` (minor: zoom percentage display)
- `config/locales/en/account.en.yml` (new locale keys)

---

## 1. Dark Immersive Viewport

The crop area uses an always-dark background in both light and dark modes, creating an immersive, focused space that makes the photo pop.

**Cropper container background:**
- Light mode: `--neutral-900` (slate-900)
- Dark mode: `--neutral-950` (slate-950)

Implementation: Add a dedicated CSS custom property `--crop-viewport-bg` set per theme, or use Tailwind's `bg-neutral-900 dark:bg-neutral-950` directly on the container element. The `cropper.css` file should use this instead of `var(--color-surface-sunken)`.

**Cropper canvas background:** Same dark value — the `cropper-canvas` Web Component background must match so there's no flash of different color during initialization.

**Selection outline:** Keep `2px solid white` — works well against the dark viewport in both modes.

**Corner resize handles:**
- Background: `white` (correct against dark viewport)
- Border: `var(--color-interactive)` (sky-700 light / sky-400 dark — both visible against white handle background)

**Shade overlay:** Keep `rgba(0, 0, 0, 0.5)` — the semi-transparent black dimming outside the selection works against the dark viewport in both modes.

---

## 2. Circular Crop Overlay

The crop selection displays a circular mask to visually represent the round avatar output. The actual crop remains square (Cropper.js exports a rectangular canvas) — the circle is a cosmetic overlay.

**Approach:** Apply `border-radius: 50%` and `overflow: hidden` to `cropper-selection` via CSS. This clips the visible selection area to a circle while the underlying Cropper.js geometry stays rectangular.

**Selection outline:** The outline follows the border-radius, creating a white circle. This is the primary visual indicator of the crop area.

**Corner handles:** With a circular selection, the corner resize handles sit at the corners of the bounding box (outside the visible circle). This is standard behavior for circular crop UIs — the handles are at the cardinal corners of the square that inscribes the circle.

**Shade/dimmed area:** The `cropper-shade` still dims everything outside the rectangular selection bounds. The circular mask on the selection itself creates the visual effect of "circle of clarity within dimmed area." The corners between the circle and the rectangle are dimmed by the shade overlay, which reinforces the circular framing.

**Move handle:** The transparent move handle inside the selection should also get `border-radius: 50%` to match the circular hit area.

---

## 3. Responsive Two-Column Layout (Desktop)

On wider viewports, the crop area and controls sit side-by-side. On narrow viewports, they stack vertically.

**Breakpoint:** The identity picker modal uses `max-w-2xl` (672px) for the hub view. For the crop view, expand the modal to `max-w-5xl` (1024px) to accommodate the two-column layout. Use a **CSS container query** (`@container`) on the modal body rather than a viewport media query, since the modal width is what determines available space, not the viewport. The threshold for switching to two-column should be approximately `640px` of container width.

**Modal size change:** When switching to crop view, the modal should transition to `max-w-5xl`. When returning to hub, it returns to `max-w-2xl`. This can be handled by toggling a class on the `<dialog>` element via the `mode-switch` controller.

**Desktop layout (container >= 640px):**
```
┌─────────────────────────────────────────────────────┐
│  ← Crop your photo                               X  │
├────────────────────────┬────────────────────────────┤
│                        │  PREVIEW                    │
│                        │  ┌──────┐                   │
│    [Crop viewport]     │  │ ○    │ Circular Result   │
│     with circular      │  └──────┘ This is how your  │
│     overlay            │           photo will look    │
│                        │                              │
│  ↔ 800 × 800px        │  ⊕ Zoom Level        100%   │
│                        │  ──●─────────────────       │
│  Drag to move ·        │                              │
│  Pinch to zoom         │  [ ↺ Reset ]                │
│                        │                              │
│                        │  ℹ High quality images...    │
├────────────────────────┴────────────────────────────┤
│  🗑 Remove photo          Upload new   Save crop     │
└─────────────────────────────────────────────────────┘
```

- Left column (~55%): Crop viewport, dimension badge, hint text
- Right column (~45%): Preview, zoom slider, reset button, info banner

**Mobile layout (< lg):**
```
┌──────────────────────────┐
│  ← Crop your photo       │
│                           │
│   [Crop viewport with     │
│    circular overlay]      │
│  ↔ 800 × 800px           │
│  Drag to move ·           │
│  Pinch to zoom            │
│                           │
│  PREVIEW                  │
│  ○ Circular Result        │
│                           │
│  ⊕ Zoom Level      100%  │
│  ──●──────────────────    │
│                           │
│  [ ↺ Reset ]              │
│                           │
│  ℹ High quality images... │
│                           │
│  Cancel         Save crop │
│  🗑 Remove photo          │
└──────────────────────────┘
```

**Implementation:** Define a container on the crop view wrapper, then use `@container` queries in `cropper.css` to switch between single-column and two-column grid layout. Alternatively, use Tailwind's `@container` variant if available in v4. Fallback: since the modal width is controlled by JS (toggling `max-w-2xl` ↔ `max-w-5xl`), a simpler approach is to use a CSS class (e.g., `.crop-view-layout`) that applies the grid when the crop view is active.

---

## 4. Zoom Slider with Label and Percentage

Replace the bare slider with a labeled control showing current zoom level.

**Layout:**
```
⊕ Zoom Level                    100%
[━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━]
```

- Left: magnifying glass icon + "Zoom Level" label
- Right: percentage display (e.g., "100%", "150%", "250%")
- Below: the range slider

**Percentage calculation:** The slider goes 0-100. Map to display percentage:
- Slider 0 = 100% (base scale, no zoom)
- Slider 100 = 300% (max zoom, matches the `Math.pow(3, value/100)` curve)
- Formula: `Math.round(100 * Math.pow(3, sliderValue / 100))` + "%"

**Update behavior:** The percentage display updates in real-time as the user drags the slider. The JS controller already has `handleSlider()` — add a target for the percentage span and update it there.

**Locale keys:**
- `identity_picker.zoom_label`: "Zoom Level"

---

## 5. Dimension Badge on Crop Area

A small badge in the lower-left corner of the crop viewport shows the current crop dimensions.

**Appearance:**
```
↔ 800 × 800px
```

- Positioned absolute, bottom-left of the crop container, with small margin
- Semi-transparent dark pill: `bg-black/60 text-white text-xs font-mono px-2 py-1 rounded`
- Resize icon (↔) before the dimensions
- Format: `{width} × {height}px` — always shows integer values

**Update behavior:** Dimensions update when:
- Cropper initializes (initial selection size)
- User resizes the selection (drag corner handles)
- User resets the crop

The `image_cropper_controller` listens to the `change` event on `cropper-selection` (already present for bounds enforcement). Add a target for the dimension badge and update its text content in the same handler.

**Note:** Cropper.js v2's `selection.width`/`.height` report CSS-pixel dimensions of the selection element. To display meaningful image-pixel dimensions, compute the ratio between the image's natural size and its displayed size, then multiply. This should be verified during implementation — if the math is complex or unreliable, display CSS-pixel dimensions (still useful feedback) and note "approximate" in the badge.

---

## 6. Hint Text Below Crop Area

Instructional text below the crop viewport guides first-time users.

**Text:** "Drag to move \u00b7 Pinch to zoom"

- Centered below the crop container
- Styled: `text-sm text-text-muted` (adapts to dark mode automatically via token)
- Only visible when cropper is active (always visible in crop view — this is fine since the crop view is only shown when actively cropping)

**Locale key:**
- `identity_picker.crop_hint`: "Drag to move \u00b7 Pinch to zoom"

---

## 7. Info Banner

A contextual tip encouraging high-quality, centered photos.

**Text:** "High quality images work best. We recommend using a photo where your face is centered and clearly visible."

**Appearance:**
- Blue info style: `bg-info-subtle text-info` (uses signal tokens — adapts to dark mode)
- Small info circle icon on the left
- `text-sm` body text
- Rounded corners, padding `p-3`
- Full width within its column

**Locale key:**
- `identity_picker.image_quality_tip`: "High quality images work best. We recommend using a photo where your face is centered and clearly visible."

---

## 8. Reset as Outlined Button

Promote the Reset action from a text link to a proper outlined button for better discoverability.

**Appearance:**
- Outlined style: `border border-border rounded-lg px-4 py-2`
- Icon + text: `↺ Reset`
- Full width within the right column (desktop) or inline (mobile)
- Hover: `hover:bg-surface-sunken`

**Remove the current "Reset" text link** from the secondary actions stack. It moves into the controls area next to/below the zoom slider.

---

## 9. Footer Layout — Spatial Separation

Separate destructive and constructive actions with clear spatial placement.

**Desktop footer (below both columns, full width):**
```
🗑 Remove photo                      Upload new    Save crop
```

- Left: "Remove photo" (destructive — `text-danger` with trash icon)
- Right: "Upload new" (secondary text link) and "Save crop" (primary button)
- The "Back to identity switcher" text link moves above the footer or becomes the back arrow only (already in header)

**Mobile footer:**
```
         Cancel              Save crop
         🗑 Remove photo
```

- Top row: "Cancel" (secondary) and "Save crop" (primary), side by side
- Below: "Upload new" (text link) and "Remove photo" (destructive), on the same line with space between
- "Upload new" remains visible on all viewports — it's a key action for replacing the current image

**Note on "Cancel" vs "Back to identity switcher":** The reference uses "Cancel" which is clearer and more concise. Replace the "Back to identity switcher" text with "Cancel" — both the header back arrow and this button return to the hub without saving. The back arrow in the header is kept.

**Locale key changes:**
- `identity_picker.cancel`: "Cancel" (replaces `back_to_hub`)

---

## 10. Larger Preview with Richer Description

Enhance the preview section to give users more confidence in their crop.

**Layout:**
```
PREVIEW

┌──────┐
│  ○   │  Circular Result
│      │  This is how your profile photo
└──────┘  will look on the dashboard.
```

- "PREVIEW" label: `text-xs uppercase tracking-wider text-text-muted`
- Preview circle: `w-16 h-16` (up from `w-12 h-12`) with `rounded-full overflow-hidden`
- Title: "Circular Result" — `text-sm font-medium text-text-heading`
- Description: "This is how your profile photo will look on the dashboard." — `text-xs text-text-muted`

**Locale keys:**
- `identity_picker.preview_title`: "Circular Result"
- `identity_picker.preview_description`: "This is how your profile photo will look on the dashboard."

---

## Summary of Locale Key Changes

New keys to add under `identity_picker`:
- `zoom_label`: "Zoom Level"
- `crop_hint`: "Drag to move \u00b7 Pinch to zoom"
- `image_quality_tip`: "High quality images work best. We recommend using a photo where your face is centered and clearly visible."
- `cancel`: "Cancel"
- `preview_title`: "Circular Result"
- `preview_description`: "This is how your profile photo will look on the dashboard."

Keys to remove:
- `back_to_hub` (replaced by `cancel`)

Existing keys unchanged:
- `crop_title`, `save_crop`, `upload_new`, `remove_photo`, `reset_crop`, `result_label`, `result_description`, `zoom_label` (aria), `crop_area_label`, `back`

---

## What This Spec Does NOT Cover

- Hub/identity switcher view styling (separate future pass)
- Any backend or controller logic changes
- New Stimulus controllers or targets (uses existing architecture)
- Cropper.js v2 behavioral changes (zoom curve, bounds enforcement, export — all unchanged)
- Workspace logo variant differences (covered by existing parameterization)
