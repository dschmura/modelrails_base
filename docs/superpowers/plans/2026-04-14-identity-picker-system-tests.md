# Identity Picker System Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 11 browser-level system specs covering the identity picker's end-to-end flows — upload/crop/save, source switching, re-crop, photo removal, modal navigation, double-click guard, and keyboard source selection.

**Architecture:** Tests use the existing Playwright/Capybara setup. A new shared helpers module (`spec/support/identity_picker_helpers.rb`) provides reusable primitives: sign-in via form, opening the modal, attaching files to the sr-only input, simulating crop adjustments via Cropper.js JS API, and waiting for view transitions. Tests hit the real ERB pages, not injected HTML. Cropper.js gestures are simulated via controller API calls rather than synthetic pointer events.

**Tech Stack:** RSpec, Capybara + Playwright (headless Chromium), Stimulus, Cropper.js v2, FactoryBot.

**Spec:** `docs/superpowers/specs/2026-04-14-identity-picker-system-tests-design.md`

**Important:** All commands in this worktree must use `mise exec --` prefix (e.g., `mise exec -- bundle exec rspec`).

---

## Scope Check

Single cohesive test suite. 11 specs across 2 files + 1 helpers module. No decomposition needed.

---

## File Structure

### Files to create

- `spec/support/identity_picker_helpers.rb` — shared test helpers for identity picker system specs
- `spec/system/account/profiles_spec.rb` — 9 specs for the user profile page's identity picker
- `spec/system/workspaces/brandings_spec.rb` — 2 specs for the workspace branding page's identity picker

### Files to modify

- None (no production code changes — we are adding tests for existing behavior)

---

## Background: What tests are validating

Each spec exercises behavior that was implemented earlier in this branch. Most tests should pass on first write. If a test fails, investigate:

1. Is the test wrong (wrong selector, wrong assertion)?
2. Is there a subtle bug in the production code that the test correctly caught?

Only fix production code if option 2 is true. Do not weaken a test to make it pass.

---

### Task 1: Create the shared helpers module and directory structure

**Files:**

- Create: `spec/support/identity_picker_helpers.rb`
- Create directories: `spec/system/account/` and `spec/system/workspaces/`

- [ ] **Step 1: Create the directories**

```bash
mkdir -p spec/system/account spec/system/workspaces
```

- [ ] **Step 2: Create the helpers module**

Create `spec/support/identity_picker_helpers.rb` with exactly this content:

```ruby
# frozen_string_literal: true

# Shared helpers for identity picker system specs (user avatar + workspace logo).
# Tests hit the real rendered pages. Cropper.js gestures are simulated via the
# controller's JS API rather than synthetic pointer events (flakier and slower).
module IdentityPickerHelpers
  # Sign in a user via the real login form (fills email, continues, fills password, submits).
  # Works in system specs where the session cookie must live in the Playwright browser,
  # not the Rack::Test cookie jar.
  def sign_in_via_form(user, password: "SecureP@ssw0rd123!")
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  # Open the identity picker modal from a profile or branding edit page.
  # Both pages place the trigger inside a [data-controller="modal"] container.
  def open_identity_picker
    find("[data-controller='modal'] button[data-action*='modal#open']", match: :first).click
    expect(page).to have_css("dialog[open]", wait: 3)
  end

  # Click a source card by the visible title text ("Photo", "Gravatar", "Initials").
  # Uses the label element — that's where the click action is bound.
  def select_identity_source(title)
    within("[data-identity-picker-target='sourceCards']") do
      find("label", text: title).click
    end
  end

  # Attach a file to the identity picker's hidden file input.
  # The input has the sr-only class, so Capybara must be told visible: false.
  def attach_identity_picker_file(path)
    input = page.find("input[data-identity-picker-target='fileInput']", visible: false)
    input.attach_file(path)
  end

  # Simulate a crop adjustment by calling Cropper.js v2 selection API via JS.
  # Moves the selection 10px right + 10px down. Does NOT use synthetic pointer events.
  def simulate_crop_adjustment
    page.execute_script(<<~JS)
      const cropperEl = document.querySelector("[data-controller='image-cropper']")
      const app = window.Stimulus
      const ctrl = app.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      const selection = ctrl._cropper.getCropperSelection()
      selection.$move(10, 10)
    JS
  end

  # Update the OKLCH hue slider value via JS and dispatch the input event
  # so the Stimulus controller re-renders the preview and updates the hidden field.
  def set_identity_color_hue(hue)
    page.execute_script(<<~JS)
      const slider = document.querySelector("[data-identity-picker-target='colorSlider']")
      slider.value = #{hue}
      slider.dispatchEvent(new Event('input', { bubbles: true }))
    JS
  end

  # Wait for crop view to become visible. Cropper.js v2 renders Web Components
  # (cropper-canvas) after initialization — waiting on that guarantees ready-to-act.
  def wait_for_crop_view
    expect(page).to have_css("[data-mode='crop']:not([hidden])", wait: 3)
    expect(page).to have_css("cropper-canvas", wait: 3)
  end

  # Wait for hub view to become visible (after a mode switch back to hub).
  def wait_for_hub_view
    expect(page).to have_css("[data-mode='hub']:not([hidden])", wait: 3)
  end
end

RSpec.configure do |config|
  config.include IdentityPickerHelpers, type: :system
end
```

