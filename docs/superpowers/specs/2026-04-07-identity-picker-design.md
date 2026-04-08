# Identity Picker — Design Spec

**Date:** 2026-04-07
**Status:** Draft
**Builds on:** 2026-04-07-cropperjs-image-crop-design.md, 2026-04-07-avatar-crop-ux-polish-design.md
**Reference implementation:** modelrails_agent_os `_avatar_modal.html.erb` (UX patterns only — architecture simplified)

## Summary

A shared, reusable modal component for managing visual identity across contexts (user avatars, workspace logos, and future uses like banners). The modal adapts its content based on current state (first-time vs. returning user) and available sources (upload, initials with color picker). Client-side cropping with dual-attachment storage eliminates server-side variant processing while preserving the original image for re-cropping.

## Goals

- Single shared component (`identity_picker`) used for user avatars, workspace logos, and future image identity contexts
- Dual-view modal: management hub (when image exists) and upload-first (when no image)
- Client-side crop via `getCroppedCanvas()` — what-you-see-is-what-you-get
- Dual-attachment storage: cropped display image + original preserved + crop coordinates for re-crop
- Initials with OKLCH color picker and live multi-place preview
- Radio card source selection with inline thumbnail previews
- Contextual action buttons that adapt to selected source
- WCAG 2.2 Level AAA compliance
- Clean, composable Stimulus controllers — no deep inheritance

## Non-Goals

- Gravatar and OAuth photo sources (follow-up iteration)
- Banner/cover image support (future — architecture supports it, but not built yet)
- Image rotation/flip
- Client-side image compression

## Architecture

### Naming Convention

| Layer | User Avatar | Workspace Logo | Shared |
|-------|-------------|----------------|--------|
| Component name | — | — | `identity_picker` |
| Partial | — | — | `shared/_identity_picker.html.erb` |
| Stimulus controller | — | — | `identity_picker_controller.js` |
| Modal title | "Change avatar" | "Change logo" | Passed as local |
| I18n namespace | `account.avatars.*` | `workspaces.brandings.*` | `identity_picker.*` |

### Dual-Attachment Storage

Each model stores two attachments:

```ruby
# User
has_one_attached :avatar           # Cropped display image (served directly)
has_one_attached :avatar_original  # Untouched upload (used for re-cropping)

# Workspace
has_one_attached :logo             # Cropped display image
has_one_attached :logo_original    # Untouched upload
```

**On first upload:**
1. Original file attached to `avatar_original` (or `logo_original`)
2. Client crops via `getCroppedCanvas()` → blob
3. Cropped blob attached to `avatar` (or `logo`)
4. Crop coordinates saved to `avatar_original` blob metadata as `{ "crop": { x, y, w, h } }`

**On re-crop:**
1. `avatar_original` loaded into Cropper.js
2. Saved coordinates from metadata restore the previous selection
3. User adjusts → new `getCroppedCanvas()` → blob
4. `avatar` replaced with new cropped blob
5. Updated coordinates saved to `avatar_original` metadata

**On display:**
- Serve `avatar` directly — no variant processing, no `cropped_variant` helper needed
- Fall back to `avatar_original` if `avatar` doesn't exist (edge case during migration)
- Fall back to initials/gravatar per existing `avatar_source` logic

### Controller Architecture

Reuse and compose existing small controllers rather than building a monolithic one:

| Controller | Responsibility | Already exists? |
|-----------|---------------|-----------------|
| `modal_controller.js` | Open/close dialog, animations, focus | Yes |
| `mode_switch_controller.js` | Toggle between named content sections | Yes |
| `image_cropper_controller.js` | Cropper.js wrapper, keyboard, drop-to-upload | Yes |
| `identity_picker_controller.js` | **New.** Source selection, color picker sync, save orchestration, canvas export | No |
| `modal_closer_controller.js` | Close dialog on connect (for Turbo Stream) | Yes |

The `identity_picker_controller.js` is the only new controller. It handles:
- Source radio card selection → show/hide contextual sections
- Initials color picker → live preview updates in multiple places
- Save button → if source is "upload", export `getCroppedCanvas()` blob, build FormData, submit
- Save button → if source is "initials", submit source + color

