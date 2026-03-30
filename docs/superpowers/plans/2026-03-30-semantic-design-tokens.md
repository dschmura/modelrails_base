# Semantic Design Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 650+ hardcoded color classes and 350+ dark: prefixes across 46 files with a three-layer OKLCH design token system, eliminating dark mode duplication and enabling single-value theming.

**Architecture:** Primitive OKLCH tokens generate 11-shade palettes from three hue angles. Semantic tokens map role-based names to primitives with automatic dark mode remapping. Tailwind 4 `@theme inline` registers semantic tokens as utility classes. Views migrate incrementally from hardcoded classes to token utilities.

**Tech Stack:** TailwindCSS 4, OKLCH color space, CSS custom properties, `@theme inline` directive

**Spec:** `docs/superpowers/specs/2026-03-30-semantic-design-tokens-design.md`

---

## File Structure

### Created

- `app/assets/tailwind/tokens/_primitives.css` -- OKLCH palette generation from hue angles
- `app/assets/tailwind/tokens/_semantic.css` -- Role-based aliases with dark mode remapping
- `app/assets/tailwind/tokens/_signals.css` -- Fixed signal colors (danger/warning/success/info)
- `docs/theming.md` -- Developer guide for downstream customization

### Modified

- `app/assets/tailwind/application.css` -- Import token files, register in `@theme inline`
- `app/views/layouts/application.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_header.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_footer.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_navigation.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_hero.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_toast.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_theme_toggle.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_site_logo.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_oauth_buttons.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_workspace_switcher.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_feature_card.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/shared/_activity_feed.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/sessions/new.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/sessions/password_form.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/sessions/check_email.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/registrations/new.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/passwords/new.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/passwords/edit.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/magic_link_registrations/show.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/account/profiles/edit.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/account/passwords/new.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/pages/home.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/pages/about.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/pages/privacy.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/pages/contact.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/invitation_accepts/show.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/invitation_declines/show.html.erb` -- Replace hardcoded colors with token utilities
- `app/views/workspaces/*.html.erb` -- Replace hardcoded colors with token utilities (all workspace views)
- `app/views/workspaces/**/*.html.erb` -- Replace hardcoded colors with token utilities (all nested workspace views)
- `app/views/layouts/markdowndocs/application.html.erb` -- Replace hardcoded colors with token utilities

---

## Token-to-Class Reference

This mapping is used throughout the migration tasks. Every view migration follows these substitutions:

### Surface classes

| Old classes | New class |
| --- | --- |
| `bg-white dark:bg-gray-900` | `bg-surface-raised` |
| `bg-gray-50 dark:bg-gray-800` | `bg-surface` |
| `bg-gray-100 dark:bg-gray-900` | `bg-surface-sunken` |

### Text classes

| Old classes | New class |
| --- | --- |
| `text-slate-900 dark:text-gray-100` | `text-text-heading` |
| `text-slate-800 dark:text-gray-200` | `text-text-heading` |
| `text-slate-700 dark:text-gray-300` | `text-text-body` |
| `text-slate-600 dark:text-gray-400` | `text-text-muted` |
| `text-slate-500 dark:text-gray-400` | `text-text-muted` |

### Interactive classes

| Old classes | New class |
| --- | --- |
| `bg-sky-700 hover:bg-sky-800` | `bg-interactive hover:bg-interactive-hover` |
| `text-sky-700 dark:text-sky-400` | `text-interactive` |
| `hover:text-sky-700 dark:hover:text-sky-400` | `hover:text-interactive-hover` |
| `focus:ring-sky-700` | `focus:ring-interactive-focus` |
| `focus:border-sky-700` | `focus:border-interactive-focus` |

### Border classes

| Old classes | New class |
| --- | --- |
| `border-gray-200 dark:border-gray-700` | `border-border` |
| `border-gray-300 dark:border-gray-600` | `border-border-strong` |

### Accent classes

| Old classes | New class |
| --- | --- |
| `text-indigo-600 dark:text-indigo-400` | `text-accent` |
| `hover:text-indigo-700 dark:hover:text-indigo-300` | `hover:text-accent-hover` |

### Signal classes

| Old classes | New class |
| --- | --- |
| `bg-red-50 dark:bg-red-900` | `bg-danger-surface` |
| `border-red-300 dark:border-red-700` | `border-danger` |
| `text-red-700 dark:text-red-300` / `text-red-900 dark:text-red-100` | `text-danger` |
| `bg-green-50 dark:bg-green-900` | `bg-success-surface` |
| `border-green-300 dark:border-green-700` | `border-success` |
| `text-green-700 dark:text-green-300` / `text-green-900 dark:text-green-100` | `text-success` |
| `bg-amber-50 dark:bg-amber-900` | `bg-warning-surface` |
| `border-amber-300 dark:border-amber-700` | `border-warning` |
| `text-amber-900 dark:text-amber-100` | `text-warning` |
| `bg-sky-50 dark:bg-sky-950` | `bg-info-surface` |
| `border-sky-300 dark:border-sky-700` | `border-info` |
| `text-sky-900 dark:text-sky-100` | `text-info` |

### Signal icon/progress classes

| Old classes | New class |
| --- | --- |
| `text-sky-500 dark:text-sky-400` | `text-info-icon` |
| `text-green-500 dark:text-green-400` | `text-success-icon` |
| `text-amber-500 dark:text-amber-400` | `text-warning-icon` |
| `text-red-500 dark:text-red-400` | `text-danger-icon` |
| `bg-sky-400 dark:bg-sky-500` | `bg-info-progress` |
| `bg-green-400 dark:bg-green-500` | `bg-success-progress` |
| `hover:bg-sky-100 dark:hover:bg-sky-900` | `hover:bg-info-hover` |
| `hover:bg-green-100 dark:hover:bg-green-900` | `hover:bg-success-hover` |
| `hover:bg-amber-100 dark:hover:bg-amber-900` | `hover:bg-warning-hover` |
| `hover:bg-red-100 dark:hover:bg-red-900` | `hover:bg-danger-hover` |

### Outline button classes

| Old classes | New class |
| --- | --- |
| `border border-sky-700 text-sky-700 dark:text-sky-400 hover:bg-sky-50 dark:hover:bg-sky-900` | `border border-interactive text-interactive hover:bg-interactive-subtle` |

### Input classes

| Old classes | New class |
| --- | --- |
| `bg-white dark:bg-gray-800 border-gray-300 dark:border-gray-600` | `bg-surface-raised border-border-strong` |
| `text-slate-900 dark:text-gray-100` (inside inputs) | `text-text-heading` |
| `hover:bg-gray-50 dark:hover:bg-gray-700` | `hover:bg-surface` |
| `hover:bg-gray-100 dark:hover:bg-gray-700` / `hover:bg-gray-100 dark:hover:bg-gray-800` | `hover:bg-surface-sunken` |

---

### Task 1: Create Primitive Token Definitions

**Files:**
- Create: `app/assets/tailwind/tokens/_primitives.css`

- [ ] **Step 1: Create the tokens directory**