- [ ] **Step 3: Verify rails_helper auto-loads support files**

Check the existing behavior — the project should auto-require `spec/support/**/*.rb`. Run:

```bash
grep -n "support.*rb" spec/rails_helper.rb
```

Expected output includes a line like `Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }` OR `Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }`.

If present: helpers will auto-load. Move to Step 4.

If absent: add this line inside `RSpec.configure do |config|` in `spec/rails_helper.rb`:

```ruby
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }
```

- [ ] **Step 4: Verify the helpers module loads cleanly**

Run any existing system spec:

```bash
mise exec -- bundle exec rspec spec/system/sign_up_spec.rb
```

Expected: the spec passes (1 example, 0 failures). Our new helpers module should load silently as part of support/ autoload.

- [ ] **Step 5: Commit**

```bash
git add spec/support/identity_picker_helpers.rb
git commit -m "test: add identity picker system test helpers"
```

(If `spec/system/account/` or `spec/system/workspaces/` are empty directories they won't appear in git. They'll be populated by later tasks.)

---

### Task 2: Spec — upload photo, crop, save

**Files:**

- Create: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Write the spec**

Create `spec/system/account/profiles_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe "Account profile — identity picker", type: :system do
  let(:user) { create(:user) }
  let(:avatar_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_account_profile_path
  end

  describe "photo upload flow" do
    it "uploads, crops, and saves a new avatar" do
      open_identity_picker

      # Select Photo source — since no image exists yet, this opens the file picker
      select_identity_source("Photo")

      attach_identity_picker_file(avatar_fixture)

      # File select triggers crop view automatically
      wait_for_crop_view

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      # After save, modal returns to hub
      wait_for_hub_view

      # Server-side state: avatar and avatar_original both attached, source is upload
      user.reload
      expect(user.avatar).to be_attached
      expect(user.avatar_original).to be_attached
      expect(user.avatar_source).to eq("upload")
    end
  end
end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "uploads, crops, and saves"
```

Expected: PASS (1 example, 0 failures).

If it fails, common causes:

- **Modal doesn't open:** check that the profile page's avatar trigger button exists — it may have a different selector. Inspect the page via screenshot.
- **File picker doesn't open crop view:** the `identity_picker_controller` opens the picker via `setTimeout` — ensure the crop view transition has enough wait time.
- **Save crop hangs:** the controller uses fetch; check that the turbo_stream response is rendering correctly.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for avatar upload, crop, and save"
```

---

### Task 3: Spec — switch to Initials with custom color

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

Inside the `RSpec.describe "Account profile — identity picker"` block, after the existing `describe "photo upload flow"` block, add:

```ruby
  describe "source switching" do
    it "switches to Initials with a custom color" do
      open_identity_picker

      select_identity_source("Initials")

      # Color picker panel should appear (User has has_color_picker: true)
      expect(page).to have_css("[data-identity-picker-target='colorPanel']:not([hidden])", wait: 2)

      set_identity_color_hue(120)  # green

      click_button I18n.t("identity_picker.save")

      # Modal closes on save & apply
      expect(page).to have_no_css("dialog[open]", wait: 3)

      user.reload
      expect(user.avatar_source).to eq("initials")
      expect(user.primary_color).to eq(120)
    end
  end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "switches to Initials"
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for switching avatar source to Initials with color"
```

---

### Task 4: Spec — switch to Gravatar

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

Inside the `describe "source switching"` block (added in Task 3), add a second `it` block:

```ruby
    it "switches to Gravatar" do
      open_identity_picker

      select_identity_source("Gravatar")

      # No color picker for Gravatar
      expect(page).to have_css("[data-identity-picker-target='colorPanel'][hidden]", wait: 2)

      click_button I18n.t("identity_picker.save")

      # Modal closes on save & apply
      expect(page).to have_no_css("dialog[open]", wait: 3)

      user.reload
      expect(user.avatar_source).to eq("gravatar")
    end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "switches to Gravatar"
