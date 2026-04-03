# Toast Configurability Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the toast system configurable via a single initializer so downstream projects can customize types, icons, timing, positioning, and colors without editing partials.

**Architecture:** A `config/initializers/toasts.rb` defines all toast types, timing, and icon mappings. Partials read from this config instead of using case statements. Inline SVGs are replaced with `icon()` helper calls. CSS custom properties handle positioning. The Stimulus controller reads stagger delay from a data attribute.

**Tech Stack:** Rails 8.1, Stimulus, TailwindCSS 4, IconHelper/IconRegistry

**Spec:** `docs/superpowers/specs/2026-04-02-toast-configurability-design.md`

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `config/initializers/toasts.rb` | Create | Central config for types, timing |
| `app/assets/tailwind/tokens/_semantic.css` | Modify | Add toast positioning custom properties |
| `app/assets/tailwind/application.css` | Modify | Register positioning tokens in `@theme inline` |
| `app/views/shared/_toast_pill.html.erb` | Rewrite | Config lookups, `icon()` helper |
| `app/views/shared/_toast_card.html.erb` | Rewrite | Config lookups, `icon()` helper |
| `app/views/shared/_toasts.html.erb` | Modify | Config-driven type filtering, CSS custom property positioning |
| `app/controllers/concerns/toastable.rb` | Modify | Config-driven routing |
| `app/javascript/controllers/toast_pill_controller.js` | Modify | Read stagger from data attribute |
| `spec/controllers/concerns/toastable_spec.rb` | Verify | Existing specs still pass |

---

### Task 1: Create Toast Config Initializer

**Files:**

- Create: `config/initializers/toasts.rb`

- [ ] **Step 1: Create the initializer**

Create `config/initializers/toasts.rb`:

```ruby
Rails.application.config.toasts = ActiveSupport::InheritableOptions.new(
  timing: {
    ms_per_word: 500,
    buffer_ms: 1000,
    min_ms: 5000,
    max_ms: 15000,
    stagger_ms: 2000
  },
  types: {
    notice: {
      tier: :pill,
      icon: :check_circle,
      icon_color: "text-success-icon",
      progress: "bg-success-progress"
    },
    success: {
      tier: :pill,
      icon: :check_circle,
      icon_color: "text-success-icon",
      progress: "bg-success-progress"
    },
    info: {
      tier: :pill,
      icon: :information_circle,
      icon_color: "text-info-icon",
      progress: "bg-info-progress"
    },
    alert: {
      tier: :card,
      icon: :exclamation_triangle,
      icon_color: "text-warning-icon",
      bg: "bg-warning-surface",
      border: "border-warning-border",
      text: "text-warning",
      close_hover: "hover:bg-warning-hover"
    },
    error: {
      tier: :card,
      icon: :exclamation_circle,
      icon_color: "text-danger-icon",
      bg: "bg-danger-surface",
      border: "border-danger-border",
      text: "text-danger",
      close_hover: "hover:bg-danger-hover"
    }
  }
)
```

- [ ] **Step 2: Verify config loads**

Run: `bundle exec rails runner "puts Rails.application.config.toasts[:types].keys.inspect"`
Expected: `[:notice, :success, :info, :alert, :error]`

- [ ] **Step 3: Commit**

```bash
git add config/initializers/toasts.rb
git commit -m "feat: add toast config initializer for types and timing

Central config for all toast behavior: type-to-tier mapping,
icon names, color classes, and timing formula values.
Downstream projects customize by editing this one file."
```

---

### Task 2: Add CSS Custom Properties for Toast Positioning

**Files:**

- Modify: `app/assets/tailwind/tokens/_semantic.css`
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Add positioning tokens to `_semantic.css`**

Add after the toast token section in the `:root` block (after the `--color-text-on-toast` line), before the closing `}`:

```css
  /* --- Toast positioning --- */
  --toast-pill-top: 5rem;
  --toast-card-bottom: 1rem;
  --toast-z: 100;
```

These do NOT need a `.dark` override — positioning doesn't change with theme.

- [ ] **Step 2: Register in `@theme inline` block**

Add to `app/assets/tailwind/application.css` inside the `@theme inline { }` block, after the toast pill color tokens (after the `--color-text-on-toast` line), before the closing `}`:

```css
  /* Toast positioning */
  --toast-pill-top: var(--toast-pill-top);
  --toast-card-bottom: var(--toast-card-bottom);
  --toast-z: var(--toast-z);
```

- [ ] **Step 3: Commit**

```bash
git add app/assets/tailwind/tokens/_semantic.css app/assets/tailwind/application.css
git commit -m "feat: add CSS custom properties for toast positioning

toast-pill-top, toast-card-bottom, toast-z as semantic tokens.
Downstream projects change header offsets by editing one value."
```

