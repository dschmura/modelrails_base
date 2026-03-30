# Theming Guide

This application uses a three-layer design token system built on OKLCH color space. Tokens provide accessible defaults and clear override points for customization.

## Quick Start: Retheme in One Line

To change the primary color from sky to purple, add to your CSS after the token imports:

```css
:root {
  --theme-primary-hue: 300;
}
```

The entire UI updates — buttons, links, focus rings, hover states — all from one value.

## Architecture

### Layer 1: Primitive Tokens

Three hue angles generate full 11-shade palettes (50-950) using OKLCH:

| Variable | Default | Controls |
| --- | --- | --- |
| `--theme-primary-hue` | 233 (sky) | Buttons, links, focus rings |
| `--theme-secondary-hue` | 264 (indigo) | Accents, prose links |
| `--theme-neutral-hue` | 233 (cool slate) | Text, surfaces, borders |

Each shade combines a fixed lightness/chroma value with the hue angle. The lightness/chroma arrays are calibrated for WCAG AAA contrast at any hue — changing the hue cannot break accessibility.

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

## Common Override Scenarios

### Change the primary color

```css
:root { --theme-primary-hue: 300; } /* purple */
```

### Change both primary and secondary

```css
:root {
  --theme-primary-hue: 150;  /* teal */
  --theme-secondary-hue: 30; /* orange */
}
```

### Use pure gray neutrals (no tint)

Override the neutral chroma values to remove the hue tint:

```css
:root {
  --neutral-50:  oklch(97.78% 0 0);
  --neutral-100: oklch(93.56% 0 0);
  --neutral-200: oklch(88.11% 0 0);
  --neutral-300: oklch(82.67% 0 0);
  --neutral-400: oklch(74.22% 0 0);
  --neutral-500: oklch(64.78% 0 0);
  --neutral-600: oklch(57.33% 0 0);
  --neutral-700: oklch(46.89% 0 0);
  --neutral-800: oklch(39.44% 0 0);
  --neutral-900: oklch(32.00% 0 0);
  --neutral-950: oklch(23.78% 0 0);
}
```

### Override a specific semantic token

```css
:root {
  --color-surface: oklch(98% 0.01 60); /* warm cream background */
}
.dark {
  --color-surface: oklch(15% 0.01 60); /* dark warm background */
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

The lightness/chroma arrays guarantee WCAG AAA contrast ratios (7:1 normal text, 4.5:1 large text) at every hue angle. OKLCH's perceptual uniformity means:

- Changing the hue cannot silently break contrast
- All 360 degrees of the hue wheel produce accessible palettes
- Signal colors maintain universal meaning regardless of theme

The existing axe-core test suite validates accessibility on every system spec run.

## File Reference

| File | Purpose |
| --- | --- |
| `app/assets/tailwind/tokens/_primitives.css` | OKLCH palette generation |
| `app/assets/tailwind/tokens/_semantic.css` | Role-based aliases + dark mode |
| `app/assets/tailwind/tokens/_signals.css` | Fixed signal colors |
| `app/assets/tailwind/application.css` | Tailwind config + @theme registration |