Run: `mkdir -p app/assets/tailwind/tokens`

- [ ] **Step 2: Write the primitive token file**

Create `app/assets/tailwind/tokens/_primitives.css`:

```css
/* ==========================================================================
   Primitive Design Tokens — OKLCH Palette Generation
   ==========================================================================
   Three hue angles generate full 11-shade palettes (50-950).
   Lightness/chroma arrays are calibrated for WCAG AAA contrast at any hue.

   To retheme: change the hue values below. To use pure gray neutrals,
   set all --neutral-*-c values to 0.

   Reference: https://evilmartians.com/chronicles/better-dynamic-themes-in-tailwind-with-oklch-color-magic
   ========================================================================== */

:root {
  /* --- Hue Controls (change these to retheme) --- */
  --theme-primary-hue: 233;
  --theme-secondary-hue: 264;
  --theme-neutral-hue: 233;

  /* --- Primary Palette (default: sky) --- */
  --primary-50:  oklch(97.78% 0.0108 var(--theme-primary-hue));
  --primary-100: oklch(93.56% 0.0321 var(--theme-primary-hue));
  --primary-200: oklch(88.11% 0.0609 var(--theme-primary-hue));
  --primary-300: oklch(82.67% 0.0908 var(--theme-primary-hue));
  --primary-400: oklch(74.22% 0.1398 var(--theme-primary-hue));
  --primary-500: oklch(64.78% 0.1472 var(--theme-primary-hue));
  --primary-600: oklch(57.33% 0.1299 var(--theme-primary-hue));
  --primary-700: oklch(46.89% 0.1067 var(--theme-primary-hue));
  --primary-800: oklch(39.44% 0.0898 var(--theme-primary-hue));
  --primary-900: oklch(32.00% 0.0726 var(--theme-primary-hue));
  --primary-950: oklch(23.78% 0.054  var(--theme-primary-hue));

  /* --- Secondary Palette (default: indigo) --- */
  --secondary-50:  oklch(97.78% 0.0108 var(--theme-secondary-hue));
  --secondary-100: oklch(93.56% 0.0321 var(--theme-secondary-hue));
  --secondary-200: oklch(88.11% 0.0609 var(--theme-secondary-hue));
  --secondary-300: oklch(82.67% 0.0908 var(--theme-secondary-hue));
  --secondary-400: oklch(74.22% 0.1398 var(--theme-secondary-hue));
  --secondary-500: oklch(64.78% 0.1472 var(--theme-secondary-hue));
  --secondary-600: oklch(57.33% 0.1299 var(--theme-secondary-hue));
  --secondary-700: oklch(46.89% 0.1067 var(--theme-secondary-hue));
  --secondary-800: oklch(39.44% 0.0898 var(--theme-secondary-hue));
  --secondary-900: oklch(32.00% 0.0726 var(--theme-secondary-hue));
  --secondary-950: oklch(23.78% 0.054  var(--theme-secondary-hue));

  /* --- Neutral Palette (default: cool-tinted slate) --- */
  --neutral-50:  oklch(97.78% 0.0108 var(--theme-neutral-hue));
  --neutral-100: oklch(93.56% 0.0321 var(--theme-neutral-hue));
  --neutral-200: oklch(88.11% 0.0609 var(--theme-neutral-hue));
  --neutral-300: oklch(82.67% 0.0908 var(--theme-neutral-hue));
  --neutral-400: oklch(74.22% 0.1398 var(--theme-neutral-hue));
  --neutral-500: oklch(64.78% 0.1472 var(--theme-neutral-hue));
  --neutral-600: oklch(57.33% 0.1299 var(--theme-neutral-hue));
  --neutral-700: oklch(46.89% 0.1067 var(--theme-neutral-hue));
  --neutral-800: oklch(39.44% 0.0898 var(--theme-neutral-hue));
  --neutral-900: oklch(32.00% 0.0726 var(--theme-neutral-hue));
  --neutral-950: oklch(23.78% 0.054  var(--theme-neutral-hue));
}
```

- [ ] **Step 3: Commit**

```bash
git add app/assets/tailwind/tokens/_primitives.css
git commit -m "feat(tokens): Add primitive OKLCH palette generation from three hue angles"
```

---

### Task 2: Create Semantic Token Definitions

**Files:**
- Create: `app/assets/tailwind/tokens/_semantic.css`

- [ ] **Step 1: Write the semantic token file**

Create `app/assets/tailwind/tokens/_semantic.css`:

```css
/* ==========================================================================
   Semantic Design Tokens — Role-Based Color Aliases
   ==========================================================================
   These tokens define what colors are FOR, not what they ARE.
   Dark mode is handled here: .dark remaps semantic tokens to dark primitives.
   Views never need dark: prefixes for token-backed colors.
   ========================================================================== */

:root {
  /* --- Surfaces --- */
  --color-surface:         var(--neutral-50);
  --color-surface-raised:  oklch(100% 0 0);  /* white */
  --color-surface-overlay: oklch(100% 0 0);  /* white — distinct role for modals/dropdowns */
  --color-surface-sunken:  var(--neutral-100);

  /* --- Text --- */
  --color-text-heading:        var(--neutral-900);
  --color-text-body:           var(--neutral-700);
  --color-text-muted:          var(--neutral-500);
  --color-text-on-interactive: oklch(100% 0 0);  /* white */

  /* --- Interactive (buttons, links, focus rings) --- */
  --color-interactive:       var(--primary-700);
  --color-interactive-hover: var(--primary-800);
  --color-interactive-focus: var(--primary-700);
  --color-interactive-subtle: var(--primary-50);

  /* --- Accent (secondary highlights, prose links) --- */
  --color-accent:       var(--secondary-600);
  --color-accent-hover: var(--secondary-700);

  /* --- Borders --- */
  --color-border:        var(--neutral-200);
  --color-border-strong: var(--neutral-300);
  --color-border-focus:  var(--primary-700);
}

.dark {
  /* --- Surfaces --- */
  --color-surface:         var(--neutral-900);
  --color-surface-raised:  var(--neutral-800);
  --color-surface-overlay: var(--neutral-800);
  --color-surface-sunken:  var(--neutral-950);

  /* --- Text --- */
  --color-text-heading:        var(--neutral-100);
  --color-text-body:           var(--neutral-300);
  --color-text-muted:          var(--neutral-400);
  --color-text-on-interactive: oklch(100% 0 0);  /* stays white */

  /* --- Interactive --- */
  --color-interactive:       var(--primary-400);
  --color-interactive-hover: var(--primary-300);
  --color-interactive-focus: var(--primary-400);
  --color-interactive-subtle: var(--primary-950);

  /* --- Accent --- */
  --color-accent:       var(--secondary-400);
  --color-accent-hover: var(--secondary-300);

  /* --- Borders --- */
  --color-border:        var(--neutral-700);
  --color-border-strong: var(--neutral-600);
  --color-border-focus:  var(--primary-400);
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/tailwind/tokens/_semantic.css
git commit -m "feat(tokens): Add semantic token layer with dark mode remapping"
```