---

### Task 3: Refactor Toast Pill Partial to Use Config and icon()

**Files:**

- Rewrite: `app/views/shared/_toast_pill.html.erb`

- [ ] **Step 1: Rewrite the pill partial**

Replace the full contents of `app/views/shared/_toast_pill.html.erb`:

```erb
<%# locals: (type:, message:) -%>
<%
  config = Rails.application.config.toasts
  timing = config[:timing]
  type_config = config[:types][type.to_sym] || config[:types][:notice]

  timeout = [timing[:min_ms], message.split.size * timing[:ms_per_word] + timing[:buffer_ms]].max.clamp(timing[:min_ms], timing[:max_ms])
%>
<div data-controller="toast-pill"
     data-toast-pill-timeout-value="<%= timeout %>"
     data-toast-pill-stagger-value="<%= timing[:stagger_ms] %>"
     data-action="mouseenter->toast-pill#pause mouseleave->toast-pill#resume"
     role="status"
     aria-live="polite"
     aria-atomic="true"
     class="pointer-events-auto rounded-full bg-surface-toast shadow-lg
            px-4 py-2 flex items-center gap-2
            max-w-sm max-w-[calc(100vw-2rem)] overflow-hidden">
  <div class="shrink-0 <%= type_config[:icon_color] %>">
    <%= icon(type_config[:icon], size: :sm) %>
  </div>
  <p class="text-sm font-medium text-text-on-toast whitespace-nowrap"><%= message %></p>
  <div class="absolute bottom-0 left-0 right-0 h-0.5">
    <div data-toast-pill-target="progress" class="h-full <%= type_config[:progress] %>" style="width: 100%;"></div>
  </div>
</div>
```

- [ ] **Step 2: Run toast specs to verify**

Run: `bundle exec rspec spec/system/toast_spec.rb spec/system/static_pages_spec.rb spec/requests/toast_rendering_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_toast_pill.html.erb
git commit -m "refactor: toast pill reads from config, uses icon() helper

Replace case statements with config hash lookups. Replace inline
SVGs with icon() helper calls. Pass stagger_ms as data attribute."
```

---

### Task 4: Refactor Toast Card Partial to Use Config and icon()

**Files:**

- Rewrite: `app/views/shared/_toast_card.html.erb`

- [ ] **Step 1: Rewrite the card partial**

Replace the full contents of `app/views/shared/_toast_card.html.erb`:

```erb
<%# locals: (type:, message:) -%>
<%
  type_config = Rails.application.config.toasts[:types][type.to_sym] || Rails.application.config.toasts[:types][:error]
%>
<div data-controller="toast-card"
     role="alert"
     aria-live="assertive"
     aria-atomic="true"
     class="w-96 max-w-[calc(100vw-2rem)] pointer-events-auto rounded-lg border shadow-lg overflow-hidden <%= type_config[:bg] %> <%= type_config[:border] %>">
  <div class="flex items-start gap-3 p-4">
    <div class="shrink-0 mt-0.5 <%= type_config[:icon_color] %>">
      <%= icon(type_config[:icon], size: :lg) %>
    </div>
    <p class="flex-1 text-sm leading-relaxed <%= type_config[:text] %>"><%= message %></p>
    <button type="button"
            aria-label="<%= t('toasts.close') %>"
            data-action="click->toast-card#dismiss"
            class="shrink-0 min-h-[44px] min-w-[44px] inline-flex items-center justify-center rounded-md -m-1 <%= type_config[:close_hover] %> focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-current">
      <%= icon(:x_mark, size: :md) %>
    </button>
  </div>
</div>
```

- [ ] **Step 2: Run toast specs to verify**

Run: `bundle exec rspec spec/system/toast_spec.rb spec/system/static_pages_spec.rb spec/requests/toast_rendering_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_toast_card.html.erb
git commit -m "refactor: toast card reads from config, uses icon() helper

Replace case statements with config hash lookups. Replace inline
SVGs with icon() helper for warning, error, and close icons."
```

---

### Task 5: Refactor Toast Container to Use Config and CSS Properties

**Files:**

- Modify: `app/views/shared/_toasts.html.erb`

- [ ] **Step 1: Rewrite the container partial**

Replace the full contents of `app/views/shared/_toasts.html.erb`:

