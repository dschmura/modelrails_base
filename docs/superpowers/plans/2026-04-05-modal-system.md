# Modal System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable modal system using the native `<dialog>` element with a Stimulus controller for animations, backdrop click handling, and CSS custom properties for customization.

**Architecture:** A `modal_controller.js` Stimulus controller wraps a native `<dialog>` element, adding open/close animations and backdrop click detection. The browser handles focus trap, Escape key, inert background, and top-layer positioning natively. A `_modal.html.erb` partial provides the reusable HTML structure with configurable title, size, and yielded content.

**Tech Stack:** Rails 8.1, Stimulus, native `<dialog>` element, TailwindCSS 4 with semantic tokens

**Spec:** `docs/superpowers/specs/2026-04-05-modal-system-design.md`

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `app/assets/tailwind/tokens/_semantic.css` | Modify | Add modal CSS custom properties |
| `app/assets/tailwind/application.css` | Modify | Register tokens, add `::backdrop` styles |
| `app/javascript/controllers/modal_controller.js` | Create | Open/close, animation, backdrop click |
| `app/views/shared/_modal.html.erb` | Create | Reusable modal partial |
| `config/locales/en/modals.en.yml` | Create | Modal I18n keys |
| `spec/system/modal_spec.rb` | Create | System specs for modal behavior |

---

### Task 1: Add CSS Custom Properties for Modal

**Files:**

- Modify: `app/assets/tailwind/tokens/_semantic.css`
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Add modal tokens to `_semantic.css`**

Add after the toast positioning tokens in the `:root` block (after `--toast-z: 100;`), before the closing `}`:

```css
  /* --- Modal --- */
  --modal-backdrop: oklch(20.5% 0.016 265.755 / 50%);
  --modal-animation-duration: 200ms;
```

No `.dark` override needed — the semi-transparent dark backdrop works in both modes.

- [ ] **Step 2: Register tokens in `@theme inline` block**

Add to `app/assets/tailwind/application.css` inside the `@theme inline { }` block, after the toast positioning tokens, before the closing `}`:

```css
  /* Modal */
  --modal-backdrop: var(--modal-backdrop);
  --modal-animation-duration: var(--modal-animation-duration);
```

- [ ] **Step 3: Add dialog backdrop styles**

Add to `app/assets/tailwind/application.css` after the `@theme inline { }` block, before the workspace branding section:

```css
/* ==========================================================================
   Dialog / Modal Backdrop
   ========================================================================== */

dialog::backdrop {
  background: var(--modal-backdrop);
  opacity: 0;
  transition: opacity var(--modal-animation-duration) ease-out;
}

dialog[open]::backdrop {
  opacity: 1;
}
```

- [ ] **Step 4: Commit**

```bash
git add app/assets/tailwind/tokens/_semantic.css app/assets/tailwind/application.css
git commit -m "feat: add CSS custom properties for modal backdrop and animation

modal-backdrop and modal-animation-duration as semantic tokens.
Dialog ::backdrop transitions via CSS. Downstream projects customize
by editing token values."
```

---

### Task 2: Create Modal Stimulus Controller

**Files:**

- Create: `app/javascript/controllers/modal_controller.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/modal_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "panel"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.handleCancel = this.handleCancel.bind(this)
    this.handleClick = this.handleClick.bind(this)

    this.dialogTarget.addEventListener("cancel", this.handleCancel)
    this.dialogTarget.addEventListener("click", this.handleClick)

    if (this.openValue) {
      this.open()
    }
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.handleCancel)
    this.dialogTarget.removeEventListener("click", this.handleClick)

    if (this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  open() {
    this.dialogTarget.showModal()
    this.animateIn()
  }

  close() {
    this.animateOut(() => {
      this.dialogTarget.close()
    })
  }

  // Private

  handleCancel(event) {
    event.preventDefault()
    this.close()
  }

  handleClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  animateIn() {
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = "scale(1)"
      return
    }

    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = "scale(0.95)"
    requestAnimationFrame(() => {
      const duration = getComputedStyle(document.documentElement)
        .getPropertyValue("--modal-animation-duration").trim() || "200ms"
      this.panelTarget.style.transition = `opacity ${duration} ease-out, transform ${duration} ease-out`
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = "scale(1)"
    })
  }

  animateOut(callback) {
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "0"
      callback()
      return
    }

    const duration = getComputedStyle(document.documentElement)
      .getPropertyValue("--modal-animation-duration").trim() || "200ms"
    this.panelTarget.style.transition = `opacity ${duration} ease-in, transform ${duration} ease-in`
    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = "scale(0.95)"

    const ms = parseInt(duration, 10) || 200
    setTimeout(callback, ms)
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/modal_controller.js
git commit -m "feat: add modal Stimulus controller for native dialog

Open/close with scale+opacity animation, backdrop click detection,
Escape key via native cancel event, prefers-reduced-motion support.
Animation duration read from CSS custom property."
```

