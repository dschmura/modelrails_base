# Modal System — Design Spec

## Problem

The app has no reusable modal infrastructure. Features that need modals (avatar editing, confirmations, inline forms) would each need to build their own dialog, focus management, backdrop, and keyboard handling from scratch.

## Solution

A reusable modal system built on the native `<dialog>` element with a thin Stimulus controller for animations. The browser handles focus trap, Escape key, inert background, and top-layer positioning natively. CSS custom properties control backdrop color and animation duration for downstream customization.

## Design Decisions

### Why native `<dialog>` instead of `<div role="dialog">`?

The native `<dialog>` element with `showModal()` provides built-in focus trap (no custom `focus_trap.js` needed), built-in Escape key handling, built-in top-layer positioning (no z-index management), and inert background (elements behind the dialog can't be focused or clicked). Browser support is universal in 2026. This eliminates hundreds of lines of custom JavaScript that the agent_os project had to maintain.

### Why CSS custom properties for animation?

Consistent with the toast system approach. Downstream projects can change `--modal-backdrop` and `--modal-animation-duration` in `_semantic.css` without editing the controller or partial.

### Why a shared partial instead of a ViewComponent?

Project convention: ViewComponents only when reused across unrelated views with complex logic. A modal is a simple wrapper — a partial with `yield` is sufficient. The Stimulus controller handles behavior, the partial handles structure.

## Architecture

### Modal Controller (`app/javascript/controllers/modal_controller.js`)

Stimulus controller managing open/close animations on the native `<dialog>` element.

**Targets:**

- `dialog` — the `<dialog>` element
- `panel` — the inner panel div (for scale/opacity animation)

**Values:**

- `open` (Boolean, default: false) — when true, opens the modal on connect (for Turbo Frame loaded content)

**Actions:**

- `open()` — calls `dialogTarget.showModal()`, runs enter animation on panel
- `close()` — runs exit animation on panel, then calls `dialogTarget.close()`

**Event handling:**

- `cancel` event on dialog (native Escape key) — intercepts to run exit animation before closing
- `click` event on dialog — detects backdrop clicks via `event.target === dialogTarget` (native `<dialog>` fires click on itself when backdrop is clicked, not on child elements)

**Animation:**

- Enter: panel transitions from `opacity-0 scale-95` to `opacity-100 scale-100` (200ms ease-out)
- Exit: panel transitions from `opacity-100 scale-100` to `opacity-0 scale-95` (200ms ease-in)
- `prefers-reduced-motion`: skips scale transition, uses instant opacity change
- Duration read from CSS custom property `--modal-animation-duration`

**Lifecycle:**

- `connect()` — checks `openValue`, opens if true; binds event handlers
- `disconnect()` — cleans up event handlers, closes dialog if open

### Modal Partial (`app/views/shared/_modal.html.erb`)

```erb
<%# locals: (title:, id: nil, size: :md) %>
```

Renders a `<dialog>` element wrapping a panel with header (title + close button) and body (yielded content).

**Parameters:**

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |
| `title` | String | required | Modal title, rendered in `<h2>`, linked via `aria-labelledby` |
| `id` | String | nil | Optional DOM ID for the dialog (useful for Turbo Frame targeting) |
| `size` | Symbol | `:md` | Panel width: `:sm` (max-w-sm), `:md` (max-w-lg), `:lg` (max-w-2xl), `:full` (max-w-4xl) |

**Usage — inline content:**

```erb
<div data-controller="modal">
  <button data-action="click->modal#open">Edit</button>

  <%= render "shared/modal", title: "Edit Item" do %>
    <p>Form content here</p>
  <% end %>
</div>
```

**Usage — Turbo Frame loaded:**

```erb
<%= link_to "Edit", edit_thing_path, data: { turbo_frame: "modal-content" } %>

<div data-controller="modal" data-modal-open-value="true">
  <%= render "shared/modal", title: "Edit Item" do %>
    <%= turbo_frame_tag "modal-content" %>
  <% end %>
</div>
```

### HTML Structure

```html
<dialog data-modal-target="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title-[id]"
        class="bg-transparent backdrop:bg-transparent">
  <div data-modal-target="panel"
       class="relative w-full [size-class] mx-auto rounded-lg
              bg-surface-raised border border-border shadow-xl
              opacity-0 scale-95">
    <header class="flex items-center justify-between px-6 py-4 border-b border-border">
      <h2 id="modal-title-[id]" class="text-lg font-semibold text-text-heading">Title</h2>
      <button data-action="click->modal#close"
              aria-label="[I18n close]"
              class="min-h-[44px] min-w-[44px] inline-flex items-center justify-center
                     rounded-md -m-2 hover:bg-surface-sunken
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= icon(:x_mark, size: :md) %>
      </button>
    </header>
    <div class="px-6 py-4">
      <!-- yielded content -->
    </div>
  </div>
</dialog>
```

The `<dialog>` itself is styled transparent — the visual modal is the inner panel div. The `::backdrop` pseudo-element provides the overlay.

### CSS Custom Properties

Add to `_semantic.css` `:root` block:

```css
--modal-backdrop: oklch(20.5% 0.016 265.755 / 50%);
--modal-animation-duration: 200ms;
```

No `.dark` override needed — the semi-transparent dark backdrop works in both modes.

Register in `@theme inline` block in `application.css`.

Add to `application.css` for backdrop styling:

```css
dialog::backdrop {
  background: var(--modal-backdrop);
  opacity: 0;
  transition: opacity var(--modal-animation-duration) ease-out;
}
dialog[open]::backdrop {
  opacity: 1;
}
```

### Backdrop Click Detection

Native `<dialog>` fires a `click` event on the `<dialog>` element itself when the user clicks the backdrop area (outside the panel). The controller checks `event.target === this.dialogTarget` — if true, the click was on the backdrop, not on a child element. This is simpler than maintaining a separate backdrop div.

### I18n Keys

Add to the appropriate locale file:

```yaml
en:
  modals:
    close: "Close dialog"
```

## Accessibility (WCAG AAA)

- Native `<dialog>` with `showModal()` provides browser-managed focus trap — no custom JS needed
- Focus moves to the first focusable element inside the dialog on open (native behavior)
- Focus returns to the trigger element on close (native behavior)
- Escape key closes the dialog (native behavior, controller adds exit animation)
- `role="dialog"` + `aria-modal="true"` explicit for older screen readers
- `aria-labelledby` links dialog to its title `<h2>`
- Close button: 44px touch target, `aria-label` from I18n
- Background is inert while modal is open (native `showModal()` behavior)
- `prefers-reduced-motion`: scale animation skipped, instant opacity
- Semantic token colors ensure contrast compliance

## Files

| File | Action | Purpose |
| ---- | ------ | ------- |
| `app/javascript/controllers/modal_controller.js` | Create | Open/close, animation, backdrop click |
| `app/views/shared/_modal.html.erb` | Create | Reusable modal partial |
| `app/assets/tailwind/tokens/_semantic.css` | Modify | Add modal CSS custom properties |
| `app/assets/tailwind/application.css` | Modify | Register tokens, add `::backdrop` styles |
| `config/locales/en/modals.en.yml` | Create | Modal I18n keys |
| `spec/system/modal_spec.rb` | Create | System specs for modal behavior |

## Testing Strategy

**System specs:**

- Modal opens when trigger button is clicked
- Modal closes when close button is clicked
- Modal closes on Escape key
- Modal closes on backdrop click
- Content is visible when modal is open
- ARIA attributes present (role=dialog, aria-modal, aria-labelledby)
- Close button is keyboard accessible (Tab + Enter)
- Modal works with Turbo Frame loaded content (open on connect)

## Out of Scope

- Confirmation dialog variant (future — simple extension of the base modal)
- Stacked/nested modals
- Modal with footer actions (consumers add their own footer in the yielded content)
- Specific modal consumers (avatar editor, resource editor — separate specs)
