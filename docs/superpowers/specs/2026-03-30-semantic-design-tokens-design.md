# Semantic Design Tokens

**Date:** 2026-03-30
**Status:** Approved

## Problem

The codebase has 219 hardcoded sky-color references across 48 files and 192 `dark:` prefixes across 20 view files. Changing the app's color scheme requires touching dozens of files. Dark mode maintenance is manual and error-prone. Downstream developers have no clear override points for customization.

## Goals

1. **Consistency** -- Single source of truth for colors, eliminating drift between views
2. **Theming flexibility** -- Retheme the entire app by changing 1-3 hue values
3. **Dark mode maintenance** -- Eliminate `dark:` prefixes from markup; dark mode handled at the token level
4. **Developer overrides** -- Sensible, accessible defaults with clear customization points for downstream developers

## Non-Goals

- Workspace-specific branding (future layer on top of this system)
- GUI color picker for admins (future; this design accommodates it -- three hue sliders updating CSS custom properties)

## Architecture: Three-Layer Token System

### Layer 1: Primitive Tokens (Tailwind Color Mappings)

Three palettes map to Tailwind's built-in color scales, each with 11 shades (50-950):

| Token prefix            | Default Tailwind color | Role                                              |
| ----------------------- | ---------------------- | ------------------------------------------------- |
| `--primary-{shade}`     | `sky`                  | Interactive elements, CTAs, links, focus rings     |
| `--secondary-{shade}`   | `indigo`               | Accents, highlights, prose links, documentation    |
| `--neutral-{shade}`     | `slate`                | Text, surfaces, borders                            |

Each primitive references a Tailwind CSS custom property directly:

```css
--primary-700: var(--color-sky-700);
--neutral-600: var(--color-slate-600);
```

Signal colors (danger, warning, success, info) are hardcoded and do not shift with theming. Their meaning is universal.

**Override story:** To retheme the app to purple, a downstream developer swaps the Tailwind color family in `_primitives.css`:

```css
--primary-700: var(--color-purple-700);
/* ... same for all 11 shades */
```

Tailwind's color scales are designed for consistent contrast, so swapping families maintains accessibility. For advanced single-hue OKLCH theming (e.g., runtime color pickers), the primitives file can be replaced with an OKLCH generator -- see docs/theming.md.

### Layer 2: Semantic Tokens (Role-Based Aliases)

Semantic tokens answer "what is this color for?" Views reference these, never shade numbers.

Dark mode is handled here: the semantic layer remaps values under `.dark`, so markup never needs `dark:` prefixes for token-backed colors.

#### Surface tokens

| Semantic token           | Light value    | Dark value     |
| ------------------------ | -------------- | -------------- |
| `--color-surface`        | `neutral-50`   | `neutral-900`  |
| `--color-surface-raised` | `white`        | `neutral-800`  |
| `--color-surface-overlay` | `white`       | `neutral-800`  |
| `--color-surface-sunken` | `neutral-100`  | `neutral-950`  |

`surface-overlay` shares values with `surface-raised` intentionally -- it exists as a distinct semantic role for modals and dropdowns, allowing independent customization later.

#### Text tokens

| Semantic token              | Light value    | Dark value     |
| --------------------------- | -------------- | -------------- |
| `--color-text-heading`      | `neutral-900`  | `neutral-100`  |
| `--color-text-body`         | `neutral-700`  | `neutral-300`  |
| `--color-text-muted`        | `neutral-500`  | `neutral-400`  |
| `--color-text-on-interactive` | `white`      | `white`        |

#### Interactive tokens

| Semantic token              | Light value      | Dark value       |
| --------------------------- | ---------------- | ---------------- |
| `--color-interactive`       | `primary-700`    | `primary-400`    |
| `--color-interactive-hover` | `primary-800`    | `primary-300`    |
| `--color-interactive-focus` | `primary-700`    | `primary-400`    |
| `--color-interactive-subtle` | `primary-50`    | `primary-950`    |
| `--color-accent`            | `secondary-600`  | `secondary-400`  |
| `--color-accent-hover`      | `secondary-700`  | `secondary-300`  |

#### Border tokens

| Semantic token         | Light value    | Dark value     |
| ---------------------- | -------------- | -------------- |
| `--color-border`       | `neutral-200`  | `neutral-700`  |
| `--color-border-strong` | `neutral-300` | `neutral-600`  |
| `--color-border-focus` | `primary-700`  | `primary-400`  |

#### Signal tokens (fixed, not theme-dependent)

Each signal has a base color plus surface, icon, hover, progress, and border variants to support toast notifications and status indicators:

| Semantic token    | Light value  | Dark value  |
| ----------------- | ------------ | ----------- |
| `--color-danger`  | `red-700`    | `red-400`   |
| `--color-warning` | `amber-600`  | `amber-400` |
| `--color-success` | `green-700`  | `green-400` |
| `--color-info`    | `sky-600`    | `sky-400`   |

