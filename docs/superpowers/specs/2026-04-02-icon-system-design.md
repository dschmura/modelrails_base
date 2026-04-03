# File-Based Icon Helper with Registry — Design Spec

## Problem

SVG icons are hardcoded inline throughout view templates (toasts, header, theme toggle, workspace switcher, etc.). This makes icons difficult to customize — a downstream project forking modelrails_base must edit partials to change icons. There is no consistent API for rendering icons with proper sizing, styling, or accessibility attributes.

## Solution

A helper method `icon(:name)` backed by a file-based registry that loads SVGs from a directory, parses them with Nokogiri, caches the results, and renders `<svg>` tags with proper attributes. Downstream developers customize icons by replacing SVG files in a directory — no partial editing required.

## Design Decisions

### Why a helper + registry instead of ViewComponent?

The project convention is ViewComponents only when reused across unrelated views with complex logic. An icon is a simple rendering helper — it takes a name and options, returns an SVG tag. A helper method with a backing registry class is simpler, has no gem dependency beyond what Rails already includes, and provides the same developer experience: `<%= icon(:check_circle) %>`.

### Why Nokogiri parsing instead of raw file reads?

The helper needs to inject attributes (`class`, `aria-hidden`, `role`, `viewBox`, `fill`, `stroke`) onto the `<svg>` element. Raw file reads would require fragile string manipulation. Nokogiri is already a Rails dependency (via Action View), and the parsing is trivial — extract inner HTML and viewBox, cache the result.

### Why icon-set agnostic?

The registry reads `viewBox` from each SVG file rather than assuming Heroicons conventions. This lets downstream projects swap in Lucide, Phosphor, or custom icons without code changes. The base app ships with Heroicons as the default set.

### Accessibility approach

Icons are transparent to accessibility — they inherit color via `currentColor`, are never focusable, and are either decorative (`aria-hidden="true"`) or labeled (`role="img"` + `aria-label`). Focus, contrast, touch targets, and dark mode are all handled by the parent element and the semantic token system, not the icon helper.

## Architecture

### IconRegistry (`app/lib/icon_registry.rb`)

Singleton class that loads, parses, and caches SVG files.

**Directory structure:**

```
app/assets/icons/
  outline/
    check_circle.svg
    information_circle.svg
    exclamation_triangle.svg
    exclamation_circle.svg
    x_mark.svg
    chevron_down.svg
    bars_3.svg
    sun.svg
    moon.svg
    computer_desktop.svg
    ...
  solid/
    x_mark.svg
    ...
```

**Public API:**

```ruby
IconRegistry.find(:check_circle, style: :outline)
# => { inner_html: "<path .../>", viewbox: "0 0 24 24", style: :outline }

IconRegistry.exists?(:check_circle)
# => true

IconRegistry.available_icons
# => [:bars_3, :check_circle, :chevron_down, ...]
```

**Behavior:**

- Scans `app/assets/icons/{outline,solid}/` for `.svg` files
- Parses each with `Nokogiri::XML` to extract:
  - Inner HTML (all child elements of `<svg>` — `<path>`, `<circle>`, etc.)
  - `viewBox` attribute (no default assumed — read from file)
- Caches parsed results in a hash keyed by `[name, style]`
- **Production** (`Rails.application.config.eager_load`): loads all icons at boot via an initializer
- **Development**: lazy-loads on first access, provides `IconRegistry.reload!` for cache busting
- Style resolution: if no style specified, checks outline first, then solid
- Raises `IconRegistry::NotFound` for unknown icons (caught in development, logs warning in production)

### IconHelper (`app/helpers/icon_helper.rb`)

Helper method included in all views via `ApplicationHelper`.

**API:**

```ruby
icon(name, size: :md, style: :outline, class: nil, aria_label: nil, **attrs)
```

**Parameters:**

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |
| `name` | Symbol | required | Icon name matching SVG filename (e.g., `:check_circle`) |
| `size` | Symbol | `:md` | Size preset: `:xs` (12px), `:sm` (16px), `:md` (20px), `:lg` (24px) |
| `style` | Symbol | `:outline` | `:outline` or `:solid` |
| `class` | String | `nil` | Additional Tailwind classes (merged with size classes) |
| `aria_label` | String | `nil` | If present, icon is meaningful (`role="img"`); if absent, decorative (`aria-hidden="true"`) |
| `**attrs` | Hash | `{}` | Additional HTML attributes (`data-*`, etc.) |

**Size classes:**