---

### Task 3: Create Signal Token Definitions

**Files:**
- Create: `app/assets/tailwind/tokens/_signals.css`

- [ ] **Step 1: Write the signal token file**

Create `app/assets/tailwind/tokens/_signals.css`:

```css
/* ==========================================================================
   Signal Tokens — Fixed Colors for Semantic Meaning
   ==========================================================================
   These do NOT shift with theming. Red = danger, green = success, etc.
   Uses Tailwind 4's built-in OKLCH color values for consistency.
   ========================================================================== */

:root {
  /* --- Danger (red) --- */
  --color-danger:          oklch(50.5% 0.213 27.518);   /* ~red-700 */
  --color-danger-surface:  oklch(97.1% 0.013 17.38);    /* ~red-50 */
  --color-danger-icon:     oklch(63.7% 0.237 25.331);   /* ~red-500 */
  --color-danger-hover:    oklch(93.6% 0.032 17.717);   /* ~red-100 */
  --color-danger-progress: oklch(70.4% 0.191 22.216);   /* ~red-400 */
  --color-danger-border:   oklch(80.8% 0.114 19.571);   /* ~red-300 */

  /* --- Warning (amber) --- */
  --color-warning:          oklch(66.6% 0.179 58.318);   /* ~amber-600 */
  --color-warning-surface:  oklch(98.1% 0.029 95.724);   /* ~amber-50 */
  --color-warning-icon:     oklch(76.6% 0.163 70.08);    /* ~amber-500 */
  --color-warning-hover:    oklch(95.4% 0.064 86.375);   /* ~amber-100 */
  --color-warning-border:   oklch(87.9% 0.125 85.859);   /* ~amber-300 */

  /* --- Success (green) --- */
  --color-success:          oklch(52.7% 0.154 150.069);  /* ~green-700 */
  --color-success-surface:  oklch(98.2% 0.018 155.826);  /* ~green-50 */
  --color-success-icon:     oklch(72.3% 0.219 149.579);  /* ~green-500 */
  --color-success-hover:    oklch(96.2% 0.044 156.743);  /* ~green-100 */
  --color-success-progress: oklch(79.2% 0.209 151.711);  /* ~green-400 */
  --color-success-border:   oklch(87.1% 0.15 154.449);   /* ~green-300 */

  /* --- Info (sky) --- */
  --color-info:          oklch(58.8% 0.158 231.966);  /* ~sky-600 */
  --color-info-surface:  oklch(97.7% 0.013 236.62);   /* ~sky-50 */
  --color-info-icon:     oklch(71.4% 0.168 237.674);  /* ~sky-500 */
  --color-info-hover:    oklch(95.1% 0.026 236.824);  /* ~sky-100 */
  --color-info-progress: oklch(79.6% 0.15 235.169);   /* ~sky-400 */
  --color-info-border:   oklch(86.2% 0.084 237.323);  /* ~sky-300 */
}

.dark {
  /* --- Danger (red) --- */
  --color-danger:          oklch(70.4% 0.191 22.216);   /* ~red-400 */
  --color-danger-surface:  oklch(25.8% 0.092 26.042);   /* ~red-950 */
  --color-danger-icon:     oklch(70.4% 0.191 22.216);   /* ~red-400 */
  --color-danger-hover:    oklch(29.6% 0.093 25.166);   /* ~red-900 */
  --color-danger-progress: oklch(63.7% 0.237 25.331);   /* ~red-500 */
  --color-danger-border:   oklch(44.4% 0.177 26.899);   /* ~red-700 */

  /* --- Warning (amber) --- */
  --color-warning:          oklch(82.7% 0.174 78.604);   /* ~amber-400 */
  --color-warning-surface:  oklch(27.9% 0.077 45.635);   /* ~amber-950 */
  --color-warning-icon:     oklch(82.7% 0.174 78.604);   /* ~amber-400 */
  --color-warning-hover:    oklch(31.1% 0.091 50.601);   /* ~amber-900 */
  --color-warning-border:   oklch(55.4% 0.163 48.998);   /* ~amber-700 */

  /* --- Success (green) --- */
  --color-success:          oklch(79.2% 0.209 151.711);  /* ~green-400 */
  --color-success-surface:  oklch(26.2% 0.065 152.934);  /* ~green-950 */
  --color-success-icon:     oklch(79.2% 0.209 151.711);  /* ~green-400 */
  --color-success-hover:    oklch(29.3% 0.094 153.051);  /* ~green-900 */
  --color-success-progress: oklch(72.3% 0.219 149.579);  /* ~green-500 */
  --color-success-border:   oklch(46.2% 0.141 148.96);   /* ~green-700 */

  /* --- Info (sky) --- */
  --color-info:          oklch(79.6% 0.15 235.169);   /* ~sky-400 */
  --color-info-surface:  oklch(24.4% 0.063 264.052);  /* ~sky-950 */
  --color-info-icon:     oklch(79.6% 0.15 235.169);   /* ~sky-400 */
  --color-info-hover:    oklch(28.3% 0.088 260.031);  /* ~sky-900 */
  --color-info-progress: oklch(71.4% 0.168 237.674);  /* ~sky-500 */
  --color-info-border:   oklch(45.1% 0.146 256.823);  /* ~sky-700 */
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/tailwind/tokens/_signals.css
git commit -m "feat(tokens): Add fixed signal color tokens for danger/warning/success/info"
```

---

### Task 4: Integrate Tokens into Tailwind and Register Theme

**Files:**
- Modify: `app/assets/tailwind/application.css:1-6`

- [ ] **Step 1: Add token imports and @theme inline registration**

At the top of `app/assets/tailwind/application.css`, replace lines 1-5:

Old:
```css
@import "tailwindcss";

/* Dark mode: class-based toggle via .dark on <html> instead of media query.
   This allows a three-way user preference (light/dark/system). */
@custom-variant dark (&:where(.dark, .dark *));
```

New:
```css
@import "tailwindcss";

/* Dark mode: class-based toggle via .dark on <html> instead of media query.
   This allows a three-way user preference (light/dark/system). */
@custom-variant dark (&:where(.dark, .dark *));

/* Design token layers */
@import "./tokens/_primitives.css";
@import "./tokens/_semantic.css";
@import "./tokens/_signals.css";

/* Register semantic tokens as Tailwind utilities via @theme inline.
   "inline" is required because these reference CSS custom properties
   that change under .dark — Tailwind needs to inline the var() references. */
@theme inline {
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
  --color-interactive-subtle: var(--color-interactive-subtle);

  /* Accent */
  --color-accent: var(--color-accent);
  --color-accent-hover: var(--color-accent-hover);

  /* Borders */
  --color-border: var(--color-border);
  --color-border-strong: var(--color-border-strong);
  --color-border-focus: var(--color-border-focus);

  /* Signals — Danger */
  --color-danger: var(--color-danger);
  --color-danger-surface: var(--color-danger-surface);
  --color-danger-icon: var(--color-danger-icon);
  --color-danger-hover: var(--color-danger-hover);
  --color-danger-progress: var(--color-danger-progress);
  --color-danger-border: var(--color-danger-border);

  /* Signals — Warning */
  --color-warning: var(--color-warning);
  --color-warning-surface: var(--color-warning-surface);
  --color-warning-icon: var(--color-warning-icon);
  --color-warning-hover: var(--color-warning-hover);
  --color-warning-border: var(--color-warning-border);

  /* Signals — Success */
  --color-success: var(--color-success);
  --color-success-surface: var(--color-success-surface);
  --color-success-icon: var(--color-success-icon);
  --color-success-hover: var(--color-success-hover);
  --color-success-progress: var(--color-success-progress);
  --color-success-border: var(--color-success-border);

  /* Signals — Info */
  --color-info: var(--color-info);
  --color-info-surface: var(--color-info-surface);
  --color-info-icon: var(--color-info-icon);
  --color-info-hover: var(--color-info-hover);
  --color-info-progress: var(--color-info-progress);
  --color-info-border: var(--color-info-border);
}
```