```

Expected: PASS. If the user's `available_avatar_sources` doesn't include "gravatar" by default, the test will fail because the Gravatar card won't be in the DOM. If so, inspect `User#available_avatar_sources` and update the test's setup (e.g., create the user with an email that is explicitly Gravatar-enabled, or stub `available_avatar_sources` to return a specific list).

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for switching avatar source to Gravatar"
```

---

### Task 5: Spec — re-crop existing photo uses avatar_original

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

Inside the `RSpec.describe` block, after the `describe "source switching"` block, add:

```ruby
  describe "re-crop existing photo" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "loads avatar_original for re-crop and saves a new blob" do
      original_key = user.avatar_original.blob.key
      prior_avatar_key = user.avatar.blob.key

      open_identity_picker

      # Click the large photo preview to enter crop view
      find("button[data-identity-picker-target='photoPreview']").click

      wait_for_crop_view

      # Crop view image src should contain the avatar_original blob key (not the avatar's)
      img_src = page.evaluate_script(
        "document.querySelector('.cropper-container img').getAttribute('src')"
      )
      expect(img_src).to include(original_key)

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      wait_for_hub_view

      user.reload
      expect(user.avatar).to be_attached
      # New crop save creates a new avatar blob (different key than before)
      expect(user.avatar.blob.key).not_to eq(prior_avatar_key)
    end
  end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "loads avatar_original for re-crop"
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for re-crop loading avatar_original"
```

---

### Task 6: Spec — remove photo persists immediately

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

After the `describe "re-crop existing photo"` block, add:

```ruby
  describe "remove photo" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "persists removal immediately (without clicking Save & apply)" do
      open_identity_picker

      # Enter crop view via photo preview
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      click_button I18n.t("identity_picker.remove_photo")

      # Returns to hub with Initials now selected
      wait_for_hub_view
      expect(page).to have_css("[data-source='initials'].border-interactive", wait: 2)

      # Server state persisted immediately — no Save & apply needed
      user.reload
      expect(user.avatar).not_to be_attached
      expect(user.avatar_original).not_to be_attached
      expect(user.avatar_source).to eq("initials")
    end
  end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "persists removal immediately"
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for removing avatar photo persists immediately"
```

---

### Task 7: Spec — Escape and Cancel both return to hub

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

After the `describe "remove photo"` block, add:

```ruby
  describe "navigation from crop view" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "Escape returns to hub without closing the modal" do
      open_identity_picker
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      page.driver.with_playwright_page do |playwright_page|
        playwright_page.keyboard.press("Escape")
      end

      wait_for_hub_view
      expect(page).to have_css("dialog[open]")
    end

    it "Cancel button returns to hub without closing the modal" do
      open_identity_picker
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      click_button I18n.t("identity_picker.cancel")

      wait_for_hub_view
      expect(page).to have_css("dialog[open]")
    end
  end
```

- [ ] **Step 2: Run the specs**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "navigation from crop view"
```

Expected: PASS (2 examples).

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system specs for Escape and Cancel returning to hub"
```

---

### Task 8: Spec — modal title reflects current view

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

After the `describe "navigation from crop view"` block, add:

```ruby
  describe "modal title" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "changes between hub and crop modes" do
      open_identity_picker

      # Hub view title
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.choose_profile_picture"))

      # Enter crop view
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.adjust_profile_picture"))

      # Return to hub
      click_button I18n.t("identity_picker.cancel")
      wait_for_hub_view
      expect(page).to have_css("dialog h2", text: I18n.t("identity_picker.choose_profile_picture"))
    end
  end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "changes between hub and crop modes"
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for modal title reflecting view mode"
```

---

### Task 9: Spec — double-click Save crop triggers only one request

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

This test intercepts the PATCH to `/account/avatar` via Playwright's `route` API, counts invocations, and delays the response so both clicks happen within the in-flight window.

- [ ] **Step 1: Add the spec**

After the `describe "modal title"` block, add:

```ruby
  describe "double-click guard on Save crop" do
    it "triggers only one PATCH request even if Save crop is clicked twice rapidly" do
      open_identity_picker
      select_identity_source("Photo")
      attach_identity_picker_file(Rails.root.join("spec/fixtures/files/avatar.png"))
      wait_for_crop_view
      simulate_crop_adjustment

      # Count PATCH requests and delay their responses so both clicks
      # happen within the in-flight window.
      patch_count = 0

      page.driver.with_playwright_page do |playwright_page|
        playwright_page.route("**/account/avatar") do |route, request|
          if request.method == "PATCH"
            patch_count += 1
            sleep 0.5  # keeps the first request in flight long enough for a second click
          end
          route.continue
        end
      end

      # Click twice rapidly — the controller's _saving guard should drop the second click
      save_button = find_button(I18n.t("identity_picker.save_crop"))
      save_button.click
      save_button.click

      # Wait for the first response to land (modal returns to hub)
      wait_for_hub_view

      expect(patch_count).to eq(1)
    end
  end
