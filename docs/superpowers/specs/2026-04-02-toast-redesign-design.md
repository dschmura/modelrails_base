# Two-Tier Toast Notification System — Design Spec

## Problem

The current toast system uses a single floating card format positioned at `fixed top-16 right-0`, which overlaps header dropdowns (user menu, workspace switcher) and other interactive elements in the top-right corner. All toast types share the same visual treatment regardless of severity. Success confirmations and critical errors look structurally identical, differing only in color.

## Solution

Replace the single-format toast system with a two-tier approach:

- **Tier 1 (Pill):** Compact, auto-dismissing pill for success/info confirmations. Top-center position, clear of all header elements.
- **Tier 2 (Card):** Persistent, dismissible card for warnings/errors. Bottom-center position, non-blocking but unmissable.

This follows the Basecamp/37signals pattern: brief confirmations are lightweight and transient; errors are persistent and demand acknowledgment.

## Design Decisions

### Why two tiers instead of one format in a new position?

Success confirmations and error messages have fundamentally different requirements. Success messages are supplementary — the UI already changed to reflect the action. Error messages carry essential information the user needs to act on. A single format either over-presents confirmations (heavy card for "Settings saved") or under-presents errors (tiny pill for "Storage limit reached"). Two tiers match presentation to severity.

### Why top-center for pills?

- Clears all header dropdowns (user menu, workspace switcher are right-aligned)
- Centered position is visible without being in the way
- Matches Basecamp's flash notice pattern
- Small footprint means minimal content overlap

### Why bottom-center for cards?

- Completely avoids header/dropdown overlap
- Center axis creates visual cohesion with top-center pills
- Persistent cards at the bottom don't push content or interfere with navigation
- On mobile, bottom-center and bottom-right are effectively identical (nearly full-width)

### WCAG 2.2 Level AAA compliance

**Auto-dismiss (pills):** The pill auto-dismiss is compliant because:

1. The pill conveys supplementary confirmation, not essential information. The UI itself reflects the completed action (page navigated, item appeared in list, etc.). The toast is redundant feedback.
2. Pause-on-hover satisfies WCAG 2.2.1 (Timing Adjustable, Level A) — users can extend the timeout by hovering.
3. A visual progress indicator shows remaining time, providing awareness of the countdown.
4. The reading-speed formula (500ms/word + 1s buffer, 5-15s range) ensures adequate reading time.

**Persistent cards (warnings/errors):** `timeout=0`, manual dismiss only. No timing concerns.

**Screen readers:**

| Type | role | aria-live | Behavior |
|------|------|-----------|----------|
| Success/Info (pill) | `status` | `polite` | Announced at next pause, does not interrupt |
| Warning/Error (card) | `alert` | `assertive` | Announced immediately, interrupts current speech |

Both containers use `aria-atomic="true"` so the full message is announced, not just the changed portion.

**Other AAA requirements:**

- Close button: 44x44px minimum touch target
- `prefers-reduced-motion`: animations skipped entirely (opacity-only or instant)
- Contrast: uses existing signal tokens which meet 7:1 AAA contrast ratios
- Keyboard: close button reachable via Tab; cards are near end of DOM for natural tab order

## Architecture

### Partials

**`app/views/shared/_toast_pill.html.erb`** — Compact pill for success/info.

```
Strict locals: (type:, message:)
```

Structure:

- Dark semi-transparent background (`bg-slate-900/90`), fully rounded (`rounded-full`)
- Icon (checkmark for success, info circle for notice) + message text
- No close button — auto-dismisses
- Progress bar (thin, inside pill, same width animation as current)
- `data-controller="toast-pill"`
- `data-toast-pill-timeout-value="<computed>"`
- `data-action="mouseenter->toast-pill#pause mouseleave->toast-pill#resume"`
- `role="status"` `aria-live="polite"` `aria-atomic="true"`

**`app/views/shared/_toast_card.html.erb`** — Persistent card for warnings/errors.

```
Strict locals: (type:, message:)
```

Structure:

- Signal-colored background/border (existing `warning-surface`/`danger-surface` tokens)
- Icon (triangle for warning, circle-exclamation for error) + message text + close button
- Close button: 44x44px, `aria-label` from I18n
- No progress bar
- `data-controller="toast-card"`
- `data-toast-card-timeout-value="0"`
- `role="alert"` `aria-live="assertive"` `aria-atomic="true"`

### Containers

**`app/views/shared/_toasts.html.erb`** — Renders both containers in the layout.

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

### Stimulus Controllers

**`app/javascript/controllers/toast_pill_controller.js`**

Responsibilities:

- Auto-dismiss with reading-speed formula: `max(5000, word_count * 500 + 1000).clamp(5000, 15000)`
- Pause timer on mouseenter, resume on mouseleave (preserves remaining time)
- Progress bar animation (width 100% to 0% over timeout duration, pauses with timer)
- Animate in: slide down + fade in (300ms ease-out)
- Animate out: fade out (300ms ease-in)
- `prefers-reduced-motion`: skip slide, use instant opacity change
- Remove element from DOM after exit animation

**`app/javascript/controllers/toast_card_controller.js`**

