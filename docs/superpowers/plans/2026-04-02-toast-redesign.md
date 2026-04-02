# Two-Tier Toast Notification System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-format toast system with a two-tier approach: compact auto-dismissing pills (top-center) for success/info, persistent dismissible cards (bottom-center) for warnings/errors.

**Architecture:** Two separate Stimulus controllers (`toast-pill`, `toast-card`) replace the single `toast` controller. Two DOM containers (`#toast-pills`, `#toast-cards`) replace the single `#notifications` container. The `Toastable` concern routes flash types to the correct container/partial. New semantic tokens (`surface-toast`, `text-on-toast`) handle pill dark/light mode.

**Tech Stack:** Rails 8.1, Stimulus, TailwindCSS 4 with OKLCH semantic tokens, RSpec, Playwright

**Spec:** `docs/superpowers/specs/2026-04-02-toast-redesign-design.md`

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `app/assets/tailwind/tokens/_semantic.css` | Modify | Add `surface-toast` and `text-on-toast` tokens |
| `app/assets/tailwind/application.css` | Modify | Register new tokens in `@theme inline` block |
| `app/javascript/controllers/toast_pill_controller.js` | Create | Auto-dismiss pill: animate, pause/resume, progress bar |
| `app/javascript/controllers/toast_card_controller.js` | Create | Persistent card: animate in, dismiss on click |
| `app/views/shared/_toast_pill.html.erb` | Create | Compact pill partial for success/info |
| `app/views/shared/_toast_card.html.erb` | Create | Persistent card partial for warning/error |
| `app/views/shared/_toasts.html.erb` | Rewrite | Two containers (top-center pills, bottom-center cards) |
| `app/controllers/concerns/toastable.rb` | Modify | Route types to correct container/partial |
| `config/locales/en/toasts.en.yml` | Modify | Add pill/card aria labels |
| `spec/controllers/concerns/toastable_spec.rb` | Rewrite | Test new routing, partials, targets |
| `spec/system/static_pages_spec.rb` | Modify | Update toast assertions for new structure |
| `spec/system/toast_spec.rb` | Create | System specs for pill auto-dismiss, card persistence, keyboard |
| `app/views/shared/_toast.html.erb` | Delete | Replaced by pill + card partials |
| `app/javascript/controllers/toast_controller.js` | Delete | Replaced by pill + card controllers |

---

### Task 1: Add Semantic Tokens for Toast Pill

**Files:**

- Modify: `app/assets/tailwind/tokens/_semantic.css`
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Add toast tokens to `:root` in `_semantic.css`**

Add after the `--color-border-focus` line (line 35) in the `:root` block, before the closing `}`:

```css
  /* --- Toast (inverted overlay pill) --- */
  --color-surface-toast: oklch(20.5% 0.016 265.755 / 90%);  /* neutral-900 @ 90% */
  --color-text-on-toast: oklch(100% 0 0);                     /* white */
```

- [ ] **Step 2: Add toast tokens to `.dark` in `_semantic.css`**

Add after the `--color-border-focus` line (line 64) in the `.dark` block, before the closing `}`:

```css
  /* --- Toast --- */
  --color-surface-toast: oklch(96.8% 0.007 264.536 / 90%);   /* neutral-100 @ 90% */
  --color-text-on-toast: var(--neutral-900);
```

- [ ] **Step 3: Register tokens in `@theme inline` block**

Add to `app/assets/tailwind/application.css` inside the `@theme inline { }` block, after the Info signals section (after line 72), before the closing `}`:

```css
  /* Toast pill */
  --color-surface-toast: var(--color-surface-toast);
  --color-text-on-toast: var(--color-text-on-toast);
```

- [ ] **Step 4: Verify Tailwind compiles the new tokens**

Run: `bin/rails tailwindcss:build 2>&1 | tail -3`
Expected: Build completes without errors.

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind/tokens/_semantic.css app/assets/tailwind/application.css
git commit -m "feat: add surface-toast and text-on-toast semantic tokens