```erb
<%
  toast_types = Rails.application.config.toasts[:types]
%>
<%# Top-center: success/info pills %>
<div id="toast-pills"
     aria-label="<%= t('toasts.pill_aria_label') %>"
     class="fixed top-[var(--toast-pill-top)] left-1/2 -translate-x-1/2 z-[var(--toast-z)]
            flex flex-col items-center gap-2
            pointer-events-none">
  <% flash.each do |type, message| %>
    <% next unless toast_types.dig(type.to_sym, :tier) == :pill %>
    <%= render "shared/toast_pill", type: type, message: message %>
  <% end %>
</div>

<%# Bottom-center: warning/error cards %>
<div id="toast-cards"
     aria-label="<%= t('toasts.card_aria_label') %>"
     class="fixed bottom-[var(--toast-card-bottom)] left-1/2 -translate-x-1/2 z-[var(--toast-z)]
            flex flex-col items-center gap-3 pb-[env(safe-area-inset-bottom)]
            max-w-[calc(100vw-2rem)]
            pointer-events-none">
  <% flash.each do |type, message| %>
    <% next unless toast_types.dig(type.to_sym, :tier) == :card %>
    <%= render "shared/toast_card", type: type, message: message %>
  <% end %>
</div>
```

- [ ] **Step 2: Run toast specs to verify**

Run: `bundle exec rspec spec/system/toast_spec.rb spec/system/static_pages_spec.rb spec/requests/toast_rendering_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_toasts.html.erb
git commit -m "refactor: toast container uses config-driven filtering and CSS properties

Type filtering reads tier from config instead of hardcoded arrays.
Positioning uses CSS custom properties (toast-pill-top, toast-card-bottom,
toast-z) instead of hardcoded Tailwind values."
```

---

### Task 6: Refactor Toastable Concern to Use Config

**Files:**

- Modify: `app/controllers/concerns/toastable.rb`
- Verify: `spec/controllers/concerns/toastable_spec.rb`

- [ ] **Step 1: Update the Toastable concern**

Replace the full contents of `app/controllers/concerns/toastable.rb`:

```ruby
module Toastable
  extend ActiveSupport::Concern

  private

  def toast_stream(type, message)
    type_config = Rails.application.config.toasts[:types][type.to_sym]
    tier = type_config&.dig(:tier) || :card
    target = tier == :pill ? "toast-pills" : "toast-cards"
    partial = tier == :pill ? "shared/toast_pill" : "shared/toast_card"
    turbo_stream.append(target, partial: partial, locals: { type: type, message: message })
  end

  def success_toast(message)
    toast_stream("success", message)
  end

  def notice_toast(message)
    toast_stream("notice", message)
  end

  def info_toast(message)
    toast_stream("info", message)
  end

  def error_toast(message)
    toast_stream("error", message)
  end

  def warning_toast(message)
    toast_stream("alert", message)
  end
end
```

- [ ] **Step 2: Run Toastable specs to verify**

Run: `bundle exec rspec spec/controllers/concerns/toastable_spec.rb`
Expected: 3 examples, 0 failures

- [ ] **Step 3: Commit**

```bash
git add app/controllers/concerns/toastable.rb
git commit -m "refactor: Toastable concern reads tier from config

Replace hardcoded type arrays with config hash lookup.
Unknown types default to card tier."
```

---

### Task 7: Update Pill Controller to Read Stagger from Data Attribute

**Files:**

- Modify: `app/javascript/controllers/toast_pill_controller.js`

- [ ] **Step 1: Add stagger value and update staggerDelay**

In `app/javascript/controllers/toast_pill_controller.js`, replace the `static values` line:

```javascript
  static values = { timeout: { type: Number, default: 5000 }, stagger: { type: Number, default: 2000 } }
```

Replace the `staggerDelay()` method:

```javascript
  staggerDelay() {
    const container = this.element.parentElement
    if (!container) return 0
    const siblings = [...container.querySelectorAll('[data-controller="toast-pill"]')]
    const index = siblings.indexOf(this.element)
    return index * this.staggerValue
  }
```

- [ ] **Step 2: Run toast system specs to verify**

Run: `bundle exec rspec spec/system/toast_spec.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/toast_pill_controller.js
git commit -m "refactor: pill controller reads stagger delay from data attribute

Replace hardcoded 2000ms with configurable stagger Stimulus value.
The pill partial passes the value from the toast config initializer."
```

---

### Task 8: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All specs pass (698), 0 failures.

- [ ] **Step 2: Verify about page shows all 5 toast types**

Run: `bundle exec rails runner "puts Rails.application.config.toasts[:types].keys.inspect"`
Expected: `[:notice, :success, :info, :alert, :error]`

---

## Verification

After all tasks are complete:

1. **Full suite:** `bundle exec rspec` — all specs green
2. **About page:** Visit `/about` — all 5 toast types render correctly with icons from the icon system
3. **Config change test:** Temporarily change an icon name in the initializer, restart server, verify the new icon renders
4. **Positioning test:** Temporarily change `--toast-pill-top` in `_semantic.css`, verify pill moves
5. **Timing test:** Change `stagger_ms` in initializer, verify pills stagger differently on `/about`