It does NOT handle cropping mechanics (that's `image_cropper_controller`), modal open/close (that's `modal_controller`), or view switching (that's `mode_switch_controller`).

## UX Flows

### Modal Structure — Two Views

```
┌─────────────────────────────────────────────┐
│ [Title]                              [X]    │
├─────────────────────────────────────────────┤
│                                             │
│  VIEW: Main (mode="main")                   │
│  ┌─────────────────────────────────────┐    │
│  │  Current identity display           │    │
│  │  (large avatar/logo + metadata)     │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  Source selection (radio cards)      │    │
│  │  ○ Upload photo    [thumbnail]      │    │
│  │  ○ Initials        [color circle]   │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  Contextual actions                 │    │
│  │  [Upload] [Edit crop] [Delete]      │    │
│  │  — or —                             │    │
│  │  [Color picker slider]              │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  VIEW: Crop (mode="crop")                   │
│  ┌─────────────────────────────────────┐    │
│  │  Cropper.js viewport               │    │
│  │  Zoom slider + instructions         │    │
│  │  [Preview] [Save] [Cancel]          │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  VIEW: Upload (mode="upload")               │
│  ┌─────────────────────────────────────┐    │
│  │  Drop zone / file picker            │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

### Flow A: First-time user (no avatar)

1. Click avatar/change link → modal opens in **upload mode**
2. Select/drop file → file uploads, transitions to **crop mode**
3. Adjust crop → Save → client-side canvas export → server saves both attachments
4. Modal closes, avatar appears everywhere

### Flow B: Returning user (has uploaded avatar)

1. Click avatar → modal opens in **main mode**
2. Sees current avatar large, source cards below, action buttons
3. Options:
   - **Edit crop** → switch to crop mode, `avatar_original` loaded with saved coordinates
   - **Upload new** → switch to upload mode, pick file → crop mode with new image
   - **Switch to initials** → color picker appears, live preview, save changes source
   - **Delete** → confirmation → removes avatar, falls back to initials

### Flow C: Initials color customization

1. On main view, select "Initials" radio card
2. Action section switches to show OKLCH hue slider
3. Dragging slider updates:
   - The color circle in the initials radio card
   - The large identity display at top of modal
   - The hue preview bar below the slider
4. Save → updates `primary_color` (user or workspace)

## Component: Source Radio Cards

Each source option is a card with:
- Radio input (visually styled as a card border highlight)
- Source label
- Inline thumbnail preview (actual image for upload, color circle for initials)
- Selected state: `border-interactive bg-interactive/5`
- Unselected state: `border-border hover:border-border-strong`

```
┌──────────────────────────────────┐
│ ○  Uploaded photo    [thumb]     │
└──────────────────────────────────┘
┌──────────────────────────────────┐
│ ●  Initials          [JD circle] │
└──────────────────────────────────┘
```

When a card is selected, the contextual action section below updates:
- **Upload selected:** Shows Upload / Edit crop / Delete buttons (Edit and Delete disabled if no image uploaded)
- **Initials selected:** Shows OKLCH hue slider + preview

## Component: OKLCH Color Picker

A range slider that cycles through hue values (0-360) at a fixed lightness and chroma appropriate for the design token system.

**Slider background:** CSS `linear-gradient` with OKLCH color stops around the full 360° hue wheel.

**Live updates:** Moving the slider updates the initials color in three places simultaneously:
1. The small color circle in the initials radio card
2. The large identity display at top of modal
3. The hue preview strip below the slider

**Storage:** Saves to `User#primary_color` or `Workspace#primary_color` as a hex string.

## Component: Shared Identity Picker Partial

```ruby
# Usage for user avatar:
render "shared/identity_picker",
  title: t("account.avatars.edit.title"),
  record: @user,
  image_attachment: :avatar,
  original_attachment: :avatar_original,
  save_url: account_avatar_path,
  sources: [:upload, :initials],  # Phase 1; later: @user.available_identity_sources
  current_source: @user.avatar_source,
  color_field: :primary_color,
  aspect_ratio: 1.0,
  shape: :circle

# Usage for workspace logo:
render "shared/identity_picker",
  title: t("workspaces.brandings.edit.change_logo"),
  record: @workspace,
  image_attachment: :logo,
  original_attachment: :logo_original,
  save_url: workspace_branding_path(@workspace),
  sources: [:upload, :initials],
  current_source: @workspace.logo.attached? ? "upload" : "initials",
  color_field: :primary_color,
  aspect_ratio: 1.0,
  shape: :circle
```

## File Changes

### Create

| File | Purpose |
|------|---------|
| `app/javascript/controllers/identity_picker_controller.js` | Source selection, color sync, canvas export save orchestration |
| `app/views/shared/_identity_picker.html.erb` | The shared modal interior with three views (main/crop/upload) |
| `app/views/shared/_identity_source_card.html.erb` | Single radio card for a source option |
| `db/migrate/xxx_add_original_attachments.rb` | No migration needed — ActiveStorage attachments are implicit via `has_one_attached` |

### Modify

| File | Change |
|------|--------|
| `app/models/user.rb` | Add `has_one_attached :avatar_original` |
| `app/models/workspace.rb` | Add `has_one_attached :logo_original` |
| `app/helpers/avatar_helper.rb` | Simplify — serve `avatar` directly instead of `cropped_variant` |
| `app/helpers/workspace_helper.rb` | Simplify — serve `logo` directly instead of `cropped_variant` |
| `app/helpers/crop_helper.rb` | Keep as fallback for migration period, then remove |
| `app/controllers/account/avatars_controller.rb` | Handle dual-attachment save (cropped blob + original + coordinates) |
| `app/controllers/workspaces/brandings_controller.rb` | Same dual-attachment pattern |
| `app/views/account/profiles/edit.html.erb` | Replace current modal content with `render "shared/identity_picker"` |
| `app/views/workspaces/brandings/edit.html.erb` | Same — use shared identity picker |
| `app/views/account/avatars/crop.html.erb` | Update to use `avatar_original` for re-cropping |
| `app/views/workspaces/brandings/crop.html.erb` | Same |
| `app/javascript/controllers/image_cropper_controller.js` | Add `exportCroppedBlob()` method using `getCroppedCanvas().toBlob()` |
| `config/locales/en/identity_picker.en.yml` | New — shared strings for the picker UI |
| `app/assets/stylesheets/vendor/hue-slider.css` | OKLCH gradient background for the color picker range input |

### Eventually Remove or Deprecate

| File | Status |
|------|--------|
| `app/helpers/crop_helper.rb` | Keep during migration period — remove once all images use dual-attachment |
| `app/views/shared/_image_crop.html.erb` | Keep — still used by the standalone crop page. The identity picker's crop view reuses `image_cropper_controller.js` but renders its own compact markup. |
| `app/views/shared/_image_upload_modal.html.erb` | Keep — may still be used by non-identity-picker contexts. The identity picker renders its own upload view inline. |

## Testing

### Model Specs
- User and Workspace accept `avatar_original` / `logo_original` attachments
- Attaching a cropped avatar doesn't affect the original

### Controller Specs
- `AvatarsController#save_crop` accepts a cropped blob + coordinates, stores both attachments
- `AvatarsController#update` with `avatar_source: "initials"` + color saves correctly
- Turbo Stream responses still update all visible instances

### System Specs
- **No avatar:** Click avatar → modal opens in upload mode
- **Has avatar:** Click avatar → modal opens in main mode with current avatar displayed
- **Edit crop:** Main mode → click Edit → crop view with saved coordinates → save → avatar updates
- **Upload new:** Main mode → click Upload → upload view → select file → crop view → save
- **Switch to initials:** Main mode → select Initials card → color picker appears → adjust → save
- **Delete:** Main mode → click Delete → confirmation → avatar removed, falls back to initials
- **Color picker:** Slider updates preview in 3 places simultaneously

### Accessibility
- axe-core audit on main view, crop view, and upload view
- Keyboard: Tab through radio cards, Enter to select, Tab to actions
- Screen reader: ARIA labels on radio cards, live region for source changes
- Focus management: modal open → first interactive element, view switch → first element in new view