---

### Task 3: Create I18n Keys and Modal Partial

**Files:**

- Create: `config/locales/en/modals.en.yml`
- Create: `app/views/shared/_modal.html.erb`

- [ ] **Step 1: Create I18n keys**

Create `config/locales/en/modals.en.yml`:

```yaml
en:
  modals:
    close: "Close dialog"
```

- [ ] **Step 2: Create the modal partial**

Create `app/views/shared/_modal.html.erb`:

```erb
<%# locals: (title:, id: nil, size: :md) -%>
<%
  modal_id = id || "modal-#{SecureRandom.hex(4)}"
  size_class = case size
               when :sm then "max-w-sm"
               when :md then "max-w-lg"
               when :lg then "max-w-2xl"
               when :full then "max-w-4xl"
               else "max-w-lg"
               end
%>
<dialog data-modal-target="dialog"
        id="<%= modal_id %>"
        role="dialog"
        aria-modal="true"
        aria-labelledby="<%= modal_id %>-title"
        class="bg-transparent backdrop:bg-transparent p-4 sm:p-6">
  <div data-modal-target="panel"
       class="relative w-full <%= size_class %> mx-auto rounded-lg
              bg-surface-raised border border-border shadow-xl
              opacity-0 scale-95">
    <header class="flex items-center justify-between px-6 py-4 border-b border-border">
      <h2 id="<%= modal_id %>-title"
          class="text-lg font-semibold text-text-heading">
        <%= title %>
      </h2>
      <button data-action="click->modal#close"
              aria-label="<%= t('modals.close') %>"
              class="min-h-[44px] min-w-[44px] inline-flex items-center justify-center
                     rounded-md -m-2 hover:bg-surface-sunken
                     text-text-muted hover:text-text-body
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= icon(:x_mark, size: :md) %>
      </button>
    </header>
    <div class="px-6 py-4">
      <%= yield %>
    </div>
  </div>
</dialog>
```

- [ ] **Step 3: Commit**

```bash
git add config/locales/en/modals.en.yml app/views/shared/_modal.html.erb
git commit -m "feat: add reusable modal partial with configurable size and title

Native dialog element with panel header (title + close button),
yielded body content. Sizes: sm, md, lg, full. Uses icon() helper
for close button. ARIA labelledby links to title."
```

---

### Task 4: Add System Specs

**Files:**

- Create: `spec/system/modal_spec.rb`

- [ ] **Step 1: Create a test page for the modal**

The modal needs a page to render on for system tests. Add a test-only route and view. Create `app/views/pages/_modal_test.html.erb` (this will be used via the existing `about` page or a dedicated test approach).

Actually, the simplest approach: use the system spec to visit a page and inject a modal via JavaScript, or create a lightweight test helper.

Better approach: Add a temporary modal to the `about` page action for testing, then remove it after specs are written. But that's messy.

Best approach: The system spec can test the modal by rendering it on any existing page. Since the modal partial is a shared partial, we can add it to any view. For testing, we'll add a simple modal to the `home` page that's always present but hidden.

Create the spec that tests the modal behavior. The spec will need a page with a modal on it. The simplest way: create a dedicated test partial and mount it temporarily. But actually, the cleanest approach for system specs is to use a controller test helper.

Let's use the `about` page — it's a simple static page. We'll add a modal to it just for testing purposes, then remove it when we're done.

Instead, let's create the spec using JavaScript injection to avoid modifying production views:

