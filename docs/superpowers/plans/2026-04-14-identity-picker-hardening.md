# Identity Picker Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use TDD (write failing test → implement → pass → commit).

**Goal:** Fix critical correctness bugs, missing validations, silent error swallowing, and UX gaps found in the identity picker security/quality audit.

**Architecture:** TDD hardening pass. Each task writes failing tests first, implements the minimum fix, verifies green, then commits. Tasks are ordered so Ruby/model changes come before JS changes that depend on them.

**Tech Stack:** Rails 8.1 (RSpec request/model specs), Stimulus controllers, Active Storage, Turbo Streams

**Branch:** `feature/identity-picker` (worktree at `.worktrees/identity-picker`)

**Important:** All commands in worktree use `mise exec --` prefix.

---

## File Structure

### Files to modify

- `app/models/workspace.rb` — add content_type + size validations for `logo` and `logo_original`
- `app/controllers/account/avatars_controller.rb` — JSON rescue, coord validation, turbo stream error responses, explicit remove action
- `app/controllers/workspaces/brandings_controller.rb` — accept `avatar`/`avatar_original` keys (matching JS), JSON rescue, coord validation, turbo stream error responses, explicit remove action
- `app/views/shared/_identity_picker.html.erb` — use `avatar_original` URL when re-cropping (image_url for crop view)
- `app/javascript/controllers/identity_picker_controller.js` — double-click guard, try/catch, error handling, URL revoke, remove persists to server

### Test files to create/modify

- `spec/models/workspace_spec.rb` — add attachment validation tests
- `spec/requests/account/avatars_spec.rb` — add error response + coord validation + JSON rescue tests
- `spec/requests/workspaces/brandings_spec.rb` — add error response + coord validation + JSON rescue tests + saveCrop path test

---

### Task H1: Workspace logo validations

**Goal:** Workspace `logo` and `logo_original` currently have ZERO validation. Curl bypasses client. Add content_type + size validation to match User#avatar.

**Files:**
- Modify: `app/models/workspace.rb`
- Test: `spec/models/workspace_spec.rb`

- [ ] **Step 1: Write failing tests**

Add to `spec/models/workspace_spec.rb` (create file if needed) these examples inside `RSpec.describe Workspace, type: :model do`:

```ruby
describe "logo attachment" do
  let(:workspace) { create(:workspace) }
  let(:valid_png) { fixture_file_upload("spec/fixtures/files/test_avatar.png", "image/png") }
  let(:invalid_type) { Rack::Test::UploadedFile.new(StringIO.new("not an image"), "application/pdf", original_filename: "doc.pdf") }
  let(:oversized) { Rack::Test::UploadedFile.new(StringIO.new("a" * 6.megabytes), "image/png", original_filename: "big.png") }

  it "accepts valid PNG up to 5MB" do
    workspace.logo.attach(valid_png)
    expect(workspace).to be_valid
  end

  it "rejects non-image content types" do
    workspace.logo.attach(invalid_type)
    expect(workspace).not_to be_valid
    expect(workspace.errors[:logo]).to be_present
  end

  it "rejects files over 5MB" do
    workspace.logo.attach(oversized)
    expect(workspace).not_to be_valid
    expect(workspace.errors[:logo]).to be_present
  end
end

describe "logo_original attachment" do
  let(:workspace) { create(:workspace) }
  let(:invalid_type) { Rack::Test::UploadedFile.new(StringIO.new("not an image"), "application/pdf", original_filename: "doc.pdf") }
  let(:oversized) { Rack::Test::UploadedFile.new(StringIO.new("a" * 11.megabytes), "image/png", original_filename: "big.png") }

  it "rejects non-image content types" do
    workspace.logo_original.attach(invalid_type)
    expect(workspace).not_to be_valid
    expect(workspace.errors[:logo_original]).to be_present
  end

  it "rejects files over 10MB (original can be larger than cropped)" do
    workspace.logo_original.attach(oversized)
    expect(workspace).not_to be_valid
    expect(workspace.errors[:logo_original]).to be_present
  end
end
```

