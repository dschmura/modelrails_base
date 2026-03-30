# Theming Guide

This application uses a three-layer design token system. Tokens provide accessible defaults and clear override points for customization.

## Quick Start: Retheme the Primary Color

To change the primary color from sky to purple, open `app/assets/tailwind/tokens/_primitives.css` and replace `sky` with `purple` in the primary section:

```css
/* Before */
--primary-700: var(--color-sky-700);

/* After */
--primary-700: var(--color-purple-700);
```

Replace all 11 shades (50-950) and the entire UI updates — buttons, links, focus rings, hover states.

## Architecture

### Layer 1: Primitive Tokens

Three palettes map to Tailwind's built-in color scales:

| Palette | Default Tailwind color | Used for |
| --- | --- | --- |
| `--primary-*` | `sky` | Buttons, links, focus rings |
| `--secondary-*` | `indigo` | Accents, prose links |
| `--neutral-*` | `slate` | Text, surfaces, borders |

Each palette has 11 shades (50-950) that reference Tailwind CSS custom properties directly. For example, `--primary-700` resolves to `var(--color-sky-700)`.

To retheme, swap the Tailwind color family. The semantic layer doesn't change — it references the primitive aliases, not the Tailwind colors.

Primitives are defined in `app/assets/tailwind/tokens/_primitives.css`.

### Layer 2: Semantic Tokens

Role-based aliases that answer "what is this color for?":

| Token | Purpose |
| --- | --- |
| `--color-surface` | Page background |
| `--color-surface-raised` | Cards, modals |
| `--color-surface-sunken` | Recessed areas, table headers |
| `--color-text-heading` | Headings |
| `--color-text-body` | Body text |
| `--color-text-muted` | Secondary/caption text |
| `--color-interactive` | Buttons, links |
| `--color-interactive-hover` | Hover state for interactive elements |
| `--color-border` | Default borders |
| `--color-border-strong` | Input borders, dividers |

Dark mode is handled at this layer — semantic tokens remap under `.dark` automatically. Views never need `dark:` prefixes.

Semantic tokens are defined in `app/assets/tailwind/tokens/_semantic.css`.

### Layer 3: Tailwind Utilities

Semantic tokens are registered in `@theme inline` so they work as standard Tailwind classes:

```html
<div class="bg-surface-raised border border-border rounded-lg p-6">
  <h2 class="text-text-heading">Title</h2>
  <p class="text-text-body">Content</p>
  <button class="bg-interactive hover:bg-interactive-hover text-text-on-interactive">
    Action
  </button>
</div>
```

No `dark:` prefixes needed. The token system handles light/dark automatically.

### How tokens relate to Tailwind CSS

Tailwind's built-in colors still exist and work normally. Classes like `bg-red-500` or `text-blue-700` are unchanged. The token system adds new utilities (`bg-surface`, `text-interactive`, etc.) alongside them via the `@theme inline` block in `application.css`. Views use the semantic token utilities for all themed colors.

## Common Override Scenarios

### Change the primary color

In `_primitives.css`, replace all `--color-sky-*` with another Tailwind color:

```css
--primary-50:  var(--color-purple-50);
--primary-100: var(--color-purple-100);
/* ... through 950 */
```

### Change the neutral tone

Replace all `--color-slate-*` with another neutral family:

```css
--neutral-50:  var(--color-zinc-50);
--neutral-100: var(--color-zinc-100);
/* ... through 950 */
```

Good options: `slate` (cool), `gray` (neutral), `zinc` (slightly warm), `stone` (warm), `neutral` (pure).

### Override a specific semantic token

To customize how a role maps to the palette:

```css
:root {
  --color-surface: var(--neutral-100); /* slightly darker page bg */
}
.dark {
  --color-surface: var(--neutral-950); /* deeper dark bg */
}
```

### Add a new semantic token

1. Define it in `_semantic.css` with light and dark values
2. Register it in the `@theme inline` block in `application.css`
3. Use it in views as a Tailwind utility

## Signal Colors

Danger (red), warning (amber), success (green), and info (sky) are fixed — they do not shift with theming. Their meaning is universal.

Defined in `app/assets/tailwind/tokens/_signals.css`.

## Accessibility

Tailwind's built-in color scales are designed with accessibility in mind. The semantic layer maps text and interactive tokens to shades that maintain WCAG AAA contrast ratios (7:1 for normal text, 4.5:1 for large text).

When rethemeing, stick to Tailwind's standard color families — they are all calibrated for consistent contrast. The existing axe-core test suite validates accessibility on every system spec run.

## Advanced: OKLCH Single-Hue Theming

For applications that need dynamic theming (e.g., a color picker that generates palettes at runtime), the primitives file can be replaced with an OKLCH-based generator that derives all shades from a single hue angle. See the [Evil Martians OKLCH guide](https://evilmartians.com/chronicles/better-dynamic-themes-in-tailwind-with-oklch-color-magic) for this approach. The semantic layer works identically either way.

## File Reference

| File | Purpose |
| --- | --- |
| `app/assets/tailwind/tokens/_primitives.css` | Tailwind color mappings |
| `app/assets/tailwind/tokens/_semantic.css` | Role-based aliases + dark mode |
| `app/assets/tailwind/tokens/_signals.css` | Fixed signal colors |
| `app/assets/tailwind/application.css` | Tailwind config + @theme registration |
