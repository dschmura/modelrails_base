# Modal System

A reusable modal built on the native `<dialog>` element. The browser handles focus trap, Escape key, and inert background. A thin Stimulus controller adds animations and backdrop click handling.

## Quick Start

Wrap a trigger button and the modal partial in a `data-controller="modal"` container:

```erb
<div data-controller="modal">
  <button data-action="click->modal#open">Edit Item</button>

  <%= render "shared/modal", title: "Edit Item" do %>
    <p>Your content here — forms, text, anything.</p>
  <% end %>
</div>
```

Click the button to open the modal. Close via the X button, Escape key, or clicking the backdrop.

## Partial Options

```erb
<%= render "shared/modal", title:, id:, size:, description: do %>
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `title` | String | required | Modal title, rendered in `<h2>`, linked via `aria-labelledby` |
| `id` | String | auto-generated | DOM ID for the dialog. Auto-generates `modal-XXXXXXXX` if omitted |
| `size` | Symbol | `:md` | Panel width — see sizes below |
| `description` | String | nil | Optional description text, linked via `aria-describedby` |

### Sizes

| Size | Tailwind class | Approximate width |
| --- | --- | --- |
| `:sm` | `max-w-sm` | 384px |
| `:md` | `max-w-lg` | 512px |
| `:lg` | `max-w-2xl` | 672px |
| `:full` | `max-w-4xl` | 896px |

### Description

For modals with significant consequences (confirmations, destructive actions), provide a description:

```erb
<%= render "shared/modal",
      title: "Delete Workspace",
      description: "This action cannot be undone. All projects and data will be permanently removed." do %>
  <div class="flex gap-3 justify-end">
    <button data-action="click->modal#close" class="...">Cancel</button>
    <%= button_to "Delete", workspace_path(@workspace), method: :delete, class: "..." %>
  </div>
<% end %>
```

The description renders as a paragraph above the yielded content and is linked to the dialog via `aria-describedby` for screen readers.

## Usage Patterns

### Inline content (most common)

The modal content is already in the page HTML. The dialog is hidden until opened:

```erb
<div data-controller="modal">
  <button data-action="click->modal#open">Settings</button>

  <%= render "shared/modal", title: t(".settings") do %>
    <%= form_with model: @settings, url: settings_path do |f| %>
      <%= f.text_field :name, label: t(".name") %>
      <%= f.submit t(".save"), class: "w-full" %>
    <% end %>
  <% end %>
</div>
```

### Turbo Frame loaded content

Load modal content from the server on demand. The modal opens automatically when the frame loads:

```erb
<%# Link triggers Turbo Frame fetch %>
<%= link_to "Edit", edit_item_path(@item), data: { turbo_frame: "modal-content" } %>

<%# Modal opens on connect when content arrives %>
<div data-controller="modal" data-modal-open-value="true">
  <%= render "shared/modal", title: "Edit Item" do %>
    <%= turbo_frame_tag "modal-content" %>
  <% end %>
</div>
```

Set `data-modal-open-value="true"` so the modal opens as soon as the Stimulus controller connects (when the Turbo Frame content arrives).

### Adding footer buttons

The modal yields a single content block. Add your own footer with action buttons:

```erb
<%= render "shared/modal", title: "Confirm Action" do %>
  <p>Are you sure you want to proceed?</p>

  <div class="flex gap-3 justify-end mt-6 pt-4 border-t border-border">
    <button data-action="click->modal#close"
            class="min-h-[44px] px-4 rounded-md border border-border
                   text-text-body hover:bg-surface-sunken
                   focus:outline-none focus:ring-2 focus:ring-interactive-focus">
      Cancel
    </button>
    <button class="min-h-[44px] px-4 rounded-md bg-interactive
                   hover:bg-interactive-hover text-text-on-interactive
                   focus:outline-none focus:ring-2 focus:ring-interactive-focus">
      Confirm
    </button>
  </div>
<% end %>
```

### Programmatic open/close

Open or close from other Stimulus controllers using `outlets` or DOM events:

```javascript
// From another controller
const modalController = this.application.getControllerForElementAndIdentifier(
  document.querySelector('[data-controller="modal"]'),
  'modal'
)
modalController.open()
```

## Confirmation Dialog

A pre-built partial for destructive action confirmations. Uses the modal system — no additional JavaScript.

```erb
<div data-controller="modal">
  <button data-action="click->modal#open"
          class="text-danger">Delete Workspace</button>

  <%= render "shared/confirm_dialog",
        title: t(".confirm_delete_title"),
        message: t(".confirm_delete_message"),
        confirm_text: t(".delete"),
        confirm_url: workspace_path(@workspace),
        confirm_method: :delete,
        variant: :danger %>
