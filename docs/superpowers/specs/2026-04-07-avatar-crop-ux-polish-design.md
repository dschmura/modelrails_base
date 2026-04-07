# Avatar/Crop UX Polish

**Date:** 2026-04-07
**Status:** Draft
**Builds on:** 2026-04-07-cropperjs-image-crop-design.md

## Summary

Streamline the avatar and image crop UX so the modal is the primary interaction for all avatar management. Eliminate unnecessary page navigation, simplify controls, and tighten the crop UI layout. These changes apply to both user avatar and workspace logo flows.

## Goals

- Single entry point: clicking the avatar opens the modal for all actions
- No page navigation required for common avatar operations
- Compact, space-efficient crop UI in both modal and standalone contexts
- Consistent experience between modal and standalone crop
- Maintain WCAG 2.2 Level AAA compliance

## Non-Goals

- Changing the upload mechanism (drag-and-drop, validation, file types)
- Changing the crop coordinate storage format
- Adding new avatar sources beyond upload/gravatar/initials

## Changes

### 1. Profile Page: Single Entry Point via Modal

**Current behavior:**
- Avatar uploaded → click avatar navigates to standalone crop page
- No avatar → click avatar opens upload modal
- Separate "Crop" and "Upload new" text links below avatar

**New behavior:**
- Click avatar **always opens the modal**, regardless of current state
- No avatar → modal opens with upload drop zone (unchanged)
- Avatar uploaded → modal opens showing crop UI with Cropper.js already initialized on the current image, plus an "Upload new photo" link below save that swaps back to the upload drop zone
- Single "Change" text link below avatar name (replaces "Crop" + "Upload new")

**Implementation:**
- Remove the `link_to crop_account_avatar_path` branch from [edit.html.erb](app/views/account/profiles/edit.html.erb). Both branches (avatar/no-avatar) become `button data-action="click->modal#open"`.
- The modal renders differently based on state:
  - No avatar: shows upload drop zone (current `_image_upload_modal` behavior)
  - Has avatar: shows crop UI directly (new — render `_image_crop` content inside the modal on page load)
- Replace "Crop" + "Upload new" links with single "Change" link that opens the modal.

**Modal with existing avatar — content structure:**
The modal body contains the crop UI (Cropper.js on the current avatar) with a compact layout:
- Crop viewport (max-height: 45vh)
- Inline preview + Save button row
- "Upload new photo" text link below (swaps modal body back to upload drop zone via Turbo Stream or Stimulus action)
- "Use initials" / "Remove photo" secondary actions at bottom

This means the modal needs to support two "modes": upload mode and crop mode. On the profile page, the initial mode depends on whether an avatar is already uploaded.

**Mode switching mechanism:** The modal contains both the crop content and the upload content, wrapped in togglable containers. A Stimulus controller (the existing `modal` controller, extended with a `switchMode` action, or a lightweight `mode-switch` controller) toggles visibility between the two. No server round-trip needed to switch modes — both are pre-rendered in the HTML. When the user clicks "Upload new photo" from crop mode, the crop container hides and the upload container shows. After a successful upload (turbo_stream response), the crop container's image is replaced and crop mode is restored.

### 2. Profile Page: Simplified Controls

**Current:** Avatar + "Crop" link + separator + "Upload new" button + source selection radio buttons (when multiple sources available).

**New:** Avatar + single "Change" text link. Source selection (gravatar/initials/upload) moves inside the modal as a secondary section below the upload drop zone, shown only when multiple sources are available.

**Implementation:**
- Remove the conditional "Crop" / "Upload new" links section
- Replace with single "Change" link: `button data-action="click->modal#open"`
- Move avatar source radio buttons into the upload modal partial as an optional section (new local: `avatar_sources: []`)

### 3. Standalone Crop Page: Kept as Fallback

The standalone crop page (`/account/avatar/crop`) remains unchanged. It serves:
- Direct URL access (bookmarks, shared links)
- The "Upload different" redirect flow
- Workspace branding (where the modal-first approach can be adopted in a future iteration)

