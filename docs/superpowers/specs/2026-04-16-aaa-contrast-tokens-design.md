# AAA Contrast for Interactive Tokens — Design Spec

**Goal:** Bring `--color-interactive` and OKLCH initials colors to WCAG 2.2 Level AAA (7:1 enhanced contrast ratio). Currently both pass AA (4.5:1) but fail AAA.

**Scope:** ~10 lines across 3 files. No new files, no new tests. The existing axe after-hook in system specs validates compliance automatically.

---

## Problem

Two categories of elements fail AAA color-contrast-enhanced (7:1):

1. **Interactive elements** (buttons, links, pills using `bg-interactive` + `text-text-on-interactive`): sky-700 (#0369a1) produces 5.93:1 with white text.

2. **Initials circles** (user avatar initials using `oklch(0.45 0.2 hue)` + white text): produces 5.98:1 at hue 210 (blue), varying slightly across hues.

Both pass AA (4.5:1). The project targets WCAG 2.2 Level AAA per CLAUDE.md.

## Solution

### Interactive tokens: remap from primary-700 to primary-800

In `app/assets/tailwind/tokens/_semantic.css`, change the light-mode interactive token mappings:

```css
/* Light mode (:root) */
--color-interactive:       var(--primary-800);   /* was: var(--primary-700) → 5.93:1 → now 7.56:1 */
--color-interactive-hover: var(--primary-900);   /* was: var(--primary-800) */
--color-interactive-focus: var(--primary-800);   /* was: var(--primary-700) */
--color-border-focus:      var(--primary-800);   /* was: var(--primary-700) */
```

This shifts every `bg-interactive` + `text-text-on-interactive` combination to AAA. The primitives layer is untouched — sky-700 and sky-800 still map to Tailwind's built-in values. One-line retheming ("swap sky → purple") continues to work.

Hover shifts from primary-800 to primary-900 to maintain the one-step-darker progression.

### Dark mode: verify existing contrast

Dark mode uses `--color-interactive: var(--primary-400)` with `--color-text-on-interactive: var(--neutral-900)`. Verify this combination already meets 7:1. If not, bump `--color-interactive` to `var(--primary-300)` and `--color-text-on-interactive` to `var(--neutral-950)`.

### Initials: lower OKLCH lightness from 0.45 to 0.35

All usages of `oklch(0.45 0.2 hue)` for initials backgrounds change to `oklch(0.35 0.2 hue)`:

- `app/helpers/avatar_helper.rb` — `render_initials_avatar` method
- `app/views/shared/_identity_picker.html.erb` — hub preview circle, source card circle, color picker slider gradient

At L=0.35, the worst-case hue (210/blue) produces 9.11:1 with white text — comfortably above 7:1 across the entire hue wheel.

### Accent tokens: out of scope

`--color-accent` (secondary-600, indigo) is used for prose links and documentation highlights. It may also fail AAA but is a separate concern — it uses a different palette and different text contexts. Can be audited in a follow-up.

## Files changed

| File | Change |
|------|--------|
| `app/assets/tailwind/tokens/_semantic.css` | Remap 4 light-mode tokens from primary-700 to primary-800/900. Possibly adjust dark-mode tokens. |
| `app/helpers/avatar_helper.rb` | Change `oklch(0.45` to `oklch(0.35` |
| `app/views/shared/_identity_picker.html.erb` | Change `oklch(0.45` to `oklch(0.35` in 3-4 locations |

## Verification

1. Run the axe diagnostic spec on the Initials modal state — should report 0 AAA violations
2. Run `CI=true` system specs — all 13 identity picker specs pass (axe after-hook catches regressions)
3. Run the full test suite — 961 examples, 0 failures
4. Visual spot-check in browser: profile page, workspace branding, any page with buttons

## What this does NOT cover

- Accent token (secondary palette) AAA review — separate follow-up
- Dark mode comprehensive AAA audit — verified for interactive only
- Workspace `primary_color` (hex-based branding) — separate concern, blocked on OKLCH unification
