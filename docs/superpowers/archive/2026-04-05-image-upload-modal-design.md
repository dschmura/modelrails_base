# Image Upload Modal with Optional Cropping — Design Spec

## Problem

The app has no reusable infrastructure for image uploads. Avatar upload is a bare controller with no preview, no cropping, no drag-and-drop, and no file validation UI. Future features (workspace logos, background images) will need the same upload mechanics. Building each from scratch creates inconsistency.

## Solution

Two reusable pieces:

1. **Image Cropper Controller** — Standalone Stimulus controller wrapping Cropper.js (loaded lazily via importmap). Configurable aspect ratio and output dimensions. Emits a `cropper:complete` event with the cropped Blob.
2. **Image Upload Modal** — Generic partial for uploading/removing images on any `has_one_attached` field. Shows current image preview, drag-and-drop upload zone, optional cropper integration, and remove button. Uses the existing modal system.

These are independent of avatars — they work for any image upload scenario.

## Design Decisions

### Why Cropper.js?

Mature, well-maintained library (v1.6.x stable for years). Supports configurable aspect ratios, zoom, rotation. 45KB loaded lazily only when the cropper controller connects — zero cost for pages that don't use it.

### Why importmap instead of npm?

The project uses Rails importmaps for all JavaScript. npm is only present for Playwright (dev dependency). Cropper.js is pinned via `bin/importmap pin cropperjs` and vendored to `vendor/javascript/`. The CSS is vendored separately. No CDN runtime dependency.

### Why a separate cropper controller?

The cropper is useful outside modals — inline forms, standalone pages, future components. Keeping it as its own Stimulus controller means the modal doesn't need to know about Cropper.js internals. The modal just listens for the `cropper:complete` event.

## Architecture

### Image Cropper Controller (`app/javascript/controllers/image_cropper_controller.js`)

Standalone Stimulus controller. No dependency on the modal system.

**Values:**

| Value | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `aspectRatio` | Number | 0 | Crop aspect ratio. 0 = free, 1 = square, 3 = 3:1 |
| `maxWidth` | Number | 1024 | Maximum output width in pixels |
| `maxHeight` | Number | 1024 | Maximum output height in pixels |
| `maxFileSize` | Number | 5 | Maximum file size in MB |

**Targets:**

| Target | Purpose |
| ------ | ------- |
| `fileInput` | The `<input type="file">` element |
| `preview` | Container where Cropper.js renders the image |
| `cropArea` | Wrapper div shown during cropping (hidden initially) |
| `uploadArea` | Wrapper div shown before file selection (hidden during cropping) |

**Actions:**

| Action | Trigger | Behavior |
| ------ | ------- | -------- |
| `loadImage` | File input `change` | Validates file, reads as data URL, initializes Cropper.js on preview |
| `crop` | Save button click | Gets cropped canvas, converts to Blob, dispatches `cropper:complete` |
| `cancel` | Cancel button click | Destroys Cropper.js instance, shows upload area, hides crop area |

**Events dispatched:**

| Event | Detail | When |
| ----- | ------ | ---- |
| `cropper:complete` | `{ blob, filename }` | After successful crop |
| `cropper:error` | `{ message }` | File validation failure (wrong type, too large) |

**Lifecycle:**

- `connect()` — Pre-loads Cropper.js module via dynamic `import("cropperjs")`. Stores reference for later use.
- `disconnect()` — Destroys active Cropper.js instance if any.

**File validation (client-side — UX only, not a security boundary):**

- Allowed types: `image/png`, `image/jpeg`, `image/gif`, `image/webp` (checked against file.type)
- Max size: configurable via `maxFileSize` value in MB (checked against `file.size / 1024 / 1024`)
- On failure: dispatches `cropper:error` with I18n error message, does not initialize cropper

**Cropper.js load failure:**

- If the dynamic `import("cropperjs")` fails (network error, importmap misconfiguration), the controller catches the error and dispatches `cropper:error` with the `image_upload.errors.cropper_load_failed` I18n message
- Falls back to submitting the original file without cropping — the server-side variant handles resizing

### Image Upload Controller (`app/javascript/controllers/image_upload_controller.js`)

Thin coordinator between the file input, optional cropper, and form submission.

**Values:**

| Value | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `crop` | Boolean | false | Whether to use the cropper before uploading |

**Targets:**

| Target | Purpose |
| ------ | ------- |
| `form` | The upload form element |
| `fileInput` | File input (shared with cropper when crop is enabled) |
| `croppedInput` | Hidden file input for cropped Blob (only when crop is enabled) |
| `dropZone` | Drag-and-drop area |
| `errorMessage` | Element to show validation errors |

**Actions:**

| Action | Trigger | Behavior |
| ------ | ------- | -------- |
| `submit` | File input change (when crop is false) | Submits the form directly |
| `handleCropComplete` | `cropper:complete` event | Injects Blob into hidden input, submits form |
| `handleCropError` | `cropper:error` event | Shows error message |
| `dragOver` / `dragLeave` / `drop` | Drag events on drop zone | Visual feedback + file handling |