- [ ] **Step 2: Build Tailwind to verify tokens compile**

Run: `bin/rails tailwindcss:build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Verify generated CSS contains token utilities**

Run: `grep -c "surface-raised" app/assets/builds/tailwind.css`
Expected: Output is a number > 0, confirming Tailwind generated the utility classes.

- [ ] **Step 4: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat(tokens): Register design tokens in Tailwind @theme inline"
```

---

### Task 5: Migrate Layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Replace hardcoded colors in the layout**

In `app/views/layouts/application.html.erb`, make these substitutions:

Line 21 — body tag:
```erb
<!-- Old -->
<body class="min-h-screen flex flex-col bg-white dark:bg-gray-900 text-slate-800 dark:text-gray-200">

<!-- New -->
<body class="min-h-screen flex flex-col bg-surface-raised text-text-heading">
```

Lines 22-24 — skip link:
```erb
<!-- Old -->
<a href="#main-content"
   class="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:p-4 focus:bg-white focus:text-sky-700 focus:underline">

<!-- New -->
<a href="#main-content"
   class="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:p-4 focus:bg-surface-raised focus:text-interactive focus:underline">
```

- [ ] **Step 2: Run the test suite to verify no visual regressions**

Run: `bundle exec rspec spec/system --format progress`
Expected: All system specs pass (axe-core checks included).

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "refactor(tokens): Migrate layout to semantic design tokens"
```

---

### Task 6: Migrate Header Partial

**Files:**
- Modify: `app/views/shared/_header.html.erb`

- [ ] **Step 1: Replace all hardcoded colors in the header**

Apply these substitutions throughout `app/views/shared/_header.html.erb`:

Line 1 — header tag:
```erb
<!-- Old -->
<header class="sticky top-0 z-40 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-700"

<!-- New -->
<header class="sticky top-0 z-40 bg-surface-raised border-b border-border"
```

All nav link classes (lines 16-18, 20-22, 24-27, 30-32, 60-62, 64-66, 68-70, 73-75):
```erb
<!-- Old -->
class="min-h-[44px] flex items-center text-slate-700 dark:text-gray-300
        hover:text-sky-700 dark:hover:text-sky-400
        focus:outline-none focus:ring-2 focus:ring-sky-700 rounded px-2"

<!-- New -->
class="min-h-[44px] flex items-center text-text-body
        hover:text-interactive-hover
        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded px-2"
```

Logo link (lines 7-8):
```erb
<!-- Old -->
class="flex items-center gap-2 hover:opacity-80 transition-opacity
        focus:outline-none focus:ring-2 focus:ring-sky-700 rounded"

<!-- New -->
class="flex items-center gap-2 hover:opacity-80 transition-opacity
        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded"
```

Primary CTA button (lines 34-36 and 77-79):
```erb
<!-- Old -->
class="min-h-[44px] flex items-center px-4 rounded-md
        bg-sky-700 hover:bg-sky-800 text-white font-medium
        focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-sky-700"

<!-- New -->
class="min-h-[44px] flex items-center px-4 rounded-md
        bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium
        focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus"
```

Mobile menu button (lines 46-48):
```erb
<!-- Old -->
class="md:hidden min-h-[44px] min-w-[44px] flex items-center justify-center
       text-slate-700 dark:text-gray-300
       focus:outline-none focus:ring-2 focus:ring-sky-700 rounded"

<!-- New -->
class="md:hidden min-h-[44px] min-w-[44px] flex items-center justify-center
       text-text-body
       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded"
```

- [ ] **Step 2: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_header.html.erb
git commit -m "refactor(tokens): Migrate header partial to semantic design tokens"
```

---

### Task 7: Migrate Footer Partial

**Files:**
- Modify: `app/views/shared/_footer.html.erb`

- [ ] **Step 1: Replace all hardcoded colors in the footer**

Replace the entire file content of `app/views/shared/_footer.html.erb`:

```erb
<footer class="bg-surface border-t border-border mt-auto">
  <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
      <div class="flex flex-col sm:flex-row sm:items-center gap-6">
        <%= link_to main_app.root_path,
              class: "hover:opacity-80 transition-opacity
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" do %>
          <%= render "shared/site_logo", size: :small, show_name: true %>
        <% end %>

        <div class="flex items-center gap-6">
          <%= link_to t("footer.about"), main_app.about_path,
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
          <%= link_to t("footer.privacy"), main_app.privacy_path,
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
          <%= link_to t("footer.contact"), main_app.contact_path,
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
          <%= link_to t("footer.docs"), "/docs",
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
        </div>
      </div>
      <p class="text-sm text-text-muted">
        &copy; <%= Date.current.year %> <%= t("footer.copyright") %>
      </p>
    </div>
  </div>
</footer>
```

- [ ] **Step 2: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_footer.html.erb
git commit -m "refactor(tokens): Migrate footer partial to semantic design tokens"
```

---

### Task 8: Migrate Navigation, Hero, Theme Toggle, Site Logo, Feature Card, Activity Feed

**Files:**
- Modify: `app/views/shared/_navigation.html.erb`
- Modify: `app/views/shared/_hero.html.erb`
- Modify: `app/views/shared/_theme_toggle.html.erb`
- Modify: `app/views/shared/_site_logo.html.erb`
- Modify: `app/views/shared/_feature_card.html.erb`
- Modify: `app/views/shared/_activity_feed.html.erb`

- [ ] **Step 1: Migrate _navigation.html.erb**

Apply the Token-to-Class Reference mappings. Replace the file:

```erb
<nav aria-label="<%= t("navigation.aria_label") %>"
     class="bg-surface-raised border-b border-border">
  <div class="max-w-4xl mx-auto px-4 flex items-center justify-between h-16">
    <%= link_to t("application.name"), root_path,
          class: "text-lg font-bold text-text-heading
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>

    <div class="flex items-center gap-4">
      <% if authenticated? %>
        <%= link_to t("navigation.profile"), edit_account_profile_path,
              class: "min-h-[44px] flex items-center text-text-body
                      hover:text-interactive-hover
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded px-2" %>
        <%= link_to t("navigation.connected_accounts"), account_connected_accounts_path,
              class: "min-h-[44px] flex items-center text-text-body
                      hover:text-interactive-hover
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded px-2" %>
        <%= render "shared/workspace_switcher" %>
        <%= button_to t("navigation.sign_out"), session_path, method: :delete,
              class: "min-h-[44px] flex items-center text-text-body
                      hover:text-interactive-hover
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded px-2
                      cursor-pointer" %>
      <% else %>
        <%= link_to t("navigation.sign_in"), new_session_path,
              class: "min-h-[44px] flex items-center text-text-body
                      hover:text-interactive-hover
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded px-2" %>
        <%= link_to t("navigation.sign_up"), new_registration_path,
              class: "min-h-[44px] flex items-center px-4 rounded-md
                      bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium
                      focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus" %>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 2: Migrate _hero.html.erb**

