# Toast Notification System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the minimal inline flash messages with a full toast notification system — auto-dismiss with progress bar, persistent errors, stacked display, Turbo Stream integration, and accessible animations.

**Architecture:** A `_toast.html.erb` partial (not a ViewComponent — only used in one context) rendered by a `toast_controller.js` Stimulus controller. A `_toasts.html.erb` container manages the stack. A `Toastable` concern provides controller helpers for Turbo Stream toast responses. Flash messages automatically become toasts.

**Tech Stack:** ERB partials with strict locals, Stimulus controllers, Turbo Streams, TailwindCSS, I18n

## Improvements Over agent_os

1. **Partial instead of ViewComponent** — the toast is only rendered in one place (the notifications container), so a ViewComponent adds complexity without reuse benefit. Strict locals give the same interface.
2. **No hardcoded colors in JS** — agent_os duplicates the full color scheme in `toast_stack_controller.js` for dynamic toasts. Instead, we'll use a hidden template element that the JS clones, keeping all styling in ERB.
3. **Simpler stack management** — agent_os has bring-to-top on click and complex transform stacking. Users rarely interact with stacked toasts this way. We'll stack vertically with simple gap spacing.
4. **Consolidated controllers** — agent_os has separate `toast_controller` and `toast_stack_controller`. We'll use one `toast_controller` on each toast and rely on CSS for stack layout (the container is just a flex column).
5. **Screen reader improvements** — use `role="status"` with `aria-live="polite"` for notices/success and `role="alert"` with `aria-live="assertive"` for errors/alerts. The agent_os standard uses `role="alert"` for everything, which over-announces informational messages. This override is intentional per WCAG 4.1.3 Status Messages (AAA).
6. **Deliberate omission of `render_success_toast` / `render_error_toast`** — agent_os has these "render ONLY the toast" helpers. They're syntactic sugar over `render turbo_stream: success_toast(msg)` and not worth the extra API surface.

---

### Task 1: Create the toast partial and container

**Files:**
- Create: `app/views/shared/_toast.html.erb`
- Create: `app/views/shared/_toasts.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/layouts/markdowndocs/application.html.erb`
- Create: `config/locales/en/toasts.en.yml`
- Test: `spec/system/static_pages_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/system/static_pages_spec.rb` inside `describe "layout"`:

```ruby
it "has a notifications container for toasts" do
  visit root_path
  expect(page).to have_css("#notifications[aria-label]")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/static_pages_spec.rb -e "notifications container"`

Expected: FAIL

- [ ] **Step 3: Create I18n keys**

Create `config/locales/en/toasts.en.yml`:

```yaml
en:
  toasts:
    aria_label: "Notifications"
    close: "Close notification"
```

- [ ] **Step 4: Create the toast partial**

Create `app/views/shared/_toast.html.erb` with strict locals `(type:, message:)`:

- 4 types: `notice`, `success`, `alert`, `error`
- Each with distinct icon (inline SVG), background, border, text colors
- Dark mode support on all colors
- Close button with `data-action="click->toast#dismiss"`
- Progress bar for auto-dismiss types (notice, success)
- `data-controller="toast"` with `data-toast-timeout-value` computed from word count
- `role="status"` and `aria-live="polite"` for notice/success
- `role="alert"` and `aria-live="assertive"` for alert/error
- `aria-atomic="true"` on all
- 44px minimum touch target on close button

Auto-dismiss duration formula: `max(5000, word_count * 500 + 1000)` capped at 15000. Timeout is 0 for alert/error.

- [ ] **Step 5: Create the toasts container**

Create `app/views/shared/_toasts.html.erb`:

```erb
<div id="notifications"
     aria-label="<%= t('toasts.aria_label') %>"
     class="fixed top-16 right-0 z-[100] flex flex-col gap-3 p-4 sm:p-6
            pointer-events-none">
  <% flash.each do |type, message| %>
    <% next unless %w[notice success alert error].include?(type) %>
    <%= render "shared/toast", type: type, message: message %>
  <% end %>
</div>
```

- [ ] **Step 6: Add container to both layouts**

In `app/views/layouts/application.html.erb`: replace `<%= render "shared/flash" %>` with `<%= render "shared/toasts" %>`.

In `app/views/layouts/markdowndocs/application.html.erb`: **add** `<%= render "shared/toasts" %>` after the header render (this layout does not currently render flash messages).

- [ ] **Step 7: Run full test suite**

Run: `bundle exec rspec`

Expected: All pass (560+)

- [ ] **Step 8: Commit**

```bash
git add app/views/shared/_toast.html.erb app/views/shared/_toasts.html.erb \
  app/views/layouts/application.html.erb app/views/layouts/markdowndocs/application.html.erb \
  config/locales/en/toasts.en.yml spec/system/static_pages_spec.rb
git commit -m "feat(ui): Add toast notification partial and container with flash integration"
```

---

### Task 2: Create the toast Stimulus controller

**Files:**
- Create: `app/javascript/controllers/toast_controller.js`
- Modify: `app/views/shared/_toast.html.erb` (wire data attributes)
- Test: `spec/system/static_pages_spec.rb`