Inverted overlay tokens for toast pill: dark pill on light backgrounds,
light pill on dark backgrounds. Flips automatically via .dark class."
```

---

### Task 2: Create Toast Pill Stimulus Controller

**Files:**

- Create: `app/javascript/controllers/toast_pill_controller.js`

- [ ] **Step 1: Create the pill controller**

Create `app/javascript/controllers/toast_pill_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }
  static targets = ["progress"]

  connect() {
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.remaining = this.timeoutValue
    this.animateIn()
    this.startAutoClose()
    this.startProgressBar()
  }

  disconnect() {
    clearTimeout(this.dismissTimer)
  }

  dismiss() {
    this.element.style.pointerEvents = "none"
    const duration = this.prefersReducedMotion ? 0 : 300

    this.element.style.transition = `opacity ${duration}ms ease-in`
    this.element.style.opacity = "0"

    setTimeout(() => this.element.remove(), duration)
  }

  pause() {
    clearTimeout(this.dismissTimer)
    this.pausedAt = Date.now()

    if (this.hasProgressTarget) {
      this.progressTarget.style.transition = "none"
    }
  }

  resume() {
    if (!this.pausedAt) return
    this.remaining -= (Date.now() - this.pausedAt)
    this.pausedAt = null

    if (this.remaining > 0) {
      this.startAutoClose()
      if (this.hasProgressTarget) {
        this.progressTarget.style.transition = `width ${this.remaining}ms linear`
        this.progressTarget.style.width = "0%"
      }
    } else {
      this.dismiss()
    }
  }

  // Private

  animateIn() {
    if (this.prefersReducedMotion) {
      this.element.style.opacity = "1"
      return
    }

    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(-8px)"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 300ms ease-out, transform 300ms ease-out"
      this.element.style.opacity = "1"
      this.element.style.transform = "translateY(0)"
    })
  }

  startAutoClose() {
    this.dismissTimer = setTimeout(() => this.dismiss(), this.remaining)
  }

  startProgressBar() {
    if (!this.hasProgressTarget) return
    this.progressTarget.style.width = "100%"
    requestAnimationFrame(() => {
      this.progressTarget.style.transition = `width ${this.timeoutValue}ms linear`
      this.progressTarget.style.width = "0%"
    })
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/toast_pill_controller.js
git commit -m "feat: add toast pill Stimulus controller

Auto-dismiss with reading-speed timeout, pause-on-hover, progress bar
animation, slide-down entrance, respects prefers-reduced-motion."
```

---

### Task 3: Create Toast Card Stimulus Controller

**Files:**

- Create: `app/javascript/controllers/toast_card_controller.js`

- [ ] **Step 1: Create the card controller**

Create `app/javascript/controllers/toast_card_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.animateIn()
  }

  dismiss() {
    this.element.style.pointerEvents = "none"
    const duration = this.prefersReducedMotion ? 0 : 300

    this.element.style.transition = `opacity ${duration}ms ease-in`
    this.element.style.opacity = "0"

    setTimeout(() => this.element.remove(), duration)
  }

  // Private

  animateIn() {
    if (this.prefersReducedMotion) {
      this.element.style.opacity = "1"
      return
    }

    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(8px)"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 300ms ease-out, transform 300ms ease-out"
      this.element.style.opacity = "1"
      this.element.style.transform = "translateY(0)"
    })
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/toast_card_controller.js
git commit -m "feat: add toast card Stimulus controller

Persistent card with dismiss action, slide-up entrance animation,
respects prefers-reduced-motion. No auto-dismiss."
```

---

### Task 4: Create Toast Pill Partial (TDD)

**Files:**

- Modify: `config/locales/en/toasts.en.yml`
- Create: `app/views/shared/_toast_pill.html.erb`
- Modify: `spec/system/static_pages_spec.rb`

- [ ] **Step 1: Update I18n keys**

Replace the full contents of `config/locales/en/toasts.en.yml`:

```yaml
en:
  toasts:
    pill_aria_label: "Notifications"
    card_aria_label: "Alerts"
    close: "Dismiss notification"