Variant pattern (example for danger): `--color-danger-surface` (bg), `--color-danger-icon`, `--color-danger-hover`, `--color-danger-progress`, `--color-danger-border`. Same pattern applies to warning, success, and info.

### Layer 3: Tailwind Utility Integration

Semantic tokens are registered via `@theme` in `application.css`:

```css
@theme {
  /* Surfaces */
  --color-surface: var(--color-surface);
  --color-surface-raised: var(--color-surface-raised);
  --color-surface-overlay: var(--color-surface-overlay);
  --color-surface-sunken: var(--color-surface-sunken);

  /* Text */
  --color-text-heading: var(--color-text-heading);
  --color-text-body: var(--color-text-body);
  --color-text-muted: var(--color-text-muted);
  --color-text-on-interactive: var(--color-text-on-interactive);

  /* Interactive */
  --color-interactive: var(--color-interactive);
  --color-interactive-hover: var(--color-interactive-hover);
  --color-interactive-focus: var(--color-interactive-focus);
  --color-accent: var(--color-accent);
  --color-accent-hover: var(--color-accent-hover);

  /* Borders */
  --color-border: var(--color-border);
  --color-border-strong: var(--color-border-strong);
  --color-border-focus: var(--color-border-focus);

  /* Signals */
  --color-danger: var(--color-danger);
  --color-warning: var(--color-warning);
  --color-success: var(--color-success);
  --color-info: var(--color-info);
}
```

This enables standard Tailwind utilities backed by tokens:

- `bg-surface`, `bg-surface-raised`, `bg-surface-sunken`
- `text-heading`, `text-body`, `text-muted`, `text-on-interactive`
- `text-interactive`, `hover:text-interactive-hover`
- `border-border`, `border-border-strong`, `border-border-focus`
- `text-danger`, `text-warning`, `text-success`, `text-info`

## Migration Strategy

Incremental, not big-bang. Ordered by impact:

### Phase 1: Define the token system

- Add primitive token generation (OKLCH lightness/chroma arrays + hue custom properties) to `application.css`
- Add semantic token mappings (light + dark) to `application.css`
- Register semantic tokens in `@theme` for Tailwind utility generation

### Phase 2: Migrate shared partials

These account for the majority of color usage:

- `_header.html.erb` (22 sky refs, 18 dark: refs)
- `_navigation.html.erb` (11 dark: refs)
- `_footer.html.erb` (10 dark: refs)
- `_hero.html.erb` (5 sky refs, 4 dark: refs)
- `_toast.html.erb` (9 sky refs, 28 dark: refs)
- `_theme_toggle.html.erb`
- `_site_logo.html.erb`
- `_oauth_buttons.html.erb`
- `_workspace_switcher.html.erb`

### Phase 3: Migrate page views

All remaining `.html.erb` files swap hardcoded color classes for semantic token classes.

### Phase 4: Migrate prose and syntax highlighting

- `.prose` styles switch from hardcoded slate/indigo to semantic tokens
- `.highlight` base/background styles switch to surface tokens
- Syntax highlighting colors (keywords, strings, comments, etc.) remain hardcoded -- they are optimized for code readability, not brand theming
- The entire `.dark .prose` section (~60 lines) is deleted
- The entire `.dark .highlight` section (~35 lines) is deleted (dark variants handled by semantic surface tokens + hardcoded syntax dark palette)
- Markdowndocs dark mode overrides (~70 lines) are deleted or simplified

### Phase 5: Migrate third-party overrides

- Biscuit cookie banner tokens remap to semantic tokens
- Any remaining hardcoded hex/rgb values replaced

## What Gets Deleted

After full migration:

- ~60 lines of `.dark .prose` CSS overrides
- ~35 lines of `.dark .highlight` CSS overrides
- ~70 lines of markdowndocs dark mode CSS overrides
- 192 `dark:` prefixes across view files (replaced by token-backed utilities that handle dark mode automatically)

## Accessibility Guarantees

- Lightness/chroma arrays are calibrated so WCAG AAA contrast ratios (7:1 for normal text, 4.5:1 for large text) hold at every hue angle
- OKLCH's perceptual uniformity means hue changes cannot silently break contrast
- Signal colors remain fixed to preserve universal color meaning (red = danger, green = success)
- All existing axe-core accessibility tests continue to enforce compliance

## Future Compatibility

**Workspace branding:** The primitive layer's hue-based architecture means a workspace color picker can set `--theme-primary-hue` to any value and the entire palette regenerates. This is a future layer on top, not part of this design.

**Admin GUI color picker:** Three range sliders (0-360) updating CSS custom properties via Stimulus. Live preview requires zero page reloads. Persistence is a database write of three integer values injected into the layout.

## Developer Documentation

A `docs/theming.md` guide will be created covering:

- What tokens exist and what they're for
- How to retheme the app (change hue values)
- How to swap to pure (untinted) neutrals
- How to override individual semantic tokens
- How to add new tokens
- Accessibility guarantees and what the lightness/chroma arrays ensure
- Migration guide for converting hardcoded classes to token utilities