```

**Caveat:** Playwright's `route` API in the Ruby binding requires `sleep` inside the handler. This is one of the rare cases where a brief `sleep` is intentional (it deterministically keeps the request in-flight long enough) — not a flakiness workaround.

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "double-click guard"
```

Expected: PASS. If it fails with `patch_count == 2`, the in-flight guard in the controller has regressed — check `_saving` boolean logic in `identity_picker_controller.js`.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for double-click guard on Save crop"
```

---

### Task 10: Spec — arrow keys on source radio update preview

**Files:**

- Modify: `spec/system/account/profiles_spec.rb`

- [ ] **Step 1: Add the spec**

After the `describe "double-click guard..."` block, add:

```ruby
  describe "keyboard source selection" do
    it "updates preview and color panel when arrow keys navigate the radiogroup" do
      open_identity_picker

      # Focus the Photo radio. Arrow keys in a native radiogroup move AND select.
      page.driver.with_playwright_page do |playwright_page|
        playwright_page.evaluate(<<~JS)
          const radio = document.querySelector(
            "[data-identity-picker-target='sourceCards'] input[type='radio'][value='upload']"
          )
          radio.focus()
        JS
        # ArrowDown twice: upload → gravatar → initials
        playwright_page.keyboard.press("ArrowDown")
        playwright_page.keyboard.press("ArrowDown")
      end

      # Preview section: initials now visible, photo/gravatar hidden
      expect(page).to have_css("[data-identity-picker-target='initialsPreview']:not([hidden])", wait: 2)

      # Color panel visible (has_color_picker: true for User)
      expect(page).to have_css("[data-identity-picker-target='colorPanel']:not([hidden])")

      # The Initials source card has the selected-state classes
      expect(page).to have_css("[data-source='initials'].border-interactive")
    end
  end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb -e "updates preview and color panel"