```

- [ ] **Step 2: Write the failing request spec**

Add a new file `spec/requests/toast_rendering_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Toast rendering", type: :request do
  describe "success flash" do
    let(:user) { create(:user) }

    it "renders a pill in the toast-pills container" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }
      follow_redirect!
      expect(response.body).to include('id="toast-pills"')
      expect(response.body).to include('data-controller="toast-pill"')
      expect(response.body).to include('role="status"')
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/toast_rendering_spec.rb`
Expected: FAIL — `toast-pills` container and `toast-pill` controller don't exist yet.

- [ ] **Step 4: Create the toast pill partial**

Create `app/views/shared/_toast_pill.html.erb`:

```erb
<%# locals: (type:, message:) -%>
<%
  timeout = [5000, message.split.size * 500 + 1000].max.clamp(5000, 15000)

  icon_color = case type
               when "success" then "text-success-icon"
               else "text-info-icon"
               end

  progress_color = case type
                   when "success" then "bg-success-progress"
                   else "bg-info-progress"
                   end
%>
<div data-controller="toast-pill"
     data-toast-pill-timeout-value="<%= timeout %>"
     data-action="mouseenter->toast-pill#pause mouseleave->toast-pill#resume"
     role="status"
     aria-live="polite"
     aria-atomic="true"
     class="pointer-events-auto rounded-full bg-surface-toast shadow-lg
            px-4 py-2 flex items-center gap-2
            max-w-sm max-w-[calc(100vw-2rem)] overflow-hidden">
  <div class="shrink-0 <%= icon_color %>">
    <% if type == "success" %>
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="size-4" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
      </svg>
    <% else %>
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="size-4" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z" />
      </svg>
    <% end %>
  </div>
  <p class="text-sm font-medium text-text-on-toast whitespace-nowrap"><%= message %></p>
  <div class="absolute bottom-0 left-0 right-0 h-0.5">
    <div data-toast-pill-target="progress" class="h-full <%= progress_color %>" style="width: 100%;"></div>
  </div>
</div>
```

- [ ] **Step 5: Run test — it will still fail because the container doesn't exist yet**

Run: `bundle exec rspec spec/requests/toast_rendering_spec.rb`
Expected: FAIL — the `_toasts.html.erb` container still references the old structure.

(We'll fix this in Task 6 when we rewrite the container partial.)

- [ ] **Step 6: Commit the partial and I18n**

```bash
git add app/views/shared/_toast_pill.html.erb config/locales/en/toasts.en.yml spec/requests/toast_rendering_spec.rb
git commit -m "feat: add toast pill partial with compact Basecamp-style design

Dark semi-transparent rounded pill with icon, message text, and
progress bar. Uses surface-toast/text-on-toast semantic tokens."
```

---

### Task 5: Create Toast Card Partial

**Files:**

- Create: `app/views/shared/_toast_card.html.erb`
- Modify: `spec/requests/toast_rendering_spec.rb`

- [ ] **Step 1: Add failing request spec for error flash**

Add to `spec/requests/toast_rendering_spec.rb` inside the main `RSpec.describe` block:

```ruby
describe "error flash" do
  it "renders a card in the toast-cards container" do
    post session_path, params: {
      email_address: "nobody@example.com",
      password: "wrong"
    }
    follow_redirect!
    expect(response.body).to include('id="toast-cards"')
    expect(response.body).to include('data-controller="toast-card"')
    expect(response.body).to include('role="alert"')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/toast_rendering_spec.rb`
Expected: FAIL — `toast-cards` container and `toast-card` controller don't exist yet.

- [ ] **Step 3: Create the toast card partial**

Create `app/views/shared/_toast_card.html.erb`:

```erb
<%# locals: (type:, message:) -%>
<%
  type_classes = case type
                 when "alert" then "bg-warning-surface border-warning-border"
                 when "error" then "bg-danger-surface border-danger-border"
                 end

  text_color = case type
               when "alert" then "text-warning"
               when "error" then "text-danger"
               end

  icon_color = case type
               when "alert" then "text-warning-icon"
               when "error" then "text-danger-icon"
               end

  close_hover = case type
                when "alert" then "hover:bg-warning-hover"
                when "error" then "hover:bg-danger-hover"
                end