Responsibilities:

- No auto-dismiss (`timeout=0`)
- `dismiss()` action triggered by close button click
- Animate in: slide up + fade in (300ms ease-out)
- Animate out: fade out (300ms ease-in)
- `prefers-reduced-motion`: skip slide, use instant opacity change
- Remove element from DOM after exit animation

### Toastable Concern

**`app/controllers/concerns/toastable.rb`** — Updated to route types to correct containers.

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

## Visual Specifications

### New Semantic Tokens

Add to `_semantic.css` — the pill needs an inverted overlay that flips with dark mode:

```css
:root {
  --color-surface-toast: oklch(20.5% 0.016 265.755 / 90%);  /* neutral-900 @ 90% */
  --color-text-on-toast: oklch(100% 0 0);                     /* white */
}
.dark {
  --color-surface-toast: oklch(96.8% 0.007 264.536 / 90%);   /* neutral-100 @ 90% */
  --color-text-on-toast: var(--neutral-900);
}
```

Register in `application.css` `@theme inline` block:

```css
--color-surface-toast: initial;
--color-text-on-toast: initial;
```

### Pill (Tier 1)

- Background: `bg-surface-toast` (semantic token — dark pill light mode, light pill dark mode)
- Text: `text-text-on-toast` (semantic token — white light mode, dark dark mode)
- Icon color: green checkmark (success) or blue info circle (notice)
- Border radius: `rounded-full` (pill shape)
- Padding: `px-4 py-2`
- Font size: `text-sm`
- Shadow: `shadow-lg`
- Max width: `max-w-sm` (384px), with `max-w-[calc(100vw-2rem)]` on mobile
- Progress bar: 2px height inside pill bottom edge, same color as icon

### Card (Tier 2)

- Background: existing signal tokens (`warning-surface` / `danger-surface`)
- Border: existing signal tokens (`warning-border` / `danger-border`)
- Text: existing signal tokens (`text-warning` / `text-danger`)
- Border radius: `rounded-lg`
- Padding: `p-4`
- Width: `w-96` (384px), with `max-w-[calc(100vw-2rem)]` on mobile
- Shadow: `shadow-lg`
- Close button: 44x44px touch target, `-m-1` for expanded hit area

## I18n Keys

Add to `config/locales/en/toasts.en.yml`:

```yaml
en:
  toasts:
    pill_aria_label: "Notifications"
    card_aria_label: "Alerts"
    close: "Dismiss notification"
```

The existing `toasts.aria_label` key can be removed after migration.

## Hotwire Native Compatibility

The bridge component pattern works identically with two tiers. The `bridge--toast` Stimulus controller detects the flash element, reads its type and message, and sends to the native layer. The native app presents using platform-native toast/snackbar APIs regardless of which tier the web version uses. The `turbo-native:hidden` Tailwind variant hides both pill and card when running inside a native shell.

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `app/views/shared/_toast_pill.html.erb` | Create | Compact pill partial |
| `app/views/shared/_toast_card.html.erb` | Create | Persistent card partial |
| `app/views/shared/_toasts.html.erb` | Rewrite | Two containers (top-center, bottom-center) |
| `app/views/shared/_toast.html.erb` | Delete | Replaced by pill + card partials |
| `app/javascript/controllers/toast_pill_controller.js` | Create | Auto-dismiss pill controller |
| `app/javascript/controllers/toast_card_controller.js` | Create | Persistent card controller |
| `app/javascript/controllers/toast_controller.js` | Delete | Replaced by pill + card controllers |
| `app/assets/tailwind/tokens/_semantic.css` | Modify | Add `surface-toast` and `text-on-toast` tokens |
| `app/assets/stylesheets/application.css` | Modify | Register new tokens in `@theme inline` |
| `app/controllers/concerns/toastable.rb` | Modify | Route types to correct container/partial |
| `config/locales/en/toasts.en.yml` | Modify | Add pill/card aria labels |
| `spec/controllers/concerns/toastable_spec.rb` | Modify | Update for new partials/targets |
| `spec/system/toast_spec.rb` | Create | System specs for both tiers |
| `spec/system/static_pages_spec.rb` | Modify | Update toast-related assertions |

## Testing Strategy

**Unit (Toastable concern):**
- `success_toast` appends to `toast-pills` with `_toast_pill` partial
- `error_toast` appends to `toast-cards` with `_toast_card` partial
- `warning_toast` appends to `toast-cards` with `_toast_card` partial

**Request specs:**
- Success flash renders pill in `#toast-pills` container
- Error flash renders card in `#toast-cards` container
- Pill has `role="status"`, card has `role="alert"`

**System specs:**
- Pill appears on successful action, auto-dismisses (wait for removal)
- Pill pauses on hover
- Card appears for error, persists, dismissable via close button
- Card close button keyboard-accessible (Tab + Enter)
- Unauthenticated flash renders in correct container
- No overlap with user menu dropdown when pill is visible

## Out of Scope

- Notification center / message history (future consideration)
- Undo actions in toasts
- Stacking limit (handle if needed later)
- Form validation errors (remain inline, unchanged)