```

Expected: PASS.

If the user's `available_avatar_sources` is not `upload, gravatar, initials` (three items, in that order), the ArrowDown count may land on a different source. If so, query `user.available_avatar_sources` in the setup and adjust the number of key presses.

- [ ] **Step 3: Commit**

```bash
git add spec/system/account/profiles_spec.rb
git commit -m "test: system spec for keyboard arrow key source selection"
```

---

### Task 11: Spec — workspace upload logo flow

**Files:**

- Create: `spec/system/workspaces/brandings_spec.rb`

- [ ] **Step 1: Create the spec file**

Create `spec/system/workspaces/brandings_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe "Workspace branding — identity picker", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.first || create(:workspace, owner: user) }
  let(:logo_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_workspace_branding_path(workspace)
  end

  describe "logo upload flow" do
    it "uploads, crops, and saves a workspace logo via the JS saveCrop path" do
      open_identity_picker
      select_identity_source("Photo")
      attach_identity_picker_file(logo_fixture)

      wait_for_crop_view
      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      wait_for_hub_view

      # Validates the Task H4 fix: JS sends avatar/avatar_original params
      # and the BrandingsController maps them to logo/logo_original
      workspace.reload
      expect(workspace.logo).to be_attached
      expect(workspace.logo_original).to be_attached
    end
  end
end
```

**Note on `user.workspaces.first`:** most apps using the `Tenanted` pattern auto-create a personal workspace on user creation. If this project does not, replace that line with `create(:workspace, owner: user)` and make sure the user is a member. Verify by running and adjusting if needed.

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/workspaces/brandings_spec.rb -e "uploads, crops, and saves"
```

Expected: PASS.

If the test fails at `visit edit_workspace_branding_path(workspace)` with a routing error, the user likely doesn't have access to that workspace. Investigate `user.workspaces` or `Current.workspace` setup for the test and adjust the setup block. One working pattern:

```ruby
let(:workspace) do
  ws = create(:workspace)
  ws.memberships.create!(user: user, role: "owner") if ws.memberships.none?
  ws
end
```

- [ ] **Step 3: Commit**

```bash
git add spec/system/workspaces/brandings_spec.rb
git commit -m "test: system spec for workspace logo upload via JS saveCrop path"
```

---

### Task 12: Spec — workspace switch to Initials

**Files:**

- Modify: `spec/system/workspaces/brandings_spec.rb`

- [ ] **Step 1: Add the spec**

Inside the `RSpec.describe "Workspace branding — identity picker"` block, after `describe "logo upload flow"`, add:

```ruby
  describe "switch to initials" do
    before do
      workspace.logo.attach(
        io: File.open(logo_fixture),
        filename: "logo.png",
        content_type: "image/png"
      )
      workspace.logo_original.attach(
        io: File.open(logo_fixture),
        filename: "logo_original.png",
        content_type: "image/png"
      )
      workspace.save!
      visit edit_workspace_branding_path(workspace)  # refresh after attaching
    end

    it "switches workspace to Initials (no color picker for workspace) and purges logo" do
      open_identity_picker

      select_identity_source("Initials")

      # Workspace has has_color_picker: false — color panel should NOT be in the DOM
      expect(page).to have_no_css("[data-identity-picker-target='colorPanel']")

      click_button I18n.t("identity_picker.save")

      # Modal closes
      expect(page).to have_no_css("dialog[open]", wait: 3)

      workspace.reload
      expect(workspace.logo).not_to be_attached
      expect(workspace.logo_original).not_to be_attached
    end
  end
```

- [ ] **Step 2: Run the spec**

```bash
mise exec -- bundle exec rspec spec/system/workspaces/brandings_spec.rb -e "switches workspace to Initials"
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/workspaces/brandings_spec.rb
git commit -m "test: system spec for workspace switching to Initials and purging logo"
```

---

### Task 13: Final verification — full CI=true runs

**Files:** None (verification only)

- [ ] **Step 1: Run all identity picker system specs together**

```bash
CI=true mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb spec/system/workspaces/brandings_spec.rb --format documentation
```

Expected: 11 examples, 0 failures.

- [ ] **Step 2: Run all system specs**

```bash
CI=true mise exec -- bundle exec rspec spec/system/ --format progress | tail -5
```

Expected: all system specs pass (existing + 11 new). Verify the example count is higher than before (was 110, should now be 121).

- [ ] **Step 3: Run the full test suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress | tail -5
```

Expected: all green — 948+11 = 959 examples, 0 failures.

- [ ] **Step 4: Run 3 consecutive CI=true system spec runs to check for flakiness**

```bash
for i in 1 2 3; do echo "=== Run $i ==="; CI=true mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb spec/system/workspaces/brandings_spec.rb --format progress | tail -3; done
```

Expected: 0 failures across all 3 runs.

If any run shows flakiness, the spec involved must be hardened (tighter waits, better selectors, reduced timing sensitivity). Do not merge with flaky tests.

- [ ] **Step 5: No separate commit — verification only.**

---

## Self-Review

### Spec coverage check

Against the design spec's 11-test list:

| Spec test | Task |
|-----------|------|
| Profile #1: Upload → crop → save | Task 2 ✓ |
| Profile #2: Initials with custom color | Task 3 ✓ |
| Profile #3: Gravatar | Task 4 ✓ |
| Profile #4: Re-crop existing photo | Task 5 ✓ |
| Profile #5: Remove photo persists | Task 6 ✓ |
| Profile #6: Escape + Cancel return to hub | Task 7 ✓ |
| Profile #7: Modal title reflects view | Task 8 ✓ |
| Profile #8: Double-click guard | Task 9 ✓ |
| Profile #9: Arrow keys update preview | Task 10 ✓ |
| Workspace #1: Upload logo | Task 11 ✓ |
| Workspace #2: Switch to Initials | Task 12 ✓ |

All 11 specs covered. Helpers module covered in Task 1. Final verification in Task 13.

### Placeholder check

No "TBD", "TODO", "similar to Task N", or vague instructions. Each task has full code blocks.

### Type/name consistency

- `open_identity_picker` — defined in Task 1, used in Tasks 2-12 ✓
- `select_identity_source(title)` — defined Task 1, used ✓
- `attach_identity_picker_file(path)` — defined Task 1, used Tasks 2, 9, 11 ✓
- `simulate_crop_adjustment` — defined Task 1, used Tasks 2, 5, 9, 11 ✓
- `set_identity_color_hue(hue)` — defined Task 1, used Task 3 ✓
- `wait_for_crop_view` / `wait_for_hub_view` — defined Task 1, used throughout ✓
- `sign_in_via_form(user)` — defined Task 1, used in `before` blocks ✓

All method names consistent across tasks.
