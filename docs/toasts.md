# Toast Notification System

A two-tier notification system for communicating feedback to users. Compact pills for confirmations, persistent cards for warnings and errors.

## Quick Start

### Flash messages (most common)

In any controller, use standard Rails flash keys:

```ruby
redirect_to @workspace, notice: t(".success")
```

Rails `notice:` and `success:` flash types render as **pills** (top-center, auto-dismiss). `alert:` and `error:` render as **cards** (bottom-center, persistent).

### Turbo Stream helpers

For Turbo Stream responses, use the `Toastable` concern helpers:

```ruby
render turbo_stream: success_toast("Workspace created.")
render turbo_stream: error_toast("Payment failed. Please update your billing details.")
```

Compose with other Turbo Streams:

```ruby
render turbo_stream: [
  turbo_stream.prepend("projects", partial: "project", locals: { project: @project }),
  success_toast("Project created.")
]
```

### Available helpers

| Helper | Flash type | Tier | Behavior |
| --- | --- | --- | --- |
| `success_toast(msg)` | `success` | Pill | Auto-dismiss, green checkmark |
| `notice_toast(msg)` | `notice` | Pill | Auto-dismiss, green checkmark |
| `info_toast(msg)` | `info` | Pill | Auto-dismiss, blue info icon |
| `warning_toast(msg)` | `alert` | Card | Persistent, yellow warning icon |
| `error_toast(msg)` | `error` | Card | Persistent, red error icon |

## Two-Tier Design

### Tier 1: Pills (success, notice, info)

Compact dark pill that appears top-center below the header. Auto-dismisses after a reading-speed timeout. No close button needed.

**When to use:** Confirming a completed action. The UI itself already reflects the change (page navigated, item added to list, settings saved). The pill is supplementary feedback.

**Behavior:**

- Appears with a slide-down animation
- Progress bar shows remaining time
- Pauses timer on hover (user can keep reading)
- Multiple pills stagger their timeouts so the user can read each one
- Fades out when timer expires, then removed from DOM

**Notice vs success vs info:**

- `notice` and `success` look identical (green checkmark) — use either for confirming actions. Rails convention is `notice:` for redirect flash messages.
- `info` uses a blue info icon — use for informational messages that are not confirming a user action (e.g., "Your session will expire in 5 minutes").

### Tier 2: Cards (alert, error)

Persistent card that appears bottom-center. Requires manual dismissal via close button.

**When to use:** Something needs the user's attention. The message contains information they need to read and potentially act on.

**Behavior:**

- Appears with a slide-up animation
- Persists until the user clicks the close button
- Close button is keyboard-accessible (Tab to reach, Enter to dismiss)
- Multiple cards stack upward

**Alert vs error:**