**Flow without crop:** File input change → submit form → Turbo response → modal closes.

**Flow with crop:** File input change → cropper loads image → user adjusts crop → clicks Save → `cropper:complete` fires → controller injects Blob → submits form → Turbo response → modal closes.

### Image Upload Modal Partial (`app/views/shared/_image_upload_modal.html.erb`)

```erb
<%# locals: (title:, form_url:, form_method: :patch, field_name: :image,
             current_image: nil, placeholder: nil,
             remove_url: nil, remove_method: :delete,
             crop: false, aspect_ratio: 1, max_width: 512, max_height: 512,
             accept: "image/png,image/jpeg,image/gif", max_file_size: 5,
             id: nil, size: :md) %>
```

**Structure:**

Wraps the existing `shared/modal` partial. Inside:

1. **Current preview** — Shows `current_image` (Active Storage attachment) or `placeholder` HTML
2. **Upload zone** — Dashed border area with "Click to upload or drag and drop" text and file constraints. Contains the hidden file input.
3. **Crop area** (when `crop: true`) — Hidden initially. Contains the cropper preview, Cancel, and Save buttons. Shown when file is selected.
4. **Remove link** (when `remove_url` is present) — "Remove current image" link that submits a DELETE to `remove_url`
5. **Error display** — Shows file validation errors from the cropper

**Stimulus wiring:**

```html
<div data-controller="image-upload"
     data-image-upload-crop-value="true|false">
  <!-- When crop is true, also nest: -->
  <div data-controller="image-cropper"
       data-image-cropper-aspect-ratio-value="1"
       data-image-cropper-max-width-value="512"
       data-image-cropper-max-height-value="512"
       data-image-cropper-max-file-size-value="5"
       data-action="cropper:complete->image-upload#handleCropComplete
                    cropper:error->image-upload#handleCropError">
  </div>
</div>
```

### Cropper.js Dependency

Installed via importmap:

```bash
bin/importmap pin cropperjs
```

CSS vendored manually:

```bash
curl -o vendor/assets/stylesheets/cropperjs.css https://unpkg.com/cropperjs@1.6.2/dist/cropper.min.css
```

Referenced in the image cropper controller or loaded conditionally when the crop area is shown.

## I18n Keys

All UI text in the upload modal uses I18n keys so downstream projects can override labels:

```yaml
en:
  image_upload:
    drop_zone: "Click to upload or drag and drop"
    constraints: "%{types} up to %{max_size}MB"
    remove: "Remove current image"
    crop_title: "Crop image"
    crop_save: "Save"
    crop_cancel: "Cancel"
    crop_instructions: "Drag to reposition. Scroll to zoom."
    errors:
      file_too_large: "File is too large. Maximum size is %{max_size}MB."
      invalid_type: "File type not supported. Please use PNG, JPG, GIF, or WebP."
      upload_failed: "Upload failed. Please try again."
      cropper_load_failed: "Image editor could not load. Your image will be uploaded without cropping."
```

The partial reads these keys and passes them to the view. Downstream projects override by editing the locale file.

## Server-Side Validation (Security Boundary)

Client-side validation is UX only — trivially bypassed. The consuming model MUST validate attachments server-side. Example using Active Storage validations:

```ruby
validates :avatar,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 5.megabytes }
```

The image upload modal spec does not enforce this — it is the responsibility of each consuming model. Document this requirement in the developer guide.

## Accessibility

- **Upload zone:** Rendered as a `<label>` wrapping the file input, not a clickable div. The `<label>` is natively keyboard accessible (Enter/Space opens the file picker). The file input is visually hidden but accessible.
- **File input:** Has `aria-describedby` linking to the constraints text (file types and size limit). Has `aria-label` from I18n (`image_upload.drop_zone`).
- **Error messages:** Rendered in a `role="alert"` container so screen readers announce validation failures immediately.
- **Crop area:** Wrapped in an `aria-live="polite"` region so screen readers announce when the crop view appears. Crop instructions rendered as visually subtle text and available to screen readers.
- **Focus management during view transitions:**
  - When crop view appears: focus moves to the crop area container (`tabindex="-1"` to make it focusable)
  - When Cancel is clicked: focus returns to the file input label
  - When Save completes and modal closes: focus returns to the modal trigger button (handled by the modal controller)
- **Crop area tab order:** Crop preview → Cancel button → Save button. Cropper.js supports arrow keys to move the crop area and +/- to zoom when the crop box is focused.
- **Crop buttons:** Cancel and Save meet 44px minimum touch targets. Labels from I18n (`image_upload.crop_cancel`, `image_upload.crop_save`).
- **Drag-and-drop:** Progressive enhancement only — the `<label>` + file input always works without drag-and-drop JavaScript.
- **Reduced motion:** Cropper.js does not use animations, so no `prefers-reduced-motion` concern.