```erb
<%# locals: (title:, subtitle: nil, cta_primary: nil, cta_primary_path: nil, cta_secondary: nil, cta_secondary_path: nil) %>
<section class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-16 sm:py-24 text-center">
  <h1 class="text-4xl sm:text-5xl font-bold text-text-heading tracking-tight">
    <%= title %>
  </h1>
  <% if subtitle %>
    <p class="mt-6 text-lg sm:text-xl text-text-muted max-w-2xl mx-auto">
      <%= subtitle %>
    </p>
  <% end %>
  <% if cta_primary %>
    <div class="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4">
      <%= link_to cta_primary, cta_primary_path,
            class: "min-h-[44px] flex items-center px-6 py-3 rounded-md
                    bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium text-lg
                    focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus" %>
      <% if cta_secondary %>
        <%= link_to cta_secondary, cta_secondary_path,
              class: "min-h-[44px] flex items-center px-6 py-3 rounded-md
                      border border-interactive text-interactive
                      hover:bg-interactive-subtle
                      focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus" %>
      <% end %>
    </div>
  <% end %>
</section>
```

- [ ] **Step 3: Migrate _theme_toggle.html.erb**

```erb
<%# locals: (style: :icon) %>
<button
  type="button"
  data-controller="theme-toggle"
  <% if authenticated? %>
    data-theme-toggle-url-value="<%= main_app.account_theme_preference_path %>"
    data-theme-toggle-signed-in-value="true"
  <% end %>
  data-action="click->theme-toggle#cycle"
  aria-label="<%= t("navigation.toggle_theme") %>"
  class="<%= style == :icon ? "min-h-[44px] min-w-[44px] flex items-center justify-center" : "min-h-[44px] flex items-center gap-2 px-2" %>
         text-text-body
         hover:text-interactive-hover
         focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded"
>
  <%# Sun icon (light mode) %>
  <svg data-theme-toggle-target="lightIcon" class="w-5 h-5 hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
  </svg>
  <%# Moon icon (dark mode) %>
  <svg data-theme-toggle-target="darkIcon" class="w-5 h-5 hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
  </svg>
  <%# Monitor icon (system mode) %>
  <svg data-theme-toggle-target="systemIcon" class="w-5 h-5 hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
  </svg>
  <% if style != :icon %>
    <span data-theme-toggle-target="label" class="text-sm">System</span>
  <% end %>
</button>
```

- [ ] **Step 4: Migrate _site_logo.html.erb**

```erb
<%# locals: (size: :medium, color_class: "text-interactive", show_name: false, name_class: "text-xl font-bold text-text-heading") %>
<% sizes = { small: "h-6 w-auto", medium: "h-8 w-auto", large: "h-10 w-auto" } %>
<% size_classes = sizes.fetch(size, sizes[:medium]) %>
<div class="flex items-center gap-2">
  <svg
    class="<%= size_classes %> <%= color_class %>"
    viewBox="0 0 494 251"
    fill="currentColor"
    aria-hidden="true"
  >
    <!-- SVG paths unchanged -->
  </svg>
  <% if show_name %>
    <span class="<%= name_class %>"><%= t('application.name') %></span>
  <% end %>
</div>
```

Note: Only the default parameter values change. The SVG content stays identical.

- [ ] **Step 5: Migrate _feature_card.html.erb**

```erb
<%# locals: (title:, description:) %>
<div class="p-6 bg-surface-raised rounded-lg border border-border">
  <h3 class="text-lg font-semibold text-text-heading"><%= title %></h3>
  <p class="mt-2 text-text-muted"><%= description %></p>
</div>
```

- [ ] **Step 6: Migrate _activity_feed.html.erb**

```erb
<section aria-label="<%= t('activity.title') %>" class="mt-8">
  <h2 class="text-lg font-semibold text-text-heading">
    <%= t("activity.title") %>
  </h2>
  <% if activities.any? %>
    <ol class="mt-4 space-y-3">
      <%= render partial: "activity_logs/activity_log", collection: activities, as: :activity_log %>
    </ol>
  <% else %>
    <p class="mt-4 text-sm text-text-muted"><%= t("activity.empty") %></p>
  <% end %>
</section>
```

- [ ] **Step 7: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add app/views/shared/_navigation.html.erb app/views/shared/_hero.html.erb app/views/shared/_theme_toggle.html.erb app/views/shared/_site_logo.html.erb app/views/shared/_feature_card.html.erb app/views/shared/_activity_feed.html.erb
git commit -m "refactor(tokens): Migrate shared partials to semantic design tokens"
```

---

### Task 9: Migrate Toast Partial

**Files:**
- Modify: `app/views/shared/_toast.html.erb`

- [ ] **Step 1: Replace toast with token-based version**

This is the highest-density file. Replace `app/views/shared/_toast.html.erb`:

```erb
<%# locals: (type:, message:) -%>
<%# Tailwind safelist — ensure dynamic toast classes are always generated:
  bg-info-surface border-info-border bg-success-surface border-success-border
  bg-warning-surface border-warning-border bg-danger-surface border-danger-border
  text-info text-success text-warning text-danger
  text-info-icon text-success-icon text-warning-icon text-danger-icon
  bg-info-progress bg-success-progress
  hover:bg-info-hover hover:bg-success-hover hover:bg-warning-hover hover:bg-danger-hover
%>
<%
  timeout = case type
            when "notice", "success"
              [5000, message.split.size * 500 + 1000].max.clamp(5000, 15000)
            else
              0
            end

  role = %w[alert error].include?(type) ? "alert" : "status"
  aria_live = %w[alert error].include?(type) ? "assertive" : "polite"

  type_classes = case type
                 when "notice"  then "bg-info-surface border-info-border"
                 when "success" then "bg-success-surface border-success-border"
                 when "alert"   then "bg-warning-surface border-warning-border"
                 when "error"   then "bg-danger-surface border-danger-border"
                 end

  text_color = case type
               when "notice"  then "text-info"
               when "success" then "text-success"
               when "alert"   then "text-warning"
               when "error"   then "text-danger"
               end

  icon_color = case type
               when "notice"  then "text-info-icon"
               when "success" then "text-success-icon"
               when "alert"   then "text-warning-icon"
               when "error"   then "text-danger-icon"
               end

  progress_color = case type
                   when "notice"  then "bg-info-progress"
                   when "success" then "bg-success-progress"
                   else ""
                   end

  close_hover = case type
                when "notice"  then "hover:bg-info-hover"
                when "success" then "hover:bg-success-hover"
                when "alert"   then "hover:bg-warning-hover"
                when "error"   then "hover:bg-danger-hover"
                end
