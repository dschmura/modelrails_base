# Turbo Frame Hub Refactor — Design Spec

**Goal:** Move the identity picker's hub view (source selection, preview, color picker, save) from JS state management to a server-rendered Turbo Frame. Keep the crop view client-side (Cropper.js). Reduce `identity_picker_controller.js` from ~548 lines to ~250.

**Scope:** Partial split, new `hub` controller actions + routes, JS controller simplification, form submission via native Turbo. No model/migration changes.

---

## Architecture

The identity picker modal has two views: **hub** (source selection) and **crop** (image editing). Currently both are managed by a 548-line Stimulus controller that handles state, DOM toggling, fetch calls, and error handling.

After this refactor:
- **Hub** is a `<turbo-frame>` whose content is rendered by a server `hub` action. Source card clicks are `link_to` requests that reload the frame. Save is a native `form_with` submission. The server is the single source of truth for hub state.
- **Crop** stays 100% client-side. Cropper.js, canvas blob export, and the `saveCrop` fetch are inherently client-side operations.

```
Modal opens
  → GET hub_account_avatar_path(source: current_source)
  → Server renders hub frame (preview + cards + color picker + save)

Click "Initials"
  → GET hub_account_avatar_path(source: "initials")
  → Server re-renders hub frame with initials preview + color picker visible

Click "Save & apply"
  → form_with PATCH /account/avatar (native Turbo submission)
  → Server responds with turbo_stream (update avatars, close modal, toast)

Click photo preview
  → JS switches to crop view (Cropper.js, stays client-side)

Click "Remove photo" (from crop view)
  → button_to DELETE /account/avatar (native Turbo submission)
  → Server responds with turbo_stream
```

---

## New Routes

```ruby
# config/routes.rb

# User avatar
namespace :account do
  resource :avatar, only: [ :update, :destroy ] do
    get :hub
  end
end

# Workspace branding
resource :branding, only: [ :edit, :update, :destroy ] do
  get :hub
end
```

- `GET /account/avatar/hub?source=initials` — renders hub frame for user
- `GET /workspaces/:slug/branding/hub?source=upload` — renders hub frame for workspace

---

## New Controller Actions

### `Account::AvatarsController#hub`

```ruby
def hub
  @user = Current.user
  authorize @user, policy_class: Account::AvatarPolicy

  @source = if params[:source].present? && @user.available_avatar_sources.include?(params[:source])
              params[:source]
            else
              @user.avatar_source
            end

  render partial: "shared/identity_picker_hub",
    locals: {
      model: @user,
      form_url: account_avatar_path,
      current_source: @source,
      has_color_picker: true,
      available_sources: @user.available_avatar_sources
    },
    layout: false
end
```

### `Workspaces::BrandingsController#hub`

Same pattern, using `@workspace` and workspace-specific locals (`has_color_picker: true`, `available_sources: @workspace.available_logo_sources`).

Both actions validate the requested source against the model's allowed sources — invalid source params fall back to the model's current source.

---

## Partial Split

### Current: one 400+ line partial

`app/views/shared/_identity_picker.html.erb` — contains hub view, crop view, file input, ARIA regions, everything.

### After: two partials

**`app/views/shared/_identity_picker.html.erb`** (~100 lines) — outer shell:
- Locals: `model:, form_url:, hub_title:, crop_title:, hub_url:`
- Hidden file input (for crop view)
- ARIA live region
- `<turbo-frame id="identity-picker-hub" src="<%= hub_url %>">` — initial hub load
- Crop view section (unchanged — JS-managed, `data-mode="crop"`)
- Crop footer (Cancel, Save crop, Upload new, Remove photo)

The turbo frame's `src` attribute triggers an initial GET to the `hub` action on modal open, loading the hub content server-side.

**`app/views/shared/_identity_picker_hub.html.erb`** (~150 lines) — hub content (inside the turbo frame):
- Locals: `model:, form_url:, current_source:, has_color_picker:, available_sources:`
- Wrapped in `<turbo-frame id="identity-picker-hub">`
- Large preview circle (correct one visible based on `current_source`)
- "PREVIEW" label + "Last updated" timestamp
- Source cards as `link_to` elements (styled as cards, pointing to `hub` action with `?source=X`)
- Color picker panel (rendered when `current_source == "initials" && has_color_picker`)
- `form_with` containing hidden fields (`avatar_source`, `primary_color`) + "Save & apply" submit button