### Progressive Enhancement (No JavaScript)

The upload form uses a standard `<form>` with a `<label>` + `<input type="file">`. Without JavaScript:
- The modal will not open (no `showModal()` call), but the form can be placed outside a modal as a standalone page
- Cropping is unavailable — the server-side Active Storage variant handles resizing
- Drag-and-drop is unavailable — the file input works natively
- This is documented as an acceptable degradation. Downstream projects requiring no-JS support should provide a standalone upload page as a fallback.

## Files

| File | Action | Purpose |
| ---- | ------ | ------- |
| `config/importmap.rb` | Modify | Pin cropperjs |
| `vendor/javascript/cropperjs.js` | Create (via pin) | Vendored Cropper.js |
| `vendor/assets/stylesheets/cropperjs.css` | Create | Vendored Cropper.js CSS |
| `app/javascript/controllers/image_cropper_controller.js` | Create | Cropper.js wrapper |
| `app/javascript/controllers/image_upload_controller.js` | Create | Upload coordinator |
| `app/views/shared/_image_upload_modal.html.erb` | Create | Reusable upload modal partial |
| `spec/system/image_upload_modal_spec.rb` | Create | System specs |

## Usage Examples

### Avatar upload (with cropping)

```erb
<%= render "shared/image_upload_modal",
      title: t("account.avatars.edit.title"),
      form_url: account_avatar_path,
      field_name: :avatar,
      current_image: @user.avatar.attached? ? @user.avatar : nil,
      placeholder: avatar_for(@user, size: :xl),
      remove_url: @user.avatar.attached? ? account_avatar_path : nil,
      crop: true, aspect_ratio: 1, max_width: 512, max_height: 512 %>
```

### Workspace logo (with cropping, different aspect ratio)

```erb
<%= render "shared/image_upload_modal",
      title: t("workspaces.branding.logo_title"),
      form_url: workspace_branding_path(@workspace),
      field_name: :logo,
      current_image: @workspace.logo.attached? ? @workspace.logo : nil,
      placeholder: content_tag(:div, @workspace.name[0], class: "w-32 h-32 ..."),
      remove_url: workspace_branding_path(@workspace),
      crop: true, aspect_ratio: 1, max_width: 256, max_height: 256 %>
```

### Simple document thumbnail (no cropping)

```erb
<%= render "shared/image_upload_modal",
      title: t("resources.upload_thumbnail"),
      form_url: resource_path(@resource),
      field_name: :thumbnail,
      current_image: @resource.thumbnail.attached? ? @resource.thumbnail : nil,
      crop: false %>
```

**Parameter notes:**
- `current_image` must be an Active Storage attachment (or nil), not a URL
- `placeholder` is raw HTML rendered when no image is attached
- `field_name` must match the model's `has_one_attached` name and the controller's `permit` list
- `form_url` must accept multipart form data (standard for Rails file uploads)

## Turbo Integration

### Form submission

The upload form submits via Turbo by default. The consuming controller should respond with:

```ruby
respond_to do |format|
  format.turbo_stream do
    render turbo_stream: [
      turbo_stream.replace("avatar-preview", partial: "account/avatars/preview"),
      turbo_stream.action(:dispatch, "modal:close")
    ]
  end
  format.html { redirect_to edit_account_profile_path, notice: t(".success") }
end
```

The `format.html` fallback handles non-Turbo requests (no-JS, direct form POST).

### Modal close after upload

The modal closes when the Turbo response arrives — either via a Turbo Stream action that dispatches a custom event, or via a redirect that causes Turbo to navigate away. The simplest approach: the controller redirects, Turbo performs a visit, and the page re-renders without the modal open.

## Testing Strategy

**System specs:**

- Modal opens with preview of current image
- Modal opens with placeholder when no image
- File selection via click triggers upload (no crop)
- File selection with crop enabled shows crop UI
- Crop Cancel returns to upload view
- Crop Save submits the form
- Remove button removes current image
- Invalid file type shows error
- Oversized file shows error
- Upload zone accepts drag-and-drop
- Focus moves to crop area when crop view appears
- Focus returns to upload zone on Cancel

**Request specs (for consuming controllers):**

Each controller that uses the image upload modal should have request specs verifying:
- Server-side validation rejects invalid content types (returns 422)
- Server-side validation rejects oversized files (returns 422)
- CSRF protection works (missing token returns 422)
- Unauthenticated requests are redirected
- Successful upload attaches the file and responds correctly
- Remove action purges the attachment

## Out of Scope

- Avatar-specific features (Gravatar, source selection, initials) — separate spec
- Workspace logo / banner variants — future consumers of this partial
- Image rotation/flip in cropper (Cropper.js supports it, not exposed in v1)
- Multiple file upload