| Size | Tailwind classes | Pixels |
| ---- | ---------------- | ------ |
| `:xs` | `w-3 h-3` | 12px |
| `:sm` | `w-4 h-4` | 16px |
| `:md` | `w-5 h-5` | 20px |
| `:lg` | `w-6 h-6` | 24px |

**SVG attributes by style:**

| Style | fill | stroke |
| ----- | ---- | ------ |
| `:outline` | `none` | `currentColor` |
| `:solid` | `currentColor` | (not set) |

**Class merging:** If the `class:` parameter includes explicit `w-*` or `h-*` classes, size preset classes are omitted (custom sizing takes precedence).

**Rendering:** Uses `tag.svg` to build the element:

```ruby
tag.svg(
  **svg_attributes,
  &-> { inner_html.html_safe }
)
```

### Initializer (`config/initializers/icons.rb`)

```ruby
Rails.application.config.after_initialize do
  IconRegistry.eager_load! if Rails.application.config.eager_load
end
```

## Usage Examples

```erb
<%# Decorative icon next to text — hidden from screen readers %>
<%= icon(:check_circle, size: :sm, class: "text-success-icon") %>

<%# Standalone meaningful icon — announced by screen readers %>
<%= icon(:trash, aria_label: "Delete") %>

<%# Custom size via class override %>
<%= icon(:envelope, class: "w-8 h-8 text-info-icon") %>

<%# Solid style %>
<%= icon(:x_mark, style: :solid, size: :sm) %>

<%# With data attributes %>
<%= icon(:sun, data: { theme_toggle_target: "lightIcon" }) %>
```

## Starter Icon Set

Ship with the Heroicons used by the current app. These are the SVGs that will replace existing inline icons:

**Outline:**

| File | Used by |
| ---- | ------- |
| `check_circle.svg` | Toast pill (success/notice) |
| `information_circle.svg` | Toast pill (info) |
| `exclamation_triangle.svg` | Toast card (warning) |
| `exclamation_circle.svg` | Toast card (error) |
| `x_mark.svg` | Toast card close button |
| `bars_3.svg` | Mobile menu hamburger |
| `chevron_down.svg` | Workspace switcher dropdown |
| `sun.svg` | Theme toggle (light) |
| `moon.svg` | Theme toggle (dark) |
| `computer_desktop.svg` | Theme toggle (system) |

**Solid:**

| File | Used by |
| ---- | ------- |
| `x_mark.svg` | (available for solid variant) |

Additional icons can be added by dropping SVG files into the directory. No code changes required.

## Files Changed

| File | Action | Purpose |
| ---- | ------ | ------- |
| `app/lib/icon_registry.rb` | Create | SVG file loading, Nokogiri parsing, caching |
| `app/helpers/icon_helper.rb` | Create | `icon()` helper method |
| `config/initializers/icons.rb` | Create | Eager-load registry in production |
| `app/assets/icons/outline/*.svg` | Create | Starter Heroicon set (outline) |
| `app/assets/icons/solid/*.svg` | Create | Starter Heroicon set (solid) |
| `spec/lib/icon_registry_spec.rb` | Create | Registry unit specs |
| `spec/helpers/icon_helper_spec.rb` | Create | Helper unit specs |

## Testing Strategy

**IconRegistry specs:**

- Loads SVG files from the icons directory
- Extracts inner HTML and viewBox correctly
- Caches results (second call doesn't re-read file)
- `find` with explicit style returns correct variant
- `find` without style prefers outline, falls back to solid
- `exists?` returns true for known icons, false for unknown
- `available_icons` returns sorted symbol array
- Raises `IconRegistry::NotFound` for unknown icon names
- `reload!` clears cache

**IconHelper specs:**

- Renders `<svg>` with correct viewBox and inner paths
- Default size `:md` applies `w-5 h-5` classes
- Each size preset applies correct classes
- Custom `class:` merges with size classes
- Custom `class:` with explicit `w-*`/`h-*` overrides size preset
- Outline style sets `fill="none" stroke="currentColor"`
- Solid style sets `fill="currentColor"`, no stroke
- Default: `aria-hidden="true"` (decorative)
- With `aria_label:`: `role="img"` + `aria-label` (meaningful)
- Additional `**attrs` passed through to SVG element
- Unknown icon name raises in development

## Out of Scope

- Migrating existing inline SVGs to use the helper (separate task after the toast refactor)
- Sprite sheets or symbol references
- Icon search/preview UI
- Animated icons
