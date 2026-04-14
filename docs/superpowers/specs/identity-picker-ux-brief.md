# Identity Picker — UX Brief

## What It Is

A modal dialog for managing profile identity — the image and color that represent a user or workspace throughout the application. It replaces scattered upload/crop/delete buttons with a single unified hub where users choose their identity source, customize it, and save.

The same component is used for both **user avatars** and **workspace logos**, adapted to each context.

## Where It Appears

The identity picker opens as a modal when the user clicks their avatar on the profile settings page, or their workspace logo on the branding settings page. The avatar/logo itself acts as the trigger — it has a hover state indicating it's interactive.

## Identity Sources

Users choose how they want to be represented:

- **Photo** — A cropped image they upload
- **Gravatar** — Their Gravatar image (users only, not workspaces)
- **Initials** — A colored circle with their initials (e.g., "JD" for Jane Doe)

All three sources are always available to choose from. The current selection is visually indicated.

---

## Modal Views

The modal has two views: the **Identity Switcher** (hub) and the **Crop Editor**.

### Identity Switcher (default view)

The identity switcher is what users see when the modal opens. It's a hub — users pick their identity source, optionally customize it, and save.

**Header:**
- Title: "Edit profile picture" (or "Edit workspace logo")
- Close button (X) in the top-right corner

**Layout (top to bottom):**

1. **Large circular preview** — Prominent circle showing the current identity (photo, gravatar, or initials). Below the circle, a "PREVIEW" label makes its purpose explicit. This preview updates live as the user makes changes.

2. **Section heading** — "Choose how you're represented" introduces the source cards.

3. **Source cards** — A vertical stack of radio-style cards, one per available source. Each card contains:
   - **Icon** (left side) — A distinctive icon representing the source type:
     - Photo: camera icon
     - Gravatar: globe icon
     - Initials: small initials circle showing the user's actual initials
   - **Title + description** (center) — The source name and a brief explanation:
     - Photo: "Upload or take a custom picture"
     - Gravatar: "Sync with your gravatar.com profile"
     - Initials: "A simple, colored circle with your initials"
   - **Radio indicator** (right side) — Standard radio button showing selected state
   - The selected card has a visible border/highlight to reinforce the active choice
   - Selecting a card immediately updates the preview above

4. **Contextual controls** — Appear below the source cards depending on the selection:
   - When **Photo** is selected and an image exists: the preview becomes clickable (with an edit icon on hover) and clicking it opens the Crop Editor.
   - When **Photo** is selected and no image exists: clicking the Photo card immediately opens the device's native file picker.
   - When **Initials** is selected: a color picker panel appears (see Color Picker section below).
   - When **Gravatar** is selected: no additional controls — what you see is what you get.

5. **Save button** — "Save & apply" with a checkmark icon. Full-width, primary style, anchored at the bottom. Commits the selected source (and color, if applicable). Always visible regardless of which source is selected.

**Key principle:** The hub has no action links or secondary buttons. It's a clean switcher. All photo management (crop, upload new, remove) happens in the Crop Editor.

### Crop Editor View

The crop editor is where users fine-tune their photo. They reach it by:
- Clicking their photo preview on the identity switcher (when a photo exists)
- Selecting a file from the native file picker (when uploading a new photo)

**Header:**
- Back arrow (←) for navigation, replacing the X close button
- Title: "Crop your photo"
- This header pattern signals "you're one level deeper" rather than "a separate dialog"

**Layout (top to bottom):**

1. **Crop area** — A large viewport showing the full image with a draggable, resizable crop selection overlaid. The selection is always square (1:1 aspect ratio). The area outside the selection is dimmed with a semi-transparent overlay. Users can:
   - Drag the selection to reposition it
   - Drag the corners/edges to resize it (visible corner handles)
   - Drag the image itself to pan within the viewport

2. **Zoom slider** — A minimal horizontal slider below the crop area. Simple dot/thumb on a track. Zooming is smooth and centered.

3. **Result row** — A horizontal row containing:
   - **Small circular preview** (left) — Shows exactly what the cropped result will look like at avatar size, labeled "Result" with subtitle "Circular preview"
   - **"Save crop" button** (right) — Primary action, compact size

4. **Secondary actions** — Icon + text links arranged below the result row:
   - **Upload new** (upload icon) — Opens the native file picker to replace the current image. After selecting a new file, the user stays in the crop editor with the new image loaded.
   - **Remove photo** (trash icon, destructive color) — Removes the photo entirely and returns to the identity switcher. The identity falls back to initials.
   - **Back to identity switcher** (text link) — Returns to the hub without saving changes.

**Key principle:** All photo management is consolidated here — crop, replace, and remove are grouped with the photo they act on. The back arrow in the header and "Back to identity switcher" link both return to the hub.

---

## User Flows

### Flow 1: First-time photo upload

1. User clicks their avatar on the profile page
2. Modal opens → Identity switcher shows initials preview (no photo exists yet)
3. User clicks the "Photo" source card
4. Native file picker opens immediately (no intermediate upload screen)
5. User selects a file from their device
6. Modal transitions to Crop Editor with the selected image
7. User adjusts crop selection and zoom
8. User clicks "Save crop"
9. Modal returns to identity switcher — preview now shows the cropped photo
10. User clicks "Save & apply"
11. Modal closes — avatar updates everywhere on the page