Note: If `test_avatar.png` doesn't exist in fixtures, check `spec/fixtures/files/` and use whatever PNG fixture exists. If none, the test will need to create a minimal valid PNG inline.

- [ ] **Step 2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/models/workspace_spec.rb --format documentation
```

Expected: FAIL — no validations exist yet.

- [ ] **Step 3: Add validations to Workspace model**

In `app/models/workspace.rb`, find the existing `has_one_attached :logo` lines and add validations below them (match the pattern used in `app/models/user.rb`):

```ruby
has_one_attached :logo
has_one_attached :logo_original

validates :logo,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 5.megabytes }

validates :logo_original,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 10.megabytes }
```

Rationale: `logo_original` allows 10MB (double the cropped) since originals can be larger — but still bounded.

- [ ] **Step 4: Run tests to verify they pass**

```bash
mise exec -- bundle exec rspec spec/models/workspace_spec.rb --format documentation
```

Expected: PASS — all new validation tests green.

- [ ] **Step 5: Run full test suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: 920 (or more) examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/models/workspace.rb spec/models/workspace_spec.rb
git commit -m "feat: validate workspace logo content type and size"
```

---

### Task H2: Controller input validation — JSON rescue + coord shape

**Goal:** `JSON.parse(params[:crop_coordinates])` currently raises 500 on malformed input. Also, parsed coords are stored to blob metadata without validation — could pollute with arbitrary content.

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Test: `spec/requests/account/avatars_spec.rb`
- Test: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Write failing tests**

In `spec/requests/account/avatars_spec.rb`, add inside the existing `describe "PATCH /account/avatar"` block:

```ruby
context "with malformed crop_coordinates" do
  let(:valid_avatar) { fixture_file_upload("spec/fixtures/files/test_avatar.png", "image/png") }

  it "ignores malformed JSON without crashing" do
    patch account_avatar_path, params: {
      avatar: valid_avatar,
      crop_coordinates: "not-valid-json{",
      avatar_source: "upload"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
  end

  it "ignores coords missing required keys" do
    patch account_avatar_path, params: {
      avatar: valid_avatar,
      crop_coordinates: '{"foo":"bar"}',
      avatar_source: "upload"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    user.reload
    expect(user.avatar_original.blob.metadata["crop"]).to be_nil
  end

  it "stores coords when they have the expected shape" do
    patch account_avatar_path, params: {
      avatar: valid_avatar,
      avatar_original: valid_avatar,
      crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}',
      avatar_source: "upload"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    user.reload
    expect(user.avatar_original.blob.metadata["crop"]).to eq({ "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
  end
end
```

In `spec/requests/workspaces/brandings_spec.rb`, add an analogous block testing the same behavior for brandings.

- [ ] **Step 2: Run tests to verify they fail**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: FAIL — malformed JSON currently raises, or test expects behavior not yet implemented.

- [ ] **Step 3: Add safe parse helper to AvatarsController**

In `app/controllers/account/avatars_controller.rb`, find the line that does `JSON.parse(params[:crop_coordinates])` (around line 18). Replace with safer parsing:

```ruby
coords = safe_parse_coordinates(params[:crop_coordinates])
if coords
  blob = user.avatar_original.blob
  blob.update!(metadata: blob.metadata.merge("crop" => coords))
end
```

Add this private method at the bottom of the controller (inside the class, below existing methods):

```ruby
private

def safe_parse_coordinates(raw)
  return nil if raw.blank?

  parsed = JSON.parse(raw)
  return nil unless parsed.is_a?(Hash)
  return nil unless %w[x y w h].all? { |k| parsed[k].is_a?(Numeric) }

  parsed.slice("x", "y", "w", "h")
rescue JSON::ParserError
  nil
end
```

(Place the `private` keyword above the method only if it's not already in a private section. If there's already a `private` or other private methods, just add this method alongside them.)