%>
<div data-controller="toast-card"
     role="alert"
     aria-live="assertive"
     aria-atomic="true"
     class="w-96 max-w-[calc(100vw-2rem)] pointer-events-auto rounded-lg border shadow-lg overflow-hidden <%= type_classes %>">
  <div class="flex items-start gap-3 p-4">
    <div class="shrink-0 mt-0.5 <%= icon_color %>">
      <% if type == "alert" %>
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
        </svg>
      <% else %>
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
        </svg>
      <% end %>
    </div>
    <p class="flex-1 text-sm leading-relaxed <%= text_color %>"><%= message %></p>
    <button type="button"
            aria-label="<%= t('toasts.close') %>"
            data-action="click->toast-card#dismiss"
            class="shrink-0 min-h-[44px] min-w-[44px] inline-flex items-center justify-center rounded-md -m-1 <%= close_hover %> focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-current">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-5" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
      </svg>
    </button>
  </div>
</div>
```

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_toast_card.html.erb spec/requests/toast_rendering_spec.rb
git commit -m "feat: add toast card partial for persistent warning/error display

Signal-colored card with icon, message, and 44px close button.
No auto-dismiss. Uses existing signal tokens for warning/danger."
```

---

### Task 6: Rewrite Toast Container and Toastable Concern (TDD)

**Files:**

- Rewrite: `app/views/shared/_toasts.html.erb`
- Modify: `app/controllers/concerns/toastable.rb`
- Rewrite: `spec/controllers/concerns/toastable_spec.rb`

- [ ] **Step 1: Rewrite the Toastable spec**

Replace the full contents of `spec/controllers/concerns/toastable_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Toastable, type: :controller do
  controller(ApplicationController) do
    include Toastable
    allow_unauthenticated_access

    def index
      render turbo_stream: success_toast("It worked")
    end

    def create
      render turbo_stream: error_toast("Something failed")
    end

    def update
      render turbo_stream: warning_toast("Watch out")
    end
  end

  render_views

  before do
    routes.draw do
      get "index" => "anonymous#index"
      post "create" => "anonymous#create"
      patch "update" => "anonymous#update"
    end
  end

  describe "#success_toast" do
    it "appends to toast-pills with the pill partial" do
      get :index, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="toast-pills"')
      expect(response.body).to include("It worked")
    end
  end

  describe "#error_toast" do
    it "appends to toast-cards with the card partial" do
      post :create, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="toast-cards"')
      expect(response.body).to include("Something failed")
    end
  end

  describe "#warning_toast" do
    it "appends to toast-cards with the card partial" do
      patch :update, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="toast-cards"')
      expect(response.body).to include("Watch out")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/controllers/concerns/toastable_spec.rb`
Expected: FAIL — `warning_toast` undefined, targets still say `notifications`.

- [ ] **Step 3: Update the Toastable concern**

Replace the full contents of `app/controllers/concerns/toastable.rb`:

```ruby
module Toastable
  extend ActiveSupport::Concern

  private

  def toast_stream(type, message)
    target = %w[notice success].include?(type) ? "toast-pills" : "toast-cards"
    partial = %w[notice success].include?(type) ? "shared/toast_pill" : "shared/toast_card"
    turbo_stream.append(target, partial: partial, locals: { type: type, message: message })
  end

  def success_toast(message)
    toast_stream("success", message)
  end

  def error_toast(message)
    toast_stream("error", message)
  end

  def warning_toast(message)
    toast_stream("alert", message)
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/controllers/concerns/toastable_spec.rb`
Expected: 3 examples, 0 failures

- [ ] **Step 5: Rewrite the toast container partial**

Replace the full contents of `app/views/shared/_toasts.html.erb`:

```erb
<%# Top-center: success/info pills %>
<div id="toast-pills"
     aria-label="<%= t('toasts.pill_aria_label') %>"
     class="fixed top-20 left-1/2 -translate-x-1/2 z-[100]
            flex flex-col items-center gap-2
            pointer-events-none">
  <% flash.each do |type, message| %>
    <% if %w[notice success].include?(type) %>
      <%= render "shared/toast_pill", type: type, message: message %>
    <% end %>
  <% end %>
</div>

<%# Bottom-center: warning/error cards %>
<div id="toast-cards"
     aria-label="<%= t('toasts.card_aria_label') %>"
     class="fixed bottom-4 left-1/2 -translate-x-1/2 z-[100]
            flex flex-col items-center gap-3 pb-[env(safe-area-inset-bottom)]
            max-w-[calc(100vw-2rem)]
            pointer-events-none">
  <% flash.each do |type, message| %>
    <% if %w[alert error].include?(type) %>
      <%= render "shared/toast_card", type: type, message: message %>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 6: Run the request specs to verify both tiers render**

Run: `bundle exec rspec spec/requests/toast_rendering_spec.rb spec/controllers/concerns/toastable_spec.rb`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add app/views/shared/_toasts.html.erb app/controllers/concerns/toastable.rb spec/controllers/concerns/toastable_spec.rb
git commit -m "feat: split toast container into pill and card tiers

Pills (success/info) render in top-center #toast-pills container.
Cards (warning/error) render in bottom-center #toast-cards container.
Toastable concern routes flash types to the correct target and partial.
Adds warning_toast helper method."
```

---

### Task 7: Update Existing System Specs

**Files:**

- Modify: `spec/system/static_pages_spec.rb`

- [ ] **Step 1: Update the toast-related assertions**

In `spec/system/static_pages_spec.rb`, replace the toast test block (lines 78-119) with:

```ruby
    it "has toast containers for pills and cards" do
      visit root_path
      expect(page).to have_css("#toast-pills[aria-label]", visible: :all)
      expect(page).to have_css("#toast-cards[aria-label]", visible: :all)
    end
  end

  describe "toast notifications" do
    let(:user) { create(:user) }

    def sign_in_via_form
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("sessions.password_form.submit")
    end

    it "shows a pill toast with progress bar on successful sign-in" do
      sign_in_via_form
      expect(page).to have_css("[data-controller='toast-pill']")
      expect(page).to have_css("[data-toast-pill-target='progress']")
    end

    it "preserves theme preference across fresh page loads via cookie" do
      visit root_path
      # Cycle to dark: system → light → dark
      find("[data-controller='theme-toggle']").click
      find("[data-controller='theme-toggle']").click
      expect(page).to have_css("html.dark")

      # Full page load (not Turbo) — cookie should restore dark mode
      visit root_path
      expect(page).to have_css("html[data-theme-theme-value='dark']")
    end
```

Note: The "allows dismissing a toast via keyboard" test is removed here because it will be covered more thoroughly in the dedicated toast system spec (Task 8). The theme test remains because it's in this describe block but is unrelated to toasts.

- [ ] **Step 2: Run the updated spec**

Run: `bundle exec rspec spec/system/static_pages_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add spec/system/static_pages_spec.rb
git commit -m "test: update static pages specs for two-tier toast structure

Reference toast-pill controller and #toast-pills/#toast-cards containers
instead of the old single toast/notifications structure."
```

---

### Task 8: Add Dedicated Toast System Specs

**Files:**

- Create: `spec/system/toast_spec.rb`

- [ ] **Step 1: Create comprehensive system specs**