### Flow 2: Re-cropping an existing photo

1. User clicks their avatar on the profile page
2. Modal opens → Identity switcher shows photo preview
3. User clicks the photo preview (or the Photo source card)
4. Crop Editor opens with the existing image and previous crop selection restored
5. User adjusts the crop
6. User clicks "Save crop"
7. Modal returns to identity switcher with updated preview
8. User clicks "Save & apply"

### Flow 3: Replacing a photo

1. User is in the Crop Editor (via flow 1 or 2)
2. User clicks "Upload new"
3. Native file picker opens
4. User selects a new file
5. Crop Editor reloads with the new image
6. User crops and saves

### Flow 4: Switching to initials with a custom color

1. User clicks their avatar on the profile page
2. Modal opens → Identity switcher
3. User clicks the "Initials" source card
4. Preview updates to show initials circle in the current/default color
5. Color picker panel appears below the source cards
6. User drags the hue slider — preview updates in real-time showing different colors
7. User finds a color they like
8. User clicks "Save & apply"
9. Modal closes — all avatars on page update to the colored initials

### Flow 5: Switching to Gravatar

1. User clicks their avatar
2. Modal opens → Identity switcher
3. User clicks the "Gravatar" source card
4. Preview updates to show their Gravatar image
5. User clicks "Save & apply"

### Flow 6: Removing a photo

1. User is in the Crop Editor
2. User clicks "Remove photo"
3. Modal returns to identity switcher — preview switches to initials
4. User clicks "Save & apply" (or switches to a different source first)

---

## Color Picker

The color picker appears as a self-contained panel below the source cards when Initials is selected. It has two elements:

**Label row:**
- "Circle color" label on the left
- Current hex value displayed on the right (e.g., "#3B82F6") — this is read-only display, not an editable input

**Hue slider:**
- A horizontal gradient bar showing the full color spectrum (red → orange → yellow → green → cyan → blue → purple → pink → red)
- A circular thumb/handle that the user drags along the gradient
- The slider track IS the gradient — no separate preview bar needed

**Behavior:**
- Dragging the slider updates the initials preview in real-time
- The hex value display updates as the user drags
- All colors maintain sufficient contrast with white text for readability (fixed lightness ensures this)
- The chosen color persists — it's remembered even if the user switches to a photo and back to initials later

---

## Keyboard & Accessibility

- The modal traps focus and can be closed with Escape
- Source cards are navigable with arrow keys (standard radio group behavior)
- The crop area supports keyboard controls:
  - Arrow keys move the crop selection
  - Plus/minus keys zoom in and out
  - Shift modifier increases the step size for both
- The zoom slider and color picker slider are keyboard-accessible (arrow keys)
- Screen readers announce source changes, color changes, and zoom level
- All interactive elements meet minimum touch target sizes (44px)
- The crop editor's back arrow is keyboard-focusable and activated with Enter/Space

---

## Workspace Logos

The same modal is used for workspace logos on the branding settings page. The differences:

- No Gravatar option (only Photo and Initials source cards)
- Modal title says "Edit workspace logo" instead of "Edit profile picture"
- The initials show the workspace's initials (e.g., "AW" for "Acme Workspace")
- The initials icon in the source card shows the workspace's initials
- Color picker works identically

---

## Key Design Constraints

- **No intermediate upload screen** — Selecting "Photo" with no image goes straight to the native file picker. No drop zone, no upload progress screen. The file picker is the OS-native dialog.
- **Hub is a switcher only** — No action buttons on the hub. The only button is "Save & apply." All photo actions live in the crop editor.
- **Preview is always live** — Every change (source selection, color slider, crop adjustment) is reflected in the preview immediately, before saving.
- **Photo is preserved on source switch** — Switching from Photo to Initials doesn't delete the photo. The user can switch back without re-uploading.
- **Crop is remembered** — When re-editing a photo, the previous crop selection is restored, not reset.
- **One save point per view** — Identity switcher has "Save & apply." Crop editor has "Save crop." No ambiguity about which button does what.
- **Consistent navigation** — Back arrow in crop editor header + "Back to identity switcher" text link both return to the hub. Two paths for the same action accommodates both header-scanners and content-readers.
- **Destructive actions are visually distinct** — "Remove photo" uses a trash icon and a destructive/warning color to differentiate it from neutral actions like "Upload new."

---

## Visual Reference

These mockups represent the target direction:

**Identity Switcher (hub):**
- Clean vertical layout with generous spacing
- Source cards are full-width with icon | text | radio layout
- Selected card has a colored border
- Color picker is a contained panel, not floating
- Save button is dark/primary, full-width, anchored at bottom

**Crop Editor:**
- Back arrow navigation in header (← "Crop your photo")
- Crop area dominates the viewport
- Dimmed overlay outside the selection
- Minimal zoom slider (simple track + thumb)
- Result row: small circular preview + save button on same line
- Secondary actions below with icons, "Remove photo" in destructive color