- [x] **Step 1: Write failing system tests**

Add to `spec/system/static_pages_spec.rb`. These tests sign in to trigger a notice flash:

```ruby
describe "toast notifications" do
  let(:user) { create(:user) }

  def sign_in_via_form
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "password123!"
    click_button I18n.t("sessions.password_form.submit")
  end

  it "shows a toast with progress bar on successful sign-in" do
    sign_in_via_form
    expect(page).to have_css("[data-controller='toast']")
    expect(page).to have_css("[data-toast-target='progress']")
  end

  it "allows dismissing a toast with the close button via keyboard" do
    sign_in_via_form
    expect(page).to have_css("[data-controller='toast']")
    close_button = find("[data-controller='toast'] button[aria-label]")
    close_button.send_keys(:enter)
    expect(page).not_to have_css("[data-controller='toast']")
  end
end
```

Note: The I18n keys are `sessions.password_form.password_label` and `sessions.password_form.submit`. Verify these exist before running.

- [x] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/system/static_pages_spec.rb -e "toast notifications"`

Expected: FAIL — no `data-controller="toast"` yet

- [x] **Step 3: Create the Stimulus controller**

Create `app/javascript/controllers/toast_controller.js`:

Values:
- `timeout` (Number, default 0) — 0 means no auto-dismiss

Targets:
- `progress` — the progress bar element

Behavior:
- `connect()`: Animate in (translateX/opacity). If timeout > 0, start dismiss timer and progress bar animation. Check `prefers-reduced-motion` — if reduced, skip slide animations but still auto-dismiss.
- `dismiss()`: Animate out (opacity + translateX), then remove element.
- `pause()` / `resume()`: On mouseenter/mouseleave, pause/resume timer and progress bar.
- Progress bar: CSS transition `width` from 100% to 0% over timeout duration, pauses on hover.

Animation:
- Enter: translateX(100%) opacity(0) → translateX(0) opacity(1), 300ms ease-out
- Exit: translateX(0) opacity(1) → translateX(100%) opacity(0), 300ms ease-in
- Reduced motion: opacity only, no slide

- [x] **Step 4: Wire data attributes in the toast partial**

Update `app/views/shared/_toast.html.erb` to include:
- `data-controller="toast"`
- `data-toast-timeout-value="<%= timeout %>"`
- `data-action="mouseenter->toast#pause mouseleave->toast#resume"`
- `data-toast-target="progress"` on the progress bar div

- [x] **Step 5: Run full test suite**

Run: `bundle exec rspec`

Expected: All pass

- [x] **Step 6: Commit**

```bash
git add app/javascript/controllers/toast_controller.js app/views/shared/_toast.html.erb \
  spec/system/static_pages_spec.rb
git commit -m "feat(ui): Add toast Stimulus controller with auto-dismiss and progress bar"
```

---

### Task 3: Add Toastable concern for Turbo Stream helpers

**Files:**
- Create: `app/controllers/concerns/toastable.rb`
- Modify: `app/controllers/application_controller.rb`
- Test: `spec/controllers/concerns/toastable_spec.rb`

- [x] **Step 1: Write failing test**

Create `spec/controllers/concerns/toastable_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Toastable, type: :controller do
  controller(ApplicationController) do
    include Toastable

    def index
      render turbo_stream: success_toast("It worked")
    end
  end

  before { routes.draw { get "index" => "anonymous#index" } }

  describe "#success_toast" do
    it "returns a turbo stream append to notifications" do
      get :index, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="notifications"')
      expect(response.body).to include("It worked")
    end
  end
end
```

- [x] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/concerns/toastable_spec.rb`

Expected: FAIL — Toastable not defined

- [x] **Step 3: Create the Toastable concern**

Create `app/controllers/concerns/toastable.rb`:

```ruby
module Toastable
  extend ActiveSupport::Concern

  private

  def toast_stream(type, message, target: "notifications")
    turbo_stream.append(target, partial: "shared/toast", locals: { type: type, message: message })
  end

  def success_toast(message)
    toast_stream("success", message)
  end

  def error_toast(message)
    toast_stream("error", message)
  end
end
```

- [x] **Step 4: Include in ApplicationController**

Add `include Toastable` to `ApplicationController`.

- [x] **Step 5: Run full test suite**

Run: `bundle exec rspec`

Expected: All pass

- [x] **Step 6: Commit**

```bash
git add app/controllers/concerns/toastable.rb app/controllers/application_controller.rb \
  spec/controllers/concerns/toastable_spec.rb
git commit -m "feat(ui): Add Toastable concern with Turbo Stream toast helpers"
```

---

### Task 4: Remove old flash partial

**Files:**
- Delete: `app/views/shared/_flash.html.erb`
- Test: Full suite

- [ ] **Step 1: Verify flash partial is no longer referenced**

Search for `render "shared/flash"` or `render 'shared/flash'` in all views. It should only appear in layouts, which were already updated in Task 1 to use `_toasts.html.erb`.

- [ ] **Step 2: Delete the old flash partial**

```bash
git rm app/views/shared/_flash.html.erb
```

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rspec`

Expected: All pass

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: Remove old flash partial replaced by toast system"
```