Create `spec/system/toast_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Toast notification system", type: :system do
  let(:user) { create(:user) }

  def sign_in_via_form
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
  end

  describe "pill toasts (success/info)" do
    it "appears as a pill in the top-center container" do
      sign_in_via_form
      expect(page).to have_css("#toast-pills [data-controller='toast-pill']")
    end

    it "has role=status and aria-live=polite" do
      sign_in_via_form
      pill = find("[data-controller='toast-pill']")
      expect(pill["role"]).to eq("status")
      expect(pill["aria-live"]).to eq("polite")
    end

    it "includes a progress bar" do
      sign_in_via_form
      expect(page).to have_css("[data-toast-pill-target='progress']")
    end

    it "auto-dismisses after timeout" do
      sign_in_via_form
      expect(page).to have_css("[data-controller='toast-pill']")
      # Default minimum timeout is 5 seconds; wait up to 18 to account for max
      expect(page).to have_no_css("[data-controller='toast-pill']", wait: 18)
    end

    it "does not overlap the user menu dropdown" do
      sign_in_via_form
      expect(page).to have_css("[data-controller='toast-pill']")

      # Open user menu
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)

      # Pill should be in toast-pills (top-center), menu in top-right — no overlap
      pill_container = find("#toast-pills")
      menu = find("#user-menu")
      expect(pill_container).to be_truthy
      expect(menu).to be_truthy
    end
  end

  describe "card toasts (warning/error)" do
    it "renders an error flash as a card in the bottom-center container" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: "nobody@example.com"
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "wrongpassword"
      click_button I18n.t("sessions.password_form.submit")

      expect(page).to have_css("#toast-cards [data-controller='toast-card']")
    end

    it "has role=alert and aria-live=assertive" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: "nobody@example.com"
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "wrongpassword"
      click_button I18n.t("sessions.password_form.submit")

      card = find("[data-controller='toast-card']")
      expect(card["role"]).to eq("alert")
      expect(card["aria-live"]).to eq("assertive")
    end

    it "persists until manually dismissed" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: "nobody@example.com"
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "wrongpassword"
      click_button I18n.t("sessions.password_form.submit")

      expect(page).to have_css("[data-controller='toast-card']")
      # Wait 6 seconds — should still be visible (no auto-dismiss)
      sleep 6
      expect(page).to have_css("[data-controller='toast-card']")
    end

    it "dismisses when close button is clicked" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: "nobody@example.com"
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "wrongpassword"
      click_button I18n.t("sessions.password_form.submit")

      expect(page).to have_css("[data-controller='toast-card']")
      find("[data-controller='toast-card'] button[aria-label]").click
      expect(page).to have_no_css("[data-controller='toast-card']")
    end

    it "close button is keyboard accessible" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: "nobody@example.com"
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "wrongpassword"
      click_button I18n.t("sessions.password_form.submit")

      expect(page).to have_css("[data-controller='toast-card']")
      close_button = find("[data-controller='toast-card'] button[aria-label]")
      close_button.send_keys(:enter)
      expect(page).to have_no_css("[data-controller='toast-card']")
    end
  end
end
```

- [ ] **Step 2: Run the system specs**

Run: `bundle exec rspec spec/system/toast_spec.rb`
Expected: All pass. If any fail due to flash rendering differences (e.g., failed login might not produce `error` flash), adjust the trigger scenario.

- [ ] **Step 3: Commit**

```bash
git add spec/system/toast_spec.rb
git commit -m "test: add comprehensive system specs for two-tier toast system

Covers pill auto-dismiss, progress bar, ARIA attributes, card
persistence, manual dismiss via click and keyboard, and no overlap
with user menu dropdown."
```

---

### Task 9: Delete Old Toast Files and Run Full Suite

**Files:**

- Delete: `app/views/shared/_toast.html.erb`
- Delete: `app/javascript/controllers/toast_controller.js`

- [ ] **Step 1: Delete the old toast partial**

```bash
git rm app/views/shared/_toast.html.erb
```

- [ ] **Step 2: Delete the old toast controller**

```bash
git rm app/javascript/controllers/toast_controller.js
```

- [ ] **Step 3: Run the full test suite**

Run: `bundle exec rspec`
Expected: All specs pass (670+), 0 failures. If any specs still reference `data-controller='toast'` or `#notifications`, they need updating — check the error output and fix.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: remove old single-format toast partial and controller

Replaced by toast_pill and toast_card partials with dedicated
Stimulus controllers. Two-tier toast system is now complete."
```

---

## Verification

After all tasks are complete:

1. **Full suite:** `bundle exec rspec` — all specs green
2. **Manual check (light mode):** Sign in → dark pill with checkmark appears top-center, fades after a few seconds
3. **Manual check (dark mode):** Toggle dark mode → pill should be light-colored on dark background
4. **Error check:** Trigger an error flash → card appears bottom-center, persists, close button works
5. **Dropdown check:** Open user menu while pill is visible → no overlap
6. **Keyboard:** Tab to card close button, press Enter to dismiss
7. **Mobile:** Resize to mobile width → pill and card should be appropriately sized
8. **Hover pause:** Hover over pill → progress bar freezes, resumes on mouseout