Source cards are links, not radio buttons:
```erb
<%= link_to hub_account_avatar_path(source: "initials"),
      data: { turbo_frame: "identity-picker-hub" },
      class: "flex items-center gap-4 p-4 rounded-lg border-2 cursor-pointer ..." do %>
  <%# icon + title + description %>
<% end %>
```

Each click reloads the frame with the new source pre-selected by the server.

---

## Save & Apply — Native Turbo Form

The hub partial contains a `form_with`:

```erb
<%= form_with url: form_url, method: :patch, data: { turbo_frame: "_top" } do |f| %>
  <input type="hidden" name="avatar_source" value="<%= current_source %>">
  <input type="hidden" name="primary_color" value="<%= current_hue %>"
         data-identity-picker-target="colorField">
  <%= f.submit t("identity_picker.save"), class: "w-full ..." %>
<% end %>
```

`data: { turbo_frame: "_top" }` breaks out of the frame so the turbo stream response targets the whole page (updating avatar elements, closing modal, showing toast). Turbo handles:
- Fetch submission (no manual `fetch` needed)
- Button disabling during submission (no `_saving` guard needed)
- 422 error response rendering (no manual error handling needed)

---

## Remove Photo — Native Turbo Button

In the crop view footer, "Remove photo" changes from a JS `removePhoto()` call to:

```erb
<%= button_to t("identity_picker.remove_photo"),
      account_avatar_path,
      method: :delete,
      data: { turbo_frame: "_top" },
      class: "inline-flex items-center gap-1.5 text-sm text-danger ..." %>
```

The `destroy` action already returns turbo_stream (for workspace) or redirect (for user). This eliminates the entire `async removePhoto()` method.