%>
<div data-controller="toast"
     data-toast-timeout-value="<%= timeout %>"
     data-action="mouseenter->toast#pause mouseleave->toast#resume"
     role="<%= role %>"
     aria-live="<%= aria_live %>"
     aria-atomic="true"
     class="w-80 sm:w-96 max-w-[calc(100vw-2rem)] pointer-events-auto rounded-lg border shadow-lg overflow-hidden <%= type_classes %>">
  <div class="flex items-start gap-3 p-4">
    <div class="shrink-0 mt-0.5 <%= icon_color %>">
      <% case type %>
      <% when "notice" %>
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z" />
        </svg>
      <% when "success" %>
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
        </svg>
      <% when "alert" %>
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
        </svg>
      <% when "error" %>
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
        </svg>
      <% end %>
    </div>
    <p class="flex-1 text-sm leading-relaxed <%= text_color %>"><%= message %></p>
    <button type="button"
            aria-label="<%= t('toasts.close') %>"
            data-action="click->toast#dismiss"
            class="shrink-0 min-h-[44px] min-w-[44px] inline-flex items-center justify-center rounded-md -m-1 <%= close_hover %> focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-current">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-5" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
      </svg>
    </button>
  </div>
  <% if %w[notice success].include?(type) %>
    <div class="h-1 w-full">
      <div data-toast-target="progress" class="h-full <%= progress_color %>" style="width: 100%;"></div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass. Toast specs validate rendering and accessibility.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_toast.html.erb
git commit -m "refactor(tokens): Migrate toast partial to semantic signal tokens"
```

---

### Task 10: Migrate OAuth Buttons and Workspace Switcher

**Files:**
- Modify: `app/views/shared/_oauth_buttons.html.erb`
- Modify: `app/views/shared/_workspace_switcher.html.erb`

- [ ] **Step 1: Migrate _oauth_buttons.html.erb**

```erb
<% if oauth_enabled? %>
  <div class="space-y-3">
    <% enabled_oauth_providers.each do |provider_key, config| %>
      <%= button_to "/auth/#{provider_key}",
            method: :post,
            class: "w-full min-h-[44px] flex items-center justify-center gap-3 px-4 py-3 rounded-md
                    border border-border-strong
                    bg-surface-raised
                    text-text-body
                    hover:bg-surface
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:ring-offset-2
                    cursor-pointer" do %>
        <span class="font-medium"><%= t("oauth.sign_in_with", provider: config[:name]) %></span>
      <% end %>
    <% end %>
  </div>

  <div class="relative my-6">
    <div class="absolute inset-0 flex items-center">
      <div class="w-full border-t border-border"></div>
    </div>
    <div class="relative flex justify-center text-sm">
      <span class="px-4 bg-surface-raised text-text-muted">
        <%= t("oauth.or") %>
      </span>
    </div>
  </div>
<% end %>
```

Note: The `bg-surface-raised` on the "or" span must match the parent page background so the line appears to break behind it. Since auth pages use `bg-surface-raised` (via the layout body), this is correct.

- [ ] **Step 2: Migrate _workspace_switcher.html.erb**

```erb
<% if authenticated? && Current.user.workspaces.kept.any? %>
  <div data-controller="workspace-switcher"
       data-action="keydown->workspace-switcher#handleKeydown"
       class="relative">
    <button data-action="click->workspace-switcher#toggle"
            aria-expanded="false"
            aria-haspopup="true"
            class="min-h-[44px] flex items-center gap-2 px-3 py-2 rounded-md
                   text-text-body
                   hover:bg-surface-sunken
                   focus:outline-none focus:ring-2 focus:ring-interactive-focus">
      <%= t("navigation.workspaces") %>
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>

    <div data-workspace-switcher-target="menu"
         role="menu"
         class="hidden absolute right-0 mt-2 w-56 rounded-md bg-surface-overlay
                border border-border shadow-lg z-50">
      <% Current.user.workspaces.kept.each do |workspace| %>
        <%= link_to workspace_path(workspace), role: "menuitem",
              class: "block px-4 py-3 text-sm text-text-body
                      hover:bg-surface-sunken
                      focus:outline-none focus:bg-surface-sunken" do %>
          <span class="font-medium"><%= workspace.name %></span>
          <span class="block text-xs text-text-muted"><%= workspace.plan.titleize %></span>
        <% end %>
      <% end %>
      <div class="border-t border-border">
        <%= link_to t("navigation.new_workspace"), new_workspace_path, role: "menuitem",
              class: "block px-4 py-3 text-sm text-interactive
                      hover:bg-surface-sunken
                      focus:outline-none focus:bg-surface-sunken" %>
      </div>
    </div>
  </div>
<% end %>
```

- [ ] **Step 3: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_oauth_buttons.html.erb app/views/shared/_workspace_switcher.html.erb
git commit -m "refactor(tokens): Migrate OAuth buttons and workspace switcher to tokens"
```

---

### Task 11: Migrate Authentication Views

**Files:**
- Modify: `app/views/sessions/new.html.erb`
- Modify: `app/views/sessions/password_form.html.erb`
- Modify: `app/views/sessions/check_email.html.erb`
- Modify: `app/views/registrations/new.html.erb`
- Modify: `app/views/passwords/new.html.erb`
- Modify: `app/views/passwords/edit.html.erb`
- Modify: `app/views/magic_link_registrations/show.html.erb`
- Modify: `app/views/account/profiles/edit.html.erb`
- Modify: `app/views/account/passwords/new.html.erb`

- [ ] **Step 1: Migrate sessions/new.html.erb**

Apply the Token-to-Class Reference. Replace `app/views/sessions/new.html.erb`:

```erb
<% content_for(:title) { t("sessions.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("sessions.new.title") %>
  </h1>

  <%= render "shared/oauth_buttons" %>

  <%= turbo_frame_tag "sign_in_form" do %>
    <%= form_with url: main_app.session_lookup_path, class: "mt-8 space-y-6" do |form| %>
      <div>
        <%= form.label :email_address, t("sessions.new.email_label"),
              class: "block text-sm font-medium text-text-body" %>
        <%= form.email_field :email_address,
              required: true,
              autofocus: true,
              autocomplete: "email",
              class: "mt-1 block w-full rounded-md border border-border-strong
                      bg-surface-raised px-3 py-2
                      text-text-heading
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:border-interactive-focus" %>
      </div>

      <%= form.submit t("sessions.new.continue"),
            class: "w-full min-h-[44px] rounded-md px-4 py-2
                    bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:ring-offset-2
                    cursor-pointer" %>
    <% end %>
  <% end %>

  <div class="mt-6 text-center">
    <p class="text-sm text-text-muted">
      <%= t("sessions.new.no_account") %>
      <%= link_to t("sessions.new.sign_up"), main_app.new_registration_path,
            class: "text-interactive underline hover:no-underline
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
    </p>
  </div>
</div>
```

