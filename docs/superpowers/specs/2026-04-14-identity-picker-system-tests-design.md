# Identity Picker System Tests — Design Spec

## Goal

Add browser-level integration test coverage for the identity picker feature, ensuring the Stimulus controllers, Cropper.js integration, and modal orchestration all work end-to-end on the real rendered pages.

## Scope

**Tiers 1 + 2** from the brainstorming conversation:

- **Tier 1 (golden paths):** Upload → crop → save, source switching, Gravatar flow, re-crop, photo removal
- **Tier 2 (interaction fixes):** Escape returns to hub, Cancel returns to hub, modal title toggle, double-click guard on Save, keyboard source selection updates preview

**Out of scope:**

- Tier 3 (error path coverage — validation errors, network failures) — significant additional scope, flaky to test reliably
- Tier 4 (niche accessibility/UX — focus management, GIF warning, dimension badge updates) — lower ROI for system test cost
- Raw pointer-event drag/resize of the Cropper.js UI — covered by JS-level simulation instead
- The OLD `modal_spec.rb`'s pattern of injecting test HTML via JS — memory note says system specs must test actual ERB pages

## Architecture

Two test files mirroring the actual user-facing pages:

### `spec/system/account/profiles_spec.rb` — 9 specs

Comprehensive coverage of identity picker behavior using the profile edit page as the UI context.

1. **Upload → crop → save**
   - Visit profile edit page, open identity picker modal
   - Select Photo source; file picker opens via `attach_file` with `spec/fixtures/files/avatar.png` (visible: false, since the file input is `sr-only`)
   - Modal transitions to crop view automatically
   - Simulate a crop adjustment via JS (`cropper.getCropperSelection().$move(10, 10)`)
   - Click Save crop
   - Assert avatar image on profile page updates (check the img src changed or presence of cropped variant URL)

2. **Switch to Initials with custom color**
   - Precondition: user exists with default primary_color
   - Open modal, click Initials source card
   - Color picker panel appears (has_color_picker: true for User)
   - Update hue slider value via JS (`slider.value = 120; slider.dispatchEvent(new Event('input'))`)
   - Click Save & apply
   - Assert page shows colored initials; assert `user.reload.primary_color` matches

3. **Switch to Gravatar**
   - Open modal, click Gravatar source card
   - No color picker visible (correct)
   - Click Save & apply
   - Assert page shows Gravatar image (img src includes `gravatar.com`)

4. **Re-crop existing photo**
   - Precondition: user already has avatar AND avatar_original attached (direct `attach` on both in setup)
   - Capture the current avatar blob key before the action (`user.avatar.blob.key`)
   - Open modal — Photo source is current
   - Click the photo preview button
   - Assert crop view's image `src` contains `avatar_original` blob key (proves we're using original, not resized)
   - Simulate crop adjustment via `simulate_crop_adjustment`
   - Click Save crop
   - `user.reload`; assert `user.avatar.attached?` is true AND `user.avatar.blob.key != original_key` (proves a new blob was created by the crop save)

5. **Remove photo from crop view persists immediately**
   - Precondition: user has avatar attached
   - Open modal, enter crop view (click photo preview)
   - Click Remove photo
   - Assert: hub view is visible; Initials source card has `border-interactive` class (indicating selected state)
   - Assert immediately (without clicking Save & apply): `user.reload.avatar.attached?` is false AND `user.avatar_source == "initials"`

6. **Escape and Cancel both return to hub without closing modal**
   - Open modal, enter crop view (via photo preview click)
   - Press Escape
   - Assert: modal is still open (`dialog[open]` present), hub section is visible, crop section is hidden
   - Re-enter crop view
   - Click Cancel button
   - Same assertion

7. **Modal title reflects current view**
   - Open modal; assert modal header contains "Choose profile picture"
   - Enter crop view; assert header contains "Adjust profile picture"
   - Click Cancel (back to hub); assert header contains "Choose profile picture"

8. **Double-click Save crop triggers only one request**
   - Enter crop view with an uploaded file (upload is NOT intercepted — only the PATCH save is)
   - Set up a Playwright route handler scoped to `**/account/avatar` with method PATCH that (a) increments a counter, (b) delays 500ms before responding, (c) returns a real turbo_stream success response
   - Click Save crop twice rapidly (within 100ms — before the 500ms delay resolves)
   - After the response lands, assert the counter is exactly 1
   - Note: the second click is silently dropped by the controller's `_saving` in-flight guard, which is the behavior under test