**Note:** For User avatars, `AvatarsController#destroy` currently only does `redirect_to`. It needs a `format.turbo_stream` response added (matching workspace's `BrandingsController#destroy`).

---

## Source Card Click → File Picker (Photo + No Image)

Currently: clicking "Photo" when no image exists triggers `openFilePicker()` via JS.

After: the server renders the hub with `current_source: "upload"` and no image. The hub partial detects this state and includes a Stimulus data attribute:

```erb
<% if current_source == "upload" && !has_image %>
  <div data-controller="auto-file-picker"
       data-auto-file-picker-target-value="[data-identity-picker-target='fileInput']">
  </div>
<% end %>
```

A tiny Stimulus controller (`auto_file_picker_controller.js`, ~10 lines) triggers the file input click on connect. This replaces the `_autoOpenForSource` JS logic with a declarative pattern.

---

## Modal Size + Title

Currently: JS toggles `max-w-2xl` ↔ `max-w-4xl` and swaps the `<h2>` text.

After: The hub frame includes data attributes that a small Stimulus action reads:

```erb
<%# In the hub partial %>
<turbo-frame id="identity-picker-hub"
             data-action="turbo:frame-load->identity-picker#onHubLoad"
             data-modal-size="lg"
             data-modal-title="<%= hub_title %>">
```

When the frame loads, the `onHubLoad` callback reads these attributes and updates the modal panel's size class and title. This is ~10 lines of JS replacing the current `_toggleModalSize` and `_updateModalTitle` methods — but driven by server-rendered data attributes instead of JS state.

When entering crop view, the JS sets crop-specific size/title directly (same as now).

---

## JS Controller After Refactor (~250 lines)

### Deleted methods
- `selectSource`, `handleSourceChange`, `_selectSourceByValue` — server handles
- `_updatePreview`, `_updateCardStyles`, `_updateContextualControls` — server handles
- `_autoOpenForSource` — replaced by `auto_file_picker_controller`
- `removePhoto` async fetch — `button_to DELETE` handles
- `_saving` guard for hub save — Turbo handles
- `_saving` guard for removePhoto — Turbo handles

### Kept methods
- `openCrop` — switches to crop view, inits Cropper.js
- `saveCrop` — canvas blob export + fetch (must stay JS)
- `handleFileSelected` — file validation + crop view transition
- `handleColorChange` — live slider preview (instant feedback)
- `backToHub` — switches back to hub, releases pending file
- `_switchMode` — mode toggling (hub ↔ crop)
- `onHubLoad` — reads data attributes from frame load, sets modal size/title
- Escape/X interception — capture-phase `cancel` event handling
- `_manageFocus` — animation-aware focus management
- `_releasePendingFile`, `_toggleGifWarning`, `_announce`

### Deleted targets
- `sourceField` — hidden field now in the hub form (server-managed)
- `sourceCards` — cards are links in the frame (server-styled)
- `colorPanel` — server renders visibility
- `initialsPreview`, `photoPreview`, `gravPreview` — server renders correct preview
- `form` — form is in the hub frame (Turbo submits it)

### Kept targets
- `fileInput` — for programmatic file picker trigger
- `cropPreview` — for live crop preview in crop view
- `colorField` — for color slider sync (stays in JS for live preview)
- `colorSlider`, `colorHex` — color picker interaction
- `gifWarning` — GIF banner toggle

---

## New Stimulus Controller: `auto_file_picker_controller.js` (~10 lines)

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { target: String }

  connect() {
    const input = document.querySelector(this.targetValue)
    if (input) setTimeout(() => input.click(), 0)
  }
}
```

Declarative alternative to `_autoOpenForSource`. The server renders this controller's element when Photo is selected with no image. On connect, it triggers the file input. Clean separation of concern.

---

## Files Summary

### Files to create
- `app/views/shared/_identity_picker_hub.html.erb` — hub content partial
- `app/javascript/controllers/auto_file_picker_controller.js` — file picker trigger

### Files to modify
- `app/views/shared/_identity_picker.html.erb` — slim down to outer shell + turbo frame + crop view
- `app/javascript/controllers/identity_picker_controller.js` — remove hub state management, add `onHubLoad`
- `app/controllers/account/avatars_controller.rb` — add `hub` action, add turbo_stream to `destroy`
- `app/controllers/workspaces/brandings_controller.rb` — add `hub` action
- `config/routes.rb` — add `hub` member routes
- `app/views/account/profiles/edit.html.erb` — pass `hub_url` to identity picker
- `app/views/workspaces/brandings/edit.html.erb` — pass `hub_url` to identity picker

### Files unchanged
- `app/javascript/controllers/image_cropper_controller.js` — crop view untouched
- `app/models/` — no model changes
- `app/policies/` — no policy changes (hub uses existing `update?`)
- `app/assets/` — no CSS changes

### Files potentially deleted
- None deleted — the outer shell partial is rewritten, not replaced

---

## Testing Strategy

- **Request specs:** TDD for `hub` action (renders hub frame, validates source param, handles invalid source)
- **Request specs:** Add `format.turbo_stream` test for `AvatarsController#destroy`
- **System specs:** Existing specs should mostly pass — behavior is the same, just the plumbing changed. Some may need adjustment for the link-based source cards vs radio buttons.
- **Full suite after each task**

## Edge case: Remove Photo from crop view

The "Remove photo" `button_to DELETE` is in the crop view footer — outside the hub turbo frame. When the delete succeeds, the server's turbo stream response should:
1. Replace the hub frame content (showing initials preview, source cards with Initials selected)
2. Append a `modal-closer` div to close the modal (matching the current pattern)
3. Show a success toast

The crop view itself doesn't need explicit JS to transition back — the modal closes via the turbo stream response. If the user opens the modal again, the hub frame reloads fresh from the server with `logo_source: "initials"`.

## Edge case: saveCrop success → hub reload

After `saveCrop` succeeds (blob exported, fetch returns), the JS currently switches to hub mode and updates state. After the refactor, the turbo stream response from `update` replaces the hub frame content (with the new photo preview) AND appends `modal-closer` to close the modal. The JS `saveCrop` method still needs to handle the fetch and blob construction, but can delegate the post-save UI updates to the turbo stream — no more manual `_switchMode("hub")`, `_updatePreview()`, `_updateCardStyles()`.

The `saveCrop` method shrinks to: export blob → construct FormData → fetch → let Turbo handle the response.

---

## What this does NOT cover

- Crop view refactoring (stays as-is)
- JS i18n for remaining hardcoded strings (separate concern)
- N+1 fixes (separate concern)
- Color slider moving to a server-rendered component (stays JS for instant feedback)