- `alert` uses a yellow warning triangle — use for non-critical issues (approaching limits, deprecation notices, soft warnings)
- `error` uses a red error icon — use for failures that need attention (payment failed, permission denied, validation errors that can't be shown inline)

> **Note:** Form validation errors should be displayed inline next to the offending field, not as toast cards. Toasts are for page-level feedback, not field-level errors.

## Customization

All toast configuration lives in `config/initializers/toasts.rb`. Edit this one file to change types, icons, timing, or colors.

### Adding a new toast type

1. Add an entry to the config hash:

```ruby
# config/initializers/toasts.rb
Rails.application.config.toasts[:types][:custom] = {
  tier: :pill,                          # :pill (auto-dismiss) or :card (persistent)
  icon: :star,                          # icon name matching SVG in app/assets/icons/
  icon_color: "text-info-icon",         # Tailwind class for icon color
  progress: "bg-info-progress"          # Tailwind class for progress bar (pills only)
}
```

2. Add the SVG icon file:

```
app/assets/icons/outline/star.svg
```

3. Use it in a controller:

```ruby
flash[:custom] = "You earned a star!"
# or via Turbo Stream:
render turbo_stream: toast_stream("custom", "You earned a star!")
```

No partial editing required. The container and partials read from config automatically.

### Changing icons

The `icon:` key in each type config maps to an SVG file in `app/assets/icons/outline/` (or `solid/`). To change the success icon from a checkmark to a thumbs-up:

1. Add `app/assets/icons/outline/hand_thumb_up.svg` (drop in any Heroicon or custom SVG)
2. Update the config:

```ruby
success: { tier: :pill, icon: :hand_thumb_up, icon_color: "text-success-icon", progress: "bg-success-progress" }
```

### Changing colors

Toast colors use the signal token system. Edit `app/assets/tailwind/tokens/_signals.css`:

```css
/* Change warning text from amber-800 to orange-700 */
--color-warning: oklch(55.4% 0.163 48.998);   /* change this value */
```

The pill background uses its own tokens in `app/assets/tailwind/tokens/_semantic.css`:

```css
--color-surface-toast: oklch(20.5% 0.016 265.755 / 90%);  /* pill background */
--color-text-on-toast: oklch(100% 0 0);                     /* pill text */
```

Both flip automatically in dark mode — no `dark:` prefixes needed.

See `docs/theming.md` for full details on the token system.

### Changing timing

Edit the `timing` section in `config/initializers/toasts.rb`:

```ruby
timing: {
  ms_per_word: 500,    # milliseconds per word in the message
  buffer_ms: 1000,     # base buffer added to every timeout
  min_ms: 5000,        # minimum timeout (5 seconds)
  max_ms: 15000,       # maximum timeout (15 seconds)
  stagger_ms: 2000     # extra time per additional pill when multiple show at once
}
```

**How the formula works:** `timeout = max(min_ms, word_count * ms_per_word + buffer_ms)`, clamped to `max_ms`. A 3-word message ("Settings saved successfully") gets `max(5000, 3 * 500 + 1000) = 5000ms`. A 20-word message gets `clamp(5000, 20 * 500 + 1000, 15000) = 11000ms`.

**Stagger:** When multiple pills appear at once, each subsequent pill gets an additional `stagger_ms` before it dismisses. The first pill dismisses at its normal timeout, the second at timeout + 2000ms, the third at timeout + 4000ms, etc.

### Changing positioning

Toast containers are positioned using CSS custom properties in `app/assets/tailwind/tokens/_semantic.css`:

```css
--toast-pill-top: 5rem;      /* distance from top of viewport (default: below 64px header) */
--toast-card-bottom: 1rem;   /* distance from bottom of viewport */
--toast-z: 100;              /* z-index for both containers */
```

If your project has a taller header, change `--toast-pill-top` to match.

## Accessibility

The toast system targets WCAG 2.2 Level AAA compliance.

### Screen readers

| Type | ARIA role | aria-live | Behavior |
| --- | --- | --- | --- |
| Success, notice, info | `status` | `polite` | Announced at next pause, does not interrupt |
| Alert, error | `alert` | `assertive` | Announced immediately, interrupts current speech |

Both containers use `aria-atomic="true"` so the full message is read, not just the changed portion.

### Keyboard navigation

- **Pills:** No keyboard interaction needed. They auto-dismiss and don't contain interactive elements.
- **Cards:** The close button is a native `<button>` element in the natural tab order. Press Tab to reach it, Enter or Space to dismiss.
- Toast containers use `pointer-events-none` with `pointer-events-auto` on individual toasts, so they don't block keyboard navigation to elements beneath them.

### Timing and motion

- **Pause on hover:** Hovering over a pill pauses the auto-dismiss timer. The progress bar freezes. Moving the mouse away resumes from where it left off.
- **Reduced motion:** When `prefers-reduced-motion: reduce` is set, all slide animations are skipped. Toasts appear and disappear instantly with no transitions.
- **Auto-dismiss rationale:** Pills are supplementary confirmation — the UI already reflects the completed action. The auto-dismiss does not gate access to essential information. Cards (warnings/errors) never auto-dismiss.

### Touch targets

The card close button meets the WCAG AAA minimum of 44x44 pixels (`min-h-[44px] min-w-[44px]`).

### Color contrast

All toast text meets the AAA 7:1 contrast ratio:

| Toast | Text | Background | Approximate ratio |
| --- | --- | --- | --- |
| Pill (light mode) | White | Neutral-900 @ 90% | ~15:1 |
| Pill (dark mode) | Neutral-900 | Neutral-100 @ 90% | ~15:1 |
| Warning card | Amber-800 | Amber-50 | ~8.5:1 |
| Error card | Red-700 | Red-50 | ~9.2:1 |

## Architecture

### File overview

| File | Purpose |
| --- | --- |
| `config/initializers/toasts.rb` | Central config: types, icons, timing |
| `app/views/shared/_toasts.html.erb` | Container partial (renders both tiers) |
| `app/views/shared/_toast_pill.html.erb` | Pill partial (success/notice/info) |
| `app/views/shared/_toast_card.html.erb` | Card partial (alert/error) |
| `app/javascript/controllers/toast_pill_controller.js` | Auto-dismiss, pause, progress bar |
| `app/javascript/controllers/toast_card_controller.js` | Persistent dismiss, animation |
| `app/controllers/concerns/toastable.rb` | Turbo Stream helpers |
| `app/assets/tailwind/tokens/_signals.css` | Card colors (warning/danger tokens) |
| `app/assets/tailwind/tokens/_semantic.css` | Pill colors and positioning tokens |

### How it works

1. Controller sets a flash message or calls a Toastable helper
2. The layout renders `shared/toasts`, which contains two containers: `#toast-pills` (top-center) and `#toast-cards` (bottom-center)
3. For each flash, the container checks `config.toasts[:types]` to determine the tier
4. The appropriate partial renders with config-driven icon, colors, and timing
5. Stimulus controllers handle animation, auto-dismiss (pills), and manual dismiss (cards)
6. Turbo Stream toasts append directly to the correct container via the Toastable concern

### Hotwire Native compatibility

For native mobile apps using Hotwire Native, the established bridge component pattern applies. A `bridge--toast` Stimulus controller detects the flash element, sends the message to the native layer, and the native app shows a platform-native toast. The web element hides itself via a `turbo-native:hidden` Tailwind variant.