</div>
```

### Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `title` | String | required | Dialog title |
| `message` | String | required | Explanation of what will happen |
| `confirm_text` | String | required | Confirm button label (e.g., "Delete", "Remove") |
| `confirm_url` | String | required | URL for the confirm action |
| `confirm_method` | Symbol | `:delete` | HTTP method (`:delete`, `:post`, `:patch`) |
| `variant` | Symbol | `:danger` | `:danger` (red confirm button, warning icon) or `:default` (blue confirm, info icon) |
| `cancel_text` | String | "Cancel" (I18n) | Cancel button label |
| `id` | String | auto-generated | DOM ID for the dialog |

### Variants

- **`:danger`** — Red confirm button with exclamation triangle icon. Use for destructive actions (delete, remove, revoke).
- **`:default`** — Blue confirm button with info icon. Use for non-destructive confirmations (approve, publish, send).

The Cancel button always closes the modal without submitting. The Confirm button is a `button_to` that submits a standard Rails form.

## Customization

### Changing the backdrop

Edit `app/assets/tailwind/tokens/_semantic.css`:

```css
--modal-backdrop: oklch(20.5% 0.016 265.755 / 50%);  /* darken or lighten */
```

### Changing animation speed

```css
--modal-animation-duration: 200ms;  /* faster or slower */
```

### Changing the panel background

The panel uses `bg-surface-overlay` from the semantic token system. To change modal backgrounds independently of card backgrounds, edit the `--color-surface-overlay` token in `_semantic.css`.

See `docs/theming.md` for full details on the token system.

## Accessibility

The modal system targets WCAG 2.2 Level AAA.

### Focus management

Native `<dialog>` with `showModal()` provides browser-managed focus trap:

- Focus moves to the first focusable element inside the dialog on open
- Tab/Shift+Tab cycles through focusable elements within the dialog only
- Background elements are inert (cannot be focused or clicked)
- Focus returns to the trigger element on close

No custom JavaScript focus trap is needed — the browser handles all of this natively.

### Keyboard

- **Escape** closes the modal (native browser behavior, controller adds exit animation)
- **Tab / Shift+Tab** cycles within the modal (native focus trap)
- **Enter / Space** on the close button dismisses the modal

### Screen readers

- `role="dialog"` + `aria-modal="true"` announce the modal context
- `aria-labelledby` links the dialog to its title `<h2>`
- `aria-describedby` links to the description paragraph when provided
- Close button has `aria-label` from I18n (`modals.close`)

### Touch targets

Close button meets the WCAG AAA minimum of 44x44 pixels (`min-h-[44px] min-w-[44px]`).

### Reduced motion

When `prefers-reduced-motion: reduce` is set, the scale animation is skipped. The panel appears and disappears instantly with no transitions.

### Overflow

The modal body has `overflow-y-auto` with `max-h-[calc(100vh-3rem)]` on the panel. Long content scrolls within the modal rather than overflowing the viewport.

## Architecture

### Files

| File | Purpose |
| --- | --- |
| `app/javascript/controllers/modal_controller.js` | Open/close, animation, backdrop click, Escape handling |
| `app/views/shared/_modal.html.erb` | Reusable partial with title, size, description, yielded content |
| `app/assets/tailwind/tokens/_semantic.css` | `--modal-backdrop`, `--modal-animation-duration` tokens |
| `app/assets/tailwind/application.css` | `dialog::backdrop` transition styles with `@starting-style` |
| `config/locales/en/modals.en.yml` | Close button aria-label |

### How it works

1. User clicks trigger button → `modal#open` action fires
2. Controller calls `dialogTarget.showModal()` — browser adds dialog to top layer, enables focus trap, makes background inert
3. Controller runs panel enter animation (opacity + scale via `requestAnimationFrame`)
4. CSS `@starting-style` animates the `::backdrop` from transparent to semi-opaque
5. User interacts with modal content
6. Close triggered by: close button (`modal#close`), Escape key (native `cancel` event), or backdrop click
7. Controller runs panel exit animation, then calls `dialogTarget.close()`
8. Browser removes dialog from top layer, restores focus to trigger element

### Multiple modals

Opening a second modal while one is already open is not supported. The controller logs a console warning if this is attempted. Native `<dialog>` does support stacking, but backdrop behavior and focus management become complex. If you need stacked dialogs, consider whether the UX could be simplified to avoid it.

### Hotwire Native

For native mobile apps using Hotwire Native, the `<dialog>` element renders in the web view. For a native-feeling modal presentation, a bridge component could intercept the modal open and present a native sheet instead. This is not implemented — the web modal works in Hotwire Native web views as-is.

## Troubleshooting

### Modal doesn't open

- Verify the trigger button has `data-action="click->modal#open"`
- Verify the container div has `data-controller="modal"`
- Verify the dialog has `data-modal-target="dialog"`
- Verify the panel div has `data-modal-target="panel"`
- Check the browser console for Stimulus connection errors

### Modal opens but content is invisible

- The panel starts with `opacity-0 scale-95` classes (initial state for animation)
- If JavaScript fails to load, the panel stays invisible — this is intentional graceful degradation
- Check that the Stimulus controller is connecting (look for `modal` in Stimulus debug output)

### Backdrop doesn't animate

- The `::backdrop` entry animation requires `@starting-style` CSS support (Chrome 117+, Safari 17.4+, Firefox 129+)
- Older browsers show the backdrop instantly (no transition) — this is acceptable degradation
- The exit backdrop animation is instant in all browsers (known `<dialog>` limitation — the backdrop is removed when the dialog leaves the top layer)

### Long content overflows

- The modal body has `overflow-y-auto` — content should scroll
- If overflow doesn't work, check that the panel has `flex flex-col` and the body has `flex-1`