Create `spec/system/modal_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Modal system", type: :system do
  before do
    visit root_path
    # Inject a test modal into the page via JavaScript
    page.execute_script(<<~JS)
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-controller', 'modal');
      wrapper.innerHTML = `
        <button data-action="click->modal#open" id="test-modal-trigger">Open Modal</button>
        <dialog data-modal-target="dialog" id="test-modal"
                role="dialog" aria-modal="true" aria-labelledby="test-modal-title"
                class="bg-transparent backdrop:bg-transparent p-4"
                style="--modal-backdrop: rgba(0,0,0,0.5); --modal-animation-duration: 50ms;">
          <div data-modal-target="panel"
               style="opacity:0; transform:scale(0.95); background:white; padding:24px; border-radius:8px; min-width:300px;">
            <h2 id="test-modal-title">Test Modal</h2>
            <p>Modal content for testing</p>
            <button data-action="click->modal#close" id="test-modal-close" aria-label="Close dialog">Close</button>
            <a href="#" id="test-modal-link">A focusable link</a>
          </div>
        </dialog>
      `;
      document.body.appendChild(wrapper);
    JS
  end

  describe "opening" do
    it "opens when trigger button is clicked" do
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end
  end

  describe "closing" do
    before do
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "closes when close button is clicked" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on Escape key" do
      send_keys :escape
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on backdrop click" do
      # Click the dialog element itself (the backdrop area)
      # The dialog is full-viewport, so clicking at coordinates outside the panel hits the backdrop
      page.driver.with_playwright_page do |pw_page|
        # Click in the top-left corner of the viewport — outside the centered panel
        pw_page.mouse.click(5, 5)
      end
      expect(page).to have_no_css("dialog[open]")
    end
  end

  describe "accessibility" do
    before do
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "has role=dialog" do
      expect(page).to have_css("dialog[role='dialog']")
    end

    it "has aria-modal=true" do
      expect(page).to have_css("dialog[aria-modal='true']")
    end

    it "has aria-labelledby pointing to title" do
      expect(page).to have_css("dialog[aria-labelledby='test-modal-title']")
      expect(page).to have_css("h2#test-modal-title", text: "Test Modal")
    end

    it "close button is keyboard accessible" do
      close_btn = find("#test-modal-close")
      close_btn.send_keys(:enter)
      expect(page).to have_no_css("dialog[open]")
    end
  end
end
```

- [ ] **Step 2: Run the system specs**

Run: `bundle exec rspec spec/system/modal_spec.rb`
Expected: All pass. If the backdrop click test fails (coordinate-based clicks can be flaky), adjust the click coordinates or use a different approach.

- [ ] **Step 3: Commit**

```bash
git add spec/system/modal_spec.rb
git commit -m "test: add system specs for modal open, close, Escape, backdrop, accessibility

Tests use JavaScript-injected modal to avoid modifying production
views. Covers open/close, Escape key, backdrop click, ARIA attributes,
and keyboard accessibility."
```

---

### Task 5: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec --order defined`
Expected: All specs pass (810+), 0 failures

- [ ] **Step 2: Run with CI=true to verify axe audits pass**

Run: `CI=true bundle exec rspec spec/system/modal_spec.rb`
Expected: All pass (the injected modal uses inline styles, axe may flag contrast on the test content — if so, add sufficient styling to the injected HTML)

---

## Verification

After all tasks are complete:

1. **Full suite:** `bundle exec rspec --order defined` — all specs green
2. **Manual test:** Add a temporary modal to any view:
   ```erb
   <div data-controller="modal">
     <button data-action="click->modal#open">Open Modal</button>
     <%= render "shared/modal", title: "Test" do %>
       <p>Hello from modal!</p>
     <% end %>
   </div>
   ```
3. **Open/close:** Click button → modal opens with animation → click close → closes with animation
4. **Escape:** Open modal → press Escape → closes with animation
5. **Backdrop:** Open modal → click outside panel → closes
6. **Focus trap:** Open modal → Tab through elements → focus stays in modal (native browser behavior)
7. **Reduced motion:** Enable reduced motion in OS settings → modal opens/closes instantly
8. **Keyboard:** Tab to close button → Enter → modal closes