- [ ] **Step 4: Add same safe parse helper to BrandingsController**

In `app/controllers/workspaces/brandings_controller.rb`, replace the equivalent `JSON.parse` line with:

```ruby
coords = safe_parse_coordinates(params[:crop_coordinates])
if coords
  blob = @workspace.logo_original.blob
  blob.update!(metadata: blob.metadata.merge("crop" => coords))
end
```

And add the same private `safe_parse_coordinates` method.

(This duplication will be acceptable for now; if we find more shared behavior across these controllers in the future, it can move to a concern. For two controllers, a shared concern is YAGNI.)

- [ ] **Step 5: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/account/avatars_controller.rb app/controllers/workspaces/brandings_controller.rb spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb
git commit -m "fix: safely parse crop_coordinates and validate shape"
```

---

### Task H3: Turbo stream error responses

**Goal:** When `user.save` or `@workspace.save` fails during avatar/logo update, the current code redirects with a flash. The JS fetch follows the redirect and receives the full HTML page as a 200, treating it as Turbo Stream — appears to succeed while silently failing. Add proper turbo_stream error responses.

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Create: `app/views/shared/_identity_picker_error.html.erb` (or similar) — a turbo stream partial for displaying errors
- Test: `spec/requests/account/avatars_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/requests/account/avatars_spec.rb`:

```ruby
context "when save fails" do
  before do
    # Force user save to fail — simplest: stub the model to be invalid
    allow_any_instance_of(User).to receive(:save).and_return(false)
    allow_any_instance_of(User).to receive_message_chain(:errors, :full_messages).and_return(["Avatar is invalid"])
  end

  let(:valid_avatar) { fixture_file_upload("spec/fixtures/files/test_avatar.png", "image/png") }

  it "returns a 422 turbo stream response with error, not a redirect" do
    patch account_avatar_path, params: {
      avatar: valid_avatar,
      avatar_source: "upload"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
  end
end
```

- [ ] **Step 2: Run test to verify failure**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb --format documentation
```

Expected: FAIL — current code does `redirect_to`, not a 422 turbo stream.

- [ ] **Step 3: Update AvatarsController save-failure path**

In `app/controllers/account/avatars_controller.rb`, find the `else` branch where `user.save` fails (around lines 46-49) and replace:

```ruby
else
  user.avatar.purge if params[:avatar].present?
  user.avatar_original.purge if params[:avatar_original].present?
  redirect_to edit_account_profile_path, alert: user.errors.full_messages.to_sentence
end
```

With:

```ruby
else
  user.avatar.purge if params[:avatar].present?
  user.avatar_original.purge if params[:avatar_original].present?
  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.replace(
        "flash",
        partial: "shared/flash",
        locals: { alert: user.errors.full_messages.to_sentence }
      ), status: :unprocessable_content
    end
    format.html { redirect_to edit_account_profile_path, alert: user.errors.full_messages.to_sentence }
  end
end
```

Check whether `shared/flash` partial exists. If not, fall back to rendering an inline turbo stream with plain error text:

```ruby
render turbo_stream: turbo_stream.append(
  "body",
  "<div data-controller=\"toast\" data-toast-variant-value=\"error\">#{CGI.escapeHTML(user.errors.full_messages.to_sentence)}</div>".html_safe
), status: :unprocessable_content
```

Use whichever pattern the project already uses for flash/toast display.

- [ ] **Step 4: Update BrandingsController save-failure path**

In `app/controllers/workspaces/brandings_controller.rb`, find the corresponding save-failure branch and apply the same pattern — return a turbo_stream with 422 status.

- [ ] **Step 5: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/account/avatars_controller.rb app/controllers/workspaces/brandings_controller.rb spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb
git commit -m "fix: return turbo stream error on avatar save failure"
```

---

### Task H4: Fix workspace param name mismatch

**Goal:** JS sends FormData keys `avatar`/`avatar_original` for both User and Workspace flows. BrandingsController reads `params[:logo]`/`params[:logo_original]`. They never match → workspace logo saves silently no-op through the crop flow.

**Files:**
- Modify: `app/controllers/workspaces/brandings_controller.rb` — accept `avatar`/`avatar_original` keys (same as avatars controller)
- Test: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/requests/workspaces/brandings_spec.rb`:

```ruby
context "when cropped image is sent via JS saveCrop path" do
  let(:valid_png) { fixture_file_upload("spec/fixtures/files/test_avatar.png", "image/png") }

  it "accepts 'avatar' param and attaches as logo" do
    patch workspace_branding_path(workspace), params: {
      avatar: valid_png,
      avatar_original: valid_png,
      avatar_source: "upload",
      crop_coordinates: '{"x":0,"y":0,"w":100,"h":100}'
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    workspace.reload
    expect(workspace.logo).to be_attached
    expect(workspace.logo_original).to be_attached
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: FAIL — logo is not attached because params[:logo] is nil.

- [ ] **Step 3: Update BrandingsController to accept avatar/avatar_original**

In `app/controllers/workspaces/brandings_controller.rb`, change the attachment logic to read from `params[:avatar]` and `params[:avatar_original]` (matching what JS sends), while still supporting `params[:logo]` as a fallback for the regular HTML form submit:

```ruby
# JS saveCrop sends "avatar"/"avatar_original" to match User flow —
# accept those as aliases for logo/logo_original
cropped = params[:avatar] || params[:logo]
original = params[:avatar_original] || params[:logo_original]

@workspace.logo.attach(cropped) if cropped
@workspace.logo_original.attach(original) if original
```

(Adjust variable names to match the existing code style in the controller.)

- [ ] **Step 4: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/workspaces/brandings_controller.rb spec/requests/workspaces/brandings_spec.rb
git commit -m "fix: BrandingsController accepts avatar param from saveCrop"
```

---

### Task H5: JS saveCrop hardening

**Goal:** Add in-flight guard (no double-click), try/catch (handle network failure), proper error response handling (show error on 422), and object URL revoke.

**Files:**
- Modify: `app/javascript/controllers/identity_picker_controller.js`

- [ ] **Step 1: Add in-flight guard, try/catch, and error handling to `saveCrop`**

Find the current `saveCrop` method in `identity_picker_controller.js`. Replace the entire method with:

```javascript
async saveCrop() {
  // In-flight guard — prevent double-click duplicate uploads
  if (this._saving) return
  this._saving = true

  try {
    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (!cropperEl) return

    const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
    if (!cropper) return

    const result = await cropper.exportCrop()
    if (!result) return

    const { blob, coordinates } = result

    const formData = new FormData()
    formData.append("avatar", blob, "cropped-avatar.png")

    if (this._pendingFile) {
      formData.append("avatar_original", this._pendingFile)
    }

    formData.append("avatar_source", "upload")
    formData.append("crop_coordinates", JSON.stringify(coordinates))

    // Add CSRF token
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    }

    const response = await fetch(this.formUrlValue, {
      method: "PATCH",
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      body: formData,
      redirect: "manual"  // don't auto-follow redirects — we want to know if the server redirected
    })

    // Server-side validation failed — render error turbo stream and stay on crop view
    if (response.status === 422) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
      this._announce("Upload failed. Please try again.")
      return
    }

    // Any other non-OK (network, auth, etc.) — show error and stay
    if (!response.ok && response.type !== "opaqueredirect") {
      this._announce("Upload failed. Please try again.")
      return
    }

    // Success: render turbo stream, update state, return to hub
    if (response.ok) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
    }

    // Release any pending file and its object URL
    this._releasePendingFile()

    this.hasImageValue = true
    this.currentSourceValue = "upload"
    this.sourceFieldTarget.value = "upload"

    // Update the photo preview button with the cropped image
    if (this.hasPhotoPreviewTarget) {
      const previewImg = this.photoPreviewTarget.querySelector("img")
      if (previewImg && this.hasCropPreviewTarget && this.cropPreviewTarget.src) {
        previewImg.src = this.cropPreviewTarget.src
      }
    }

    this._switchMode("hub")
    this._updatePreview()
    this._updateContextualControls()
    this._updateCardStyles()
  } catch (error) {
    console.error("saveCrop failed:", error)
    this._announce("Upload failed. Please check your connection and try again.")
  } finally {
    this._saving = false
  }
}
```

- [ ] **Step 2: Add `_releasePendingFile` helper**

Find the private section and add this method alongside `_announce`:

```javascript
_releasePendingFile() {
  if (this._pendingObjectUrl) {
    URL.revokeObjectURL(this._pendingObjectUrl)
    this._pendingObjectUrl = null
  }
  this._pendingFile = null
}
```

- [ ] **Step 3: Track the object URL in `handleFileSelected`**

Find `handleFileSelected` and update to track the object URL. Find:

```javascript
this._pendingFile = file
const objectUrl = URL.createObjectURL(file)
```

Replace with:

```javascript
// Release any prior pending file/URL before creating a new one
this._releasePendingFile()

this._pendingFile = file
this._pendingObjectUrl = URL.createObjectURL(file)
const objectUrl = this._pendingObjectUrl
```

- [ ] **Step 4: Update `backToHub` to release pending file**

Find the `backToHub` method and replace:

```javascript
backToHub() {
  this._pendingFile = null
  this._switchMode("hub")
}
```

With:

```javascript
backToHub() {
  this._releasePendingFile()
  this._switchMode("hub")
}
```

- [ ] **Step 5: Run full test suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All tests pass (no Ruby changes in this task — just confirming nothing broke).

- [ ] **Step 6: Manual browser verification**

Open the modal, select a photo, double-click "Save crop" fast — should only send one request. Disconnect network, click "Save crop" — should show error message and stay on crop view. Cancel from crop view — should not leak memory (verify in DevTools → Memory).

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/identity_picker_controller.js
git commit -m "fix: harden saveCrop with guard, error handling, and URL cleanup"
```

---

### Task H6: Persist removePhoto immediately

**Goal:** "Remove photo" button in crop view currently only updates client state. If user navigates away without pressing Save, nothing actually changes on server. Send PATCH immediately.

**Files:**
- Modify: `app/javascript/controllers/identity_picker_controller.js`
- Test: `spec/requests/account/avatars_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/requests/account/avatars_spec.rb`:

```ruby
context "remove photo (avatar_source=initials + no avatar param)" do
  before do
    user.avatar.attach(fixture_file_upload("spec/fixtures/files/test_avatar.png", "image/png"))
    user.avatar_original.attach(fixture_file_upload("spec/fixtures/files/test_avatar.png", "image/png"))
    user.update!(avatar_source: "upload")
  end

  it "purges avatar attachments and switches source to initials" do
    patch account_avatar_path, params: {
      avatar_source: "initials"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    user.reload
    expect(user.avatar).not_to be_attached
    expect(user.avatar_original).not_to be_attached
    expect(user.avatar_source).to eq("initials")
  end
end
```

Check existing controller logic — if source change already triggers purge, this test may already pass. If not, adjust controller:

In `avatars_controller.rb`, when `params[:avatar_source] == "initials"` and source is changing from upload, purge attachments. Check existing behavior first.

- [ ] **Step 2: Run test to verify current behavior**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb --format documentation
```

If it already passes, skip to Step 4 (JS change). If it fails, continue:

- [ ] **Step 3: Ensure controller purges avatars on source change (if needed)**

Check the existing avatars controller's source-change path. Ensure it purges attachments when switching away from upload. If the test fails, add the purge logic.

- [ ] **Step 4: Update JS `removePhoto` to fetch**

Find the `removePhoto` method in `identity_picker_controller.js`. Replace:

```javascript
removePhoto() {
  this.hasImageValue = false
  this.currentSourceValue = "initials"
  this.sourceFieldTarget.value = "initials"
  this._switchMode("hub")
  this._updatePreview()
  this._updateContextualControls()
}
```

With:

```javascript
async removePhoto() {
  if (this._saving) return
  this._saving = true

  try {
    const formData = new FormData()
    formData.append("avatar_source", "initials")

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    }

    const response = await fetch(this.formUrlValue, {
      method: "PATCH",
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      body: formData
    })

    if (response.ok) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
    }

    this._releasePendingFile()
    this.hasImageValue = false
    this.currentSourceValue = "initials"
    this.sourceFieldTarget.value = "initials"
    this._switchMode("hub")
    this._updatePreview()
    this._updateContextualControls()
    this._updateCardStyles()
  } catch (error) {
    console.error("removePhoto failed:", error)
    this._announce("Failed to remove photo. Please try again.")
  } finally {
    this._saving = false
  }
}
```

- [ ] **Step 5: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/identity_picker_controller.js app/controllers/account/avatars_controller.rb spec/requests/account/avatars_spec.rb
git commit -m "fix: removePhoto persists to server immediately"
```

---

### Task H7: Re-crop uses avatar_original

**Goal:** When user clicks photo preview to re-crop, the crop view currently loads the resized `avatar` variant. Re-cropping progressively degrades quality. Use `avatar_original` instead.

**Files:**
- Modify: `app/views/shared/_identity_picker.html.erb`

- [ ] **Step 1: Update image_url logic in partial**

In `_identity_picker.html.erb`, find the top where local variables are computed. The current code sets `image_url` to `url_for(model.avatar)` (or `model.logo`).

Change to compute BOTH URLs — the display URL (resized) for the hub preview, and the original URL for the crop view:

Replace:

```erb
image_url = if is_user && model.avatar.attached?
             url_for(model.avatar)
           elsif !is_user && model.logo.attached?
             url_for(model.logo)
           end
```

With:

```erb
# URL for the hub preview circle (resized/cropped variant)
display_url = if is_user && model.avatar.attached?
                url_for(model.avatar)
              elsif !is_user && model.logo.attached?
                url_for(model.logo)
              end

# URL for re-crop — use original so quality isn't progressively degraded
original_url = if is_user && model.avatar_original.attached?
                 url_for(model.avatar_original)
               elsif !is_user && model.logo_original.attached?
                 url_for(model.logo_original)
               else
                 display_url  # fallback if original is missing
               end
```

Then find usages of `image_url`:
- In the hub photo preview `<img>` — use `display_url`
- In the crop view `cropper-container` `<img>` — use `original_url`

- [ ] **Step 2: Run tests**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass.

- [ ] **Step 3: Manual browser check**

Upload an image, save crop, re-open modal, click photo preview (re-crop). The image loaded in the crop view should be the original full resolution, not the already-cropped variant.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_identity_picker.html.erb
git commit -m "fix: re-crop loads avatar_original to preserve quality"
```

---

### Task H8: Full suite verification

- [ ] **Step 1: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All green (should be 920+ examples, new tests bring count up).

- [ ] **Step 2: Manual browser check of all hardened flows**

1. Upload image, double-click Save crop rapidly → only one upload
2. Upload image, disconnect network, click Save crop → error message, stays on crop view
3. Cancel from crop view → no memory leak (check DevTools)
4. Upload, save, re-open, click photo preview → loads original resolution for re-crop
5. Upload, switch to Initials, click Remove photo → server is updated immediately (verify by reopening modal or checking user.avatar.attached?)
6. Send malformed crop_coordinates via devtools → no 500
7. Attempt to PATCH avatar with oversized file → validation error, turbo stream shows error

- [ ] **Step 3: Commit any remaining fixes needed**

If manual verification surfaces issues, fix them and commit before moving on.
