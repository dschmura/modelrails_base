# Toast Configurability Refactor — Design Spec

## Problem

The toast system works but is difficult to customize. Type-to-style mappings are hardcoded case statements in two partials. Timing constants are buried in ERB and JavaScript. Positioning values are hardcoded Tailwind classes. Icons are inline SVGs. A downstream project forking modelrails_base must edit multiple files to change any of these.

## Solution

Consolidate all toast configuration into a single initializer file. Replace case statements with config lookups. Replace inline SVGs with `icon()` helper calls. Move positioning to CSS custom properties. Make the stagger delay configurable via data attribute instead of hardcoded in JS.

## Changes

### 1. Config initializer (`config/initializers/toasts.rb`)

Single source of truth for all toast behavior and appearance:

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
    notice:  { tier: :pill, icon: :check_circle,        icon_color: "text-success-icon", progress: "bg-success-progress" },
    success: { tier: :pill, icon: :check_circle,        icon_color: "text-success-icon", progress: "bg-success-progress" },
    info:    { tier: :pill, icon: :information_circle,   icon_color: "text-info-icon",    progress: "bg-info-progress" },
    alert:   { tier: :card, icon: :exclamation_triangle, icon_color: "text-warning-icon", bg: "bg-warning-surface", border: "border-warning-border", text: "text-warning", close_hover: "hover:bg-warning-hover" },
    error:   { tier: :card, icon: :exclamation_circle,   icon_color: "text-danger-icon",  bg: "bg-danger-surface",  border: "border-danger-border",  text: "text-danger",  close_hover: "hover:bg-danger-hover" }
  }
)
```

**Downstream customization:** Edit this one file. Add a new type by adding a hash entry and an SVG file. Change icons, colors, or timing by changing values.

### 2. Partials refactored to read config

**`_toast_pill.html.erb`** — Replace case statements and inline SVGs:

- Read `type_config = Rails.application.config.toasts[:types][type.to_sym]` for icon name, icon_color, progress color
- Read `timing = Rails.application.config.toasts[:timing]` for timeout formula values
- Replace inline SVGs with `<%= icon(type_config[:icon], size: :sm, class: type_config[:icon_color]) %>`
- Pass stagger_ms as `data-toast-pill-stagger-value` so the JS controller reads it from the DOM

**`_toast_card.html.erb`** — Replace case statements and inline SVGs:

- Read `type_config = Rails.application.config.toasts[:types][type.to_sym]` for all style classes
- Replace inline SVGs with `<%= icon(type_config[:icon], size: :lg, class: type_config[:icon_color]) %>` and `<%= icon(:x_mark, size: :md) %>` for close button

**`_toasts.html.erb`** — Replace hardcoded type lists with config lookups:

- Filter flash types by checking `config.toasts[:types][type.to_sym][:tier] == :pill` instead of `%w[notice success info].include?(type)`
- Use CSS custom properties for positioning: `top-[var(--toast-pill-top)]` instead of `top-20`

### 3. Toastable concern reads config

Replace hardcoded type lists with config lookups:

```ruby
def toast_stream(type, message)
  type_config = Rails.application.config.toasts[:types][type.to_sym]
  target = type_config[:tier] == :pill ? "toast-pills" : "toast-cards"
  partial = type_config[:tier] == :pill ? "shared/toast_pill" : "shared/toast_card"
  turbo_stream.append(target, partial: partial, locals: { type: type, message: message })
end
```

### 4. CSS custom properties for positioning

Add to `_semantic.css` `:root` and `.dark` blocks:

```css
:root {
  --toast-pill-top: 5rem;
  --toast-card-bottom: 1rem;
  --toast-z: 100;
}
```

No `.dark` override needed — positioning doesn't change with theme.

Register in `@theme inline` block in `application.css`.

### 5. Pill controller reads stagger from data attribute

Change the hardcoded `2000` in `staggerDelay()` to read from a Stimulus value:

```javascript
static values = { timeout: { type: Number, default: 5000 }, stagger: { type: Number, default: 2000 } }

staggerDelay() {
  const container = this.element.parentElement
  if (!container) return 0
  const siblings = [...container.querySelectorAll('[data-controller="toast-pill"]')]
  const index = siblings.indexOf(this.element)
  return index * this.staggerValue
}
```

The pill partial passes `data-toast-pill-stagger-value="<%= timing[:stagger_ms] %>"`.

## Files Changed

| File | Action | What changes |
| ---- | ------ | ------------ |
| `config/initializers/toasts.rb` | Create | Central config for types, timing |
| `app/views/shared/_toast_pill.html.erb` | Rewrite | Config lookups, `icon()` helper |
| `app/views/shared/_toast_card.html.erb` | Rewrite | Config lookups, `icon()` helper |
| `app/views/shared/_toasts.html.erb` | Modify | Config-driven type filtering, CSS custom property positioning |
| `app/controllers/concerns/toastable.rb` | Modify | Config-driven routing |
| `app/javascript/controllers/toast_pill_controller.js` | Modify | Add stagger value, read from DOM |
| `app/assets/tailwind/tokens/_semantic.css` | Modify | Add toast positioning tokens |
| `app/assets/tailwind/application.css` | Modify | Register positioning tokens in `@theme inline` |
| `spec/controllers/concerns/toastable_spec.rb` | Modify | Verify config-driven routing |
| `spec/system/toast_spec.rb` | Verify | Existing specs should still pass |
| `spec/system/static_pages_spec.rb` | Verify | Existing specs should still pass |

## Testing Strategy

This is a refactor — behavior should not change. The existing test suite (698 specs) is the primary verification. No new test files needed, but the Toastable spec may need minor updates if assertions reference specific partial names.

After refactor:

- All 698 specs pass
- Toast pill renders with `icon()` helper (visible in rendered HTML)
- Toast card renders with `icon()` helper
- `/about` page still shows all 5 toast types correctly
- Timing, stagger, positioning all work as before

## Out of Scope

- Migrating other inline SVGs (header, theme toggle, workspace switcher) to `icon()` — separate task
- Adding new toast types beyond the current 5
- Runtime config changes (config is set at boot)