- [ ] **Step 2: Migrate remaining auth views**

Apply the same Token-to-Class Reference substitutions to all remaining auth views. The pattern is identical across all forms:

- Labels: `text-slate-700 dark:text-gray-300` → `text-text-body`
- Inputs: `border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-slate-900 dark:text-gray-100 focus:ring-sky-700 focus:border-sky-700` → `border-border-strong bg-surface-raised text-text-heading focus:ring-interactive-focus focus:border-interactive-focus`
- Submit buttons: `bg-sky-700 hover:bg-sky-800 text-white focus:ring-sky-700` → `bg-interactive hover:bg-interactive-hover text-text-on-interactive focus:ring-interactive-focus`
- Headings: `text-slate-900 dark:text-gray-100` → `text-text-heading`
- Muted text: `text-slate-600 dark:text-gray-400` → `text-text-muted`
- Links: `text-sky-700 dark:text-sky-400` → `text-interactive`
- Error blocks: `bg-red-50 dark:bg-red-900 text-red-700 dark:text-red-300` → `bg-danger-surface text-danger`
- Card backgrounds: `bg-gray-50 dark:bg-gray-800` → `bg-surface`
- Borders: `border-gray-200 dark:border-gray-700` → `border-border`
- Info panels: `bg-sky-100 dark:bg-sky-900 text-sky-700 dark:text-sky-300` → `bg-info-surface text-info`

Apply these to: `sessions/password_form.html.erb`, `sessions/check_email.html.erb`, `registrations/new.html.erb`, `passwords/new.html.erb`, `passwords/edit.html.erb`, `magic_link_registrations/show.html.erb`, `account/profiles/edit.html.erb`, `account/passwords/new.html.erb`.

- [ ] **Step 3: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass. Auth system specs validate sign-in, registration, and magic link flows.

- [ ] **Step 4: Commit**

```bash
git add app/views/sessions/ app/views/registrations/ app/views/passwords/ app/views/magic_link_registrations/ app/views/account/
git commit -m "refactor(tokens): Migrate authentication views to semantic design tokens"
```

---

### Task 12: Migrate Content Pages

**Files:**
- Modify: `app/views/pages/home.html.erb`
- Modify: `app/views/pages/about.html.erb`
- Modify: `app/views/pages/privacy.html.erb`
- Modify: `app/views/pages/contact.html.erb`
- Modify: `app/views/invitation_accepts/show.html.erb`
- Modify: `app/views/invitation_declines/show.html.erb`

- [ ] **Step 1: Migrate all content page views**

Apply the Token-to-Class Reference to each file. These pages use the same patterns as auth views (headings, text, links, buttons, section backgrounds). Read each file, apply the mapping, write it back.

Key patterns for content pages:
- Section backgrounds passed as parameters: `bg: "bg-gray-50 dark:bg-gray-800"` → `bg: "bg-surface"`
- Inline heading styles: same as auth views
- Link colors: same as auth views

- [ ] **Step 2: Run system specs**

Run: `bundle exec rspec spec/system --format progress`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/pages/ app/views/invitation_accepts/ app/views/invitation_declines/
git commit -m "refactor(tokens): Migrate content pages to semantic design tokens"
```

---

### Task 13: Migrate Workspace Views

**Files:**
- Modify: All files in `app/views/workspaces/` and subdirectories

- [ ] **Step 1: Migrate all workspace view files**

There are approximately 17 workspace-related view files. Apply the Token-to-Class Reference to each. Read each file, apply the mapping, write it back.

The patterns are identical to auth views plus:
- Status badges using `bg-green-100 text-green-800` → `bg-success-surface text-success`
- Table headers: `bg-gray-50 dark:bg-gray-800` → `bg-surface`
- Table borders: `border-gray-200 dark:border-gray-700` → `border-border`
- Destructive buttons: `bg-red-700 hover:bg-red-800 text-white` → `bg-danger hover:bg-danger-hover text-text-on-interactive` (add `--color-danger-hover` token if needed, or use `opacity-90`)

Files to migrate:
- `workspaces/index.html.erb`
- `workspaces/show.html.erb`
- `workspaces/new.html.erb`
- `workspaces/edit.html.erb`
- `workspaces/brandings/edit.html.erb`
- `workspaces/members/index.html.erb`
- `workspaces/members/edit.html.erb`
- `workspaces/invitations/index.html.erb`
- `workspaces/invitations/new.html.erb`
- `workspaces/settings/edit.html.erb`
- `workspaces/projects/index.html.erb`
- `workspaces/projects/show.html.erb`
- `workspaces/projects/new.html.erb`
- `workspaces/projects/edit.html.erb`
- `workspaces/projects/resources/index.html.erb`
- `workspaces/projects/resources/show.html.erb`
- `workspaces/projects/resources/new.html.erb`
- `workspaces/projects/resources/edit.html.erb`
- `workspaces/projects/resources/types/_document_form.html.erb`
- `workspaces/projects/invitations/new.html.erb`
- `workspaces/projects/memberships/index.html.erb`
- `workspaces/projects/memberships/new.html.erb`

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec --format progress`
Expected: All 566+ specs pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/workspaces/
git commit -m "refactor(tokens): Migrate workspace views to semantic design tokens"
```

---

### Task 14: Migrate Prose and Syntax Highlighting Styles

**Files:**
- Modify: `app/assets/tailwind/application.css` (prose and highlight sections)

- [ ] **Step 1: Replace prose styles with token references**

In `app/assets/tailwind/application.css`, replace the `.prose` section (after the `@theme inline` block) with:

```css
/* ==========================================================================
   Prose Styles (documentation pages rendered by Markdowndocs)
   The gem wraps rendered markdown in <div class="prose prose-indigo">.
   Tailwind 4 resets all element styles, so we define them here.
   Uses semantic tokens — no dark: overrides needed.
   ========================================================================== */

.prose {
  @apply text-text-body leading-relaxed;
}

.prose p {
  @apply text-base mb-4;
}

.prose h1 {
  @apply text-4xl font-bold text-text-heading mb-6 mt-8;
}

.prose h1:first-child {
  @apply mt-0;
}

.prose h2 {
  @apply text-3xl font-semibold text-text-heading mb-4 mt-10 pb-2 border-b border-border;
}

.prose h3 {
  @apply text-2xl font-semibold text-text-heading mb-3 mt-8;
}

.prose h4 {
  @apply text-xl font-semibold text-text-heading mb-2 mt-6;
}

.prose h5 {
  @apply text-lg font-semibold text-text-heading mb-2 mt-4;
}

.prose h6 {
  @apply text-base font-semibold text-text-heading mb-2 mt-4;
}

