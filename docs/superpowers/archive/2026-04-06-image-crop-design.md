# Optional Image Cropping — Design Spec

## Overview

Add optional user-directed cropping for image uploads. Cropping is a separate step from upload — the existing upload modal stays unchanged. After uploading, a "Crop" link appears next to the image. Clicking it opens a dedicated crop page where the user can pan/zoom to select a crop region. Crop coordinates are stored in Active Storage blob metadata and applied as a variant at render time.

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where does cropping happen? | **Server-side** (coordinates from client, ImageProcessing on server) | Avoids Cropper.js/canvas.toBlob bugs from spike. Native form submit. Original preserved. |
| Where is the crop UI? | **Dedicated page** (not modal) | No modal layout constraints. Full viewport for the crop area. Own URL for bookmarking/back button. |
| When does cropping happen? | **After upload, on demand** | Upload completes immediately. "Crop" link appears. User crops when they want. |
| Where are coordinates stored? | **Active Storage blob metadata** | No migrations per model. Co-located with the image. Fresh metadata on re-upload. |
| JS cropping library? | **None** | CSS transforms (translate/scale) + Stimulus controller. No external dependencies. |

## Components

### 1. Crop Page Partial: `shared/_image_crop.html.erb`

Reusable partial rendered by any controller that supports cropping.

**Locals:**

| Local | Type | Description |
|-------|------|-------------|
| `image` | ActiveStorage attachment | The image to crop |
| `aspect_ratio` | Float | Crop ratio (1.0 for square/circle, 1.778 for 16:9) |
| `shape` | Symbol | `:circle` or `:rectangle` — overlay shape |
| `save_url` | String | PATCH URL to save crop coordinates |
| `cancel_url` | String | URL to return without cropping |
| `title` | String | Page heading (e.g., "Crop avatar") |

**Layout:**

```
┌──────────────────────────────────┐
│  Title                           │
│                                  │
│  ┌────────────────────────────┐  │
│  │                            │  │
│  │   Image (draggable/zoomable)  │
│  │       ┌──────────┐        │  │
│  │       │  Crop     │        │  │
│  │       │  overlay  │        │  │
│  │       └──────────┘        │  │
│  │                            │  │
│  └────────────────────────────┘  │
│                                  │
│  Drag to reposition. Scroll to   │
│  zoom.                           │
│                                  │
│  [ Save crop ]  [ Cancel ]       │
└──────────────────────────────────┘
```

The overlay is a fixed-position element (circle or rectangle) centered in the crop container. The image moves behind it via CSS transforms. The visible area inside the overlay is what gets cropped.

### 2. Stimulus Controller: `image_crop_controller.js`

**Values:**
- `aspectRatio` (Number) — crop aspect ratio
- `imageWidth` (Number) — natural image width (set on connect)
- `imageHeight` (Number) — natural image height (set on connect)

**Targets:**
- `image` — the `<img>` element being cropped
- `container` — the crop viewport div
- `x`, `y`, `w`, `h` — hidden input fields for coordinates

**Behavior:**
- **Pan:** mousedown/touchstart → track delta → update `transform: translate(dx, dy)`
- **Zoom:** wheel event → update `transform: scale(s)` (clamped to min/max)
- **Coordinate calculation:** On "Save crop" click, convert the current translate/scale values into crop coordinates relative to the image's natural dimensions. Write to hidden inputs. Native form submit.

**No external dependencies.** ~80-100 lines of JS.

### 3. Routes

```ruby
# Avatar crop
resource :avatar, only: [:update, :destroy] do
  get :crop, on: :member
  patch :save_crop, on: :member
end

# Workspace logo crop
resource :branding, only: [:edit, :update] do
  get :crop, on: :member
  patch :save_crop, on: :member
end
```

Produces:
- `GET /account/avatar/crop` → `Account::AvatarsController#crop`
- `PATCH /account/avatar/save_crop` → `Account::AvatarsController#save_crop`
- `GET /workspaces/:slug/branding/crop` → `Workspaces::BrandingsController#crop`
- `PATCH /workspaces/:slug/branding/save_crop` → `Workspaces::BrandingsController#save_crop`

### 4. Controller Actions

**`#crop` (GET):**
- Renders the crop page with the current attachment
- If no image attached, redirects back with alert

**`#save_crop` (PATCH):**
- Reads `params[:crop]` — `{ x:, y:, w:, h: }` as integers
- Validates coordinates are within image bounds
- Writes to `blob.metadata["crop"]` via `blob.update!(metadata: blob.metadata.merge("crop" => coords))`
- Redirects to the source page with success notice

### 5. Crop Helper: `CropHelper`

```ruby
module CropHelper
  def cropped_variant(attachment, resize_to:)
    crop = attachment.blob.metadata["crop"]

    if crop.present?
      attachment.variant(
        crop: "#{crop['w']}x#{crop['h']}+#{crop['x']}+#{crop['y']}",
        resize_to_fill: resize_to
      )
    else
      attachment.variant(resize_to_fill: resize_to)
    end
  end
end
```

### 6. Changes to Existing Code

**`avatar_for` helper** — Replace `user.avatar.variant(resize_to_fill:)` with `cropped_variant(user.avatar, resize_to:)`.

**`workspace_icon_for` helper** — Same change for `workspace.logo`.

**Profile page (`account/profiles/edit.html.erb`)** — Add "Crop" link next to avatar when attached:
```erb
<% if @user.avatar.attached? %>
  <%= link_to t("account.avatars.crop"), crop_account_avatar_path, ... %>
<% end %>
```

**Branding page (`workspaces/brandings/edit.html.erb`)** — Add "Crop" link next to logo when attached.

### 7. I18n Keys

```yaml
en:
  image_crop:
    instructions: "Drag to reposition. Scroll to zoom."
    save: "Save crop"
    cancel: "Cancel"
  account:
    avatars:
      crop:
        title: "Crop avatar"
      save_crop:
        success: "Avatar cropped."
  workspaces:
    brandings:
      crop:
        title: "Crop logo"
      save_crop:
        success: "Logo cropped."
```

## Testing Strategy

- **System specs:** Navigate to real crop page, verify image loads, verify save redirects. Test on the actual rendered page (not injected HTML).
- **Request specs:** PATCH save_crop with valid coordinates → blob metadata updated. Invalid coordinates → rejected. No image attached → redirect with error.
- **Helper specs:** `cropped_variant` with metadata returns crop+resize variant. Without metadata returns resize-only variant.
- **Stimulus controller:** System spec verifying pan/zoom produces coordinate values in hidden fields.

## Out of Scope

- Client-side image manipulation (canvas.toBlob, Cropper.js)
- Crop presets (e.g., "profile", "banner" dropdown) — aspect ratio is passed by the caller
- Image rotation or filters
- Batch cropping