9. **Arrow keys on source radio update preview**
   - Open modal
   - Focus the Photo radio input
   - Press ArrowDown twice to navigate to Initials
   - Assert: initials preview is visible (other previews hidden), color picker panel is shown, selected card has `border-interactive` class

### `spec/system/workspaces/brandings_spec.rb` — 2 specs

Workspace-specific paths only. Behaviors identical to User (Escape, Cancel, re-crop, keyboard, modal title) are already covered in profiles_spec.

1. **Upload logo → crop → save**
   - Precondition: logged-in user with a workspace; visit branding edit page
   - Open identity picker modal from logo area
   - `attach_file` with avatar.png, simulate crop, click Save crop
   - Assert `workspace.reload.logo.attached?` and `workspace.logo_original.attached?`
   - This test specifically validates the Task H4 fix: JS sends `avatar`/`avatar_original` params, controller maps them to logo/logo_original

2. **Switch to Initials → save**
   - Precondition: workspace has a logo attached
   - Open modal, click Initials source
   - Assert: no color picker inside identity picker (has_color_picker: false for workspaces)
   - Click Save & apply
   - Assert `workspace.reload.logo.attached?` is false, logo_original is also purged

## Shared Test Helpers

New file: `spec/support/identity_picker_helpers.rb`

```ruby
module IdentityPickerHelpers
  # Open the identity picker modal from a profile/branding edit page.
  # Both pages wrap the trigger in a [data-controller="modal"] container.
  def open_identity_picker
    find("[data-controller='modal'] button[data-action*='modal#open']", match: :first).click
    # Wait for modal to finish its entrance animation
    expect(page).to have_css("dialog[open]", wait: 2)
    wait_for_stimulus
  end

  # Click a source card by the title text ("Photo", "Gravatar", "Initials").
  # Uses the label element since that's what the click handler is bound to.
  def select_source(title)
    within("[data-identity-picker-target='sourceCards']") do
      find("label", text: title).click
    end
  end

  # Attach a file to the identity picker's hidden file input.
  # The input has sr-only class so Capybara needs visible: false.
  # We target by the Stimulus target attribute rather than an ID.
  def attach_identity_picker_file(path)
    input = page.find("input[data-identity-picker-target='fileInput']", visible: false)
    input.attach_file(path)
  end

  # Simulate a crop adjustment via JS — avoids brittle pointer events.
  # Moves the selection 10px right + 10px down.
  def simulate_crop_adjustment
    page.execute_script(<<~JS)
      const cropperEl = document.querySelector("[data-controller='image-cropper']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      const selection = controller._cropper.getCropperSelection()
      selection.$move(10, 10)
    JS
  end

  # Wait for the crop view to be visible and Cropper.js to initialize.
  def wait_for_crop_view
    expect(page).to have_css("[data-mode='crop']:not([hidden])", wait: 3)
    expect(page).to have_css("cropper-canvas", wait: 3)
  end

  # Wait for hub view to be visible (after switching modes).
  def wait_for_hub_view
    expect(page).to have_css("[data-mode='hub']:not([hidden])", wait: 2)
  end
end

RSpec.configure do |config|
  config.include IdentityPickerHelpers, type: :system
end
```

## Setup / Fixtures

- Uses existing `spec/fixtures/files/avatar.png` (no new fixtures)
- Factory `:user` from existing setup
- Factory `:workspace` with owner set up
- Sign-in via existing authentication helpers

## Flakiness Mitigation

- Use `wait_for_stimulus` and `wait_for_modal` from the project's `system_helpers.rb`
- NO hardcoded `sleep` calls
- For the double-click test (spec 8), use Playwright's `route` API to slow the response deterministically — NOT timing-based delays
- Color-contrast false positives already handled by the hardened `after(:each)` hook

## Performance

- 11 specs × ~3-5s each = 30-55 seconds added to system spec runtime
- Current system spec suite is ~46s; estimated new total ~75-100s
- Acceptable given the coverage gain

## Dependencies

- Playwright driver is already configured (`spec/support/capybara.rb`)
- No new gems needed
- Existing helpers (`wait_for_stimulus`, `wait_for_modal`, etc.) from `spec/support/system_helpers.rb` will be used

## Success Criteria

- All 11 new specs pass consistently on 3 consecutive `CI=true` local runs
- Adding the tests doesn't break any existing specs
- Push hook passes (including the hardened accessibility `after(:each)` audit)
- Test code follows project conventions (no `sleep`, use real rendered pages, match existing spec style)