.prose a {
  @apply text-accent underline transition-colors duration-150;
  text-decoration-color: color-mix(in oklch, var(--color-accent) 50%, transparent);
}

.prose a:hover {
  @apply text-accent-hover;
  text-decoration-color: var(--color-accent);
}

.prose strong {
  @apply font-semibold text-text-heading;
}

.prose em {
  @apply italic;
}

.prose del, .prose s, .prose strike {
  @apply line-through text-text-muted;
}

.prose ul {
  @apply list-disc list-outside ml-6 mb-4;
}

.prose ol {
  @apply list-decimal list-outside ml-6 mb-4;
}

.prose ul li,
.prose ol li {
  @apply mb-2 text-base;
}

.prose li > ul,
.prose li > ol {
  @apply mt-2 mb-0;
}

.prose blockquote {
  @apply pl-4 py-2 my-6 italic text-text-muted bg-surface-sunken rounded-md;
  border-left: 4px solid var(--color-accent);
}

.prose code {
  @apply px-1.5 py-0.5 bg-surface-sunken text-text-heading text-sm font-mono rounded-md;
}

.prose pre code {
  @apply p-0 bg-transparent text-sm leading-relaxed block;
}

.prose pre {
  @apply mb-6 p-4 bg-surface border border-border rounded-lg overflow-x-auto;
}

.prose table {
  @apply w-full mb-6;
  border-collapse: collapse;
}

.prose table th {
  @apply bg-surface-sunken border border-border-strong px-4 py-2 text-left font-semibold text-text-heading;
}

.prose table td {
  @apply border border-border-strong px-4 py-2;
}

.prose img {
  @apply max-w-full h-auto rounded-lg shadow-sm my-6;
}

.prose hr {
  @apply my-8 border-border-strong;
}

.prose input[type="checkbox"] {
  @apply mr-2 rounded-md;
}

.prose input[type="checkbox"]:disabled {
  @apply opacity-60;
}
```

- [ ] **Step 2: Delete the entire `.dark .prose` override section**

Remove the block starting with `/* --- Dark Mode: Prose --- */` through `.dark .prose hr` (~lines 139-194 in the original file). These are no longer needed because the semantic tokens handle dark mode automatically.

- [ ] **Step 3: Replace syntax highlight base styles**

Replace the `.highlight` base styles (background only — keep the individual syntax colors hardcoded):

```css
.highlight {
  @apply bg-surface rounded-lg p-4 overflow-x-auto text-sm;
}

.highlight .hll {
  @apply bg-warning-surface;
}
```

Keep all individual syntax token colors (`.highlight .c`, `.highlight .k`, etc.) as-is — they are optimized for code readability, not theming.

- [ ] **Step 4: Replace dark mode syntax highlight overrides**

Replace the dark `.highlight` section with only the base overrides:

```css
/* --- Dark Mode: Syntax Highlighting (base only) --- */
.dark .highlight {
  @apply bg-surface;
}

.dark .highlight .hll {
  background-color: rgb(250 204 21 / 0.15);
}
```

Keep all individual dark syntax token color overrides (`.dark .highlight .c`, `.dark .highlight .k`, etc.) as-is.

- [ ] **Step 5: Delete Markdowndocs dark mode overrides**

Remove the entire `/* Markdowndocs Dark Mode Overrides */` section (~lines 551-626 in the original). These broad `.dark .text-gray-900`, `.dark .bg-white.rounded-lg` overrides were a workaround — the gem's views will inherit correct colors from the semantic token system via the layout.

- [ ] **Step 6: Migrate biscuit banner overrides**

Replace the biscuit banner section:

```css
/* ==========================================================================
   Biscuit Cookie Consent Banner — Theme Overrides
   Override gem CSS tokens to match site theme.
   ========================================================================== */

.biscuit-banner {
  --biscuit-bg: var(--color-surface-raised);
  --biscuit-color: var(--color-text-body);
  --biscuit-muted: var(--color-text-muted);
  --biscuit-accent: var(--color-interactive);
  --biscuit-accent-hover: var(--color-interactive-hover);
  --biscuit-border: var(--color-border);
  --biscuit-shadow-bottom: 0 -4px 16px rgba(0, 0, 0, 0.08);
  --biscuit-radius: 0.5rem;
  --biscuit-padding: 1.25rem 1.5rem;
}

.dark .biscuit-banner {
  --biscuit-shadow-bottom: 0 -4px 16px rgba(0, 0, 0, 0.3);
}

.dark .biscuit-btn--secondary:hover {
  background: rgba(255, 255, 255, 0.08);
}

.dark .biscuit-manage-link {
  color: var(--color-text-muted);
}

.biscuit-btn {
  min-height: 44px;
}

.biscuit-btn:focus-visible {
  outline: 2px solid var(--color-interactive-focus);
  outline-offset: 2px;
}
```

- [ ] **Step 7: Migrate the Markdowndocs layout**

Update `app/views/layouts/markdowndocs/application.html.erb` to use token classes if it has hardcoded colors.

- [ ] **Step 8: Build and run tests**

Run: `bin/rails tailwindcss:build && bundle exec rspec --format progress`
Expected: Build succeeds, all specs pass.

- [ ] **Step 9: Commit**

```bash
git add app/assets/tailwind/application.css app/views/layouts/markdowndocs/
git commit -m "refactor(tokens): Migrate prose, syntax, and third-party styles to tokens

Delete ~165 lines of dark mode CSS overrides replaced by semantic tokens."
```

---

### Task 15: Write Theming Guide

**Files:**
- Create: `docs/theming.md`

- [ ] **Step 1: Write the developer theming guide**

Create `docs/theming.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/theming.md
git commit -m "docs: Add theming guide for semantic design token system"
```

---

### Task 16: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec --format progress`
Expected: All 566+ specs pass, 0 failures.

- [ ] **Step 2: Build Tailwind and verify output**

Run: `bin/rails tailwindcss:build`
Expected: Clean build, no errors.

- [ ] **Step 3: Verify no remaining hardcoded sky/slate dark: patterns in views**

Run: `grep -r "dark:bg-gray\|dark:text-gray\|dark:border-gray\|bg-sky-\|text-sky-\|text-slate-\|border-gray-.*dark:" app/views/ --include="*.erb" -l`
Expected: No files returned. All hardcoded patterns have been replaced.

Note: Some files may still have non-color `dark:` prefixes (e.g., `dark:` for shadows or opacity). Those are acceptable.

- [ ] **Step 4: Verify axe accessibility passes**

Run: `bundle exec rspec spec/system --format progress`
Expected: All system specs pass with axe-core checks.

- [ ] **Step 5: Run RuboCop and linters**

Run: `bin/rubocop && npx markdownlint-cli2 docs/theming.md`
Expected: No new violations.

- [ ] **Step 6: Update feature audit checklist**

In `docs/feature-audit-agent-os.md`, mark "Semantic design tokens" as complete.

- [ ] **Step 7: Final commit**

```bash
git add docs/feature-audit-agent-os.md
git commit -m "chore: Mark semantic design tokens complete in feature audit"
```