No profile page element links to it anymore. It is accessible only via direct URL.

### 4. Modal Crop: Add Zoom Slider

The modal crop UI (both the initial crop mode and the turbo_stream crop after upload) includes the zoom slider between the crop viewport and the action row.

**Layout in modal:**
```
[Crop viewport — max-height: 45vh]
[Zoom slider row: 🔍− ────────── 🔍+  Reset]
[Instruction text — small muted]
[Preview circle (48px) | Save crop button | Skip button]
[Upload new photo · Use initials · Remove photo]
```

### 5. Instruction Text: Streamlined

**Standalone crop page:**
- Remove instruction text from the card header
- Add a single line of small muted text between the zoom slider and action row: "Drag to reposition · Resize corners to zoom"
- Remove "Image will be cropped to a circle" — the circular preview makes this self-evident

**Modal crop:**
- Same single line of instruction text below the zoom slider
- Keep it brief — space is valuable in the modal

**I18n changes:**
- Keep `image_crop.instructions` as "Drag to reposition · Resize corners to zoom" (already updated)
- Remove `image_crop.instructions_circle` and `image_crop.instructions_rect` from the header usage
- The header subtitle becomes just the page/modal title context (e.g., no subtitle at all, or a very brief one)

### 6. Preview: Compact and Inline with Actions

**Current:** Separate bordered section with "Preview:" label, responsive preview circle (48-80px).

**New:** Small preview circle (48px fixed) positioned inline with the primary action buttons.

**Standalone crop page layout:**
```
[Crop viewport]
[Zoom slider + Reset]
[Instruction text — small muted]
[Preview (48px circle) ·····  Skip cropping | Save crop]
[Upload different · Use initials · Remove photo]
```

**Modal crop layout:**
```
[Crop viewport]
[Zoom slider + Reset]
[Instruction text — small muted]
[Preview (48px circle) ·····  Skip | Save crop]
[Upload new · Use initials · Remove photo]
```

The preview sits in the same row as the buttons, left-aligned, with buttons right-aligned. No label, no border, no separate section. This reclaims ~80px of vertical space.

## File Changes

### Modify

| File | Change |
|------|--------|
| `app/views/account/profiles/edit.html.erb` | Both avatar branches open modal; single "Change" link; remove source radio buttons section |
| `app/views/shared/_image_crop.html.erb` | Compact layout: instruction text below slider, preview inline with buttons, remove header subtitle |
| `app/views/shared/_image_upload_modal.html.erb` | Add optional `avatar_sources` local for source selection section |
| `app/views/account/avatars/update.turbo_stream.erb` | Add zoom slider, compact layout matching standalone page |
| `app/views/workspaces/brandings/update.turbo_stream.erb` | Add zoom slider, compact layout |
| `config/locales/en/image_crop.en.yml` | Remove `instructions_circle` / `instructions_rect` from header usage; may keep keys for other use |
| `config/locales/en/account.en.yml` | Simplify avatar link text |

### Create

| File | Purpose |
|------|---------|
| `app/javascript/controllers/mode_switch_controller.js` | Lightweight Stimulus controller to toggle between crop and upload content inside the modal. Shows/hides targets based on a `mode` value. |

## Testing

### System Specs Updates

- **Profile page (no avatar):** Click avatar → upload modal opens (unchanged)
- **Profile page (has avatar):** Click avatar → modal opens with crop UI, not navigation to crop page
- **Profile page:** Single "Change" link visible (not "Crop" + "Upload new")
- **Modal crop → save:** Avatar updates on page, modal closes, header avatar updates
- **Modal crop → upload new:** Modal content swaps to upload drop zone
- **Standalone crop page:** Still accessible via direct URL, functions correctly

### Request Spec Updates

- Existing turbo_stream specs remain valid
- New spec: profile page renders crop UI in modal when avatar is uploaded

### Accessibility

- All interactive elements maintain 44x44px touch targets
- Focus management: modal open → focus trapped in modal → modal close → focus returns
- Zoom slider retains ARIA labels
- axe-core audit on modal crop state
