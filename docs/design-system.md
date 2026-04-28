# Design System

ModelRails uses a layered design system anchored on TailwindCSS 4. This document is the source of truth for spacing, component utilities, and naming conventions.

## Spacing

### Preferred scale (convention)

When applying Tailwind spacing utilities (`mt-*`, `p-*`, `gap-*`), prefer this 9-step subset of the default scale for visual rhythm:

| Step | Value | Pixels |
|------|-------|--------|
| `0`  | `0`        | 0   |
| `1`  | `0.25rem`  | 4   |
| `2`  | `0.5rem`   | 8   |
| `3`  | `0.75rem`  | 12  |
| `4`  | `1rem`     | 16  |
| `6`  | `1.5rem`   | 24  |
| `8`  | `2rem`     | 32  |
| `12` | `3rem`     | 48  |
| `16` | `4rem`     | 64  |

The full Tailwind default scale (`0.5`, `1.5`, `2.5`, etc.) remains available. Reach for intermediate values only when the preferred steps would compromise the layout — and prefer to add a semantic token (see below) over inline arbitrariness.

### Semantic spacing tokens (CSS-var-only)

Defined in `app/assets/tailwind/tokens/_spacing.css`. These encode reusable composition rules:

| Token | Value | Meaning |
|-------|-------|---------|
| `--space-section-gap`        | `2rem`    (32px) | Vertical gap between top-level page sections |
| `--space-row-padding`        | `0.75rem` (12px) | Internal vertical padding on list-row items |
| `--space-action-group-gap`   | `0.75rem` (12px) | Gap between trailing action buttons |
| `--form-input-height`        | `2.75rem` (44px) | Touch-target height for buttons + form inputs |

**Policy:** These are CSS variables only. They are *not* registered in `@theme` and have no Tailwind utility equivalents. Consume them only inside `@layer components` rules in `app/assets/tailwind/application.css` or inside the `TailwindFormBuilder` constants.

**`--form-input-height` consumers:**

- `.btn-touch-target` (in `application.css`) — uses `var(--form-input-height)` for `min-height` and `min-width` so buttons hit the WCAG 2.2 AAA touch-target minimum.
- `TailwindFormBuilder::FIELD_BASE` (text inputs, selects, textareas) — uses `min-h-[var(--form-input-height)]`.
- `TailwindFormBuilder::SUBMIT_CLASSES` (submit buttons) — same.
- `TailwindFormBuilder::FILE_FIELD_CLASSES` (file uploads, via `file:` prefix) — same.

To change the touch-target height for these four consumers (e.g., bump to 48px), edit `--form-input-height` in `tokens/_spacing.css`. The unmigrated `min-h-[44px]` sites listed below will need a separate sweep.

**Known gaps (incremental migration):** A number of view partials still hardcode `min-h-[44px]` directly and will migrate to the token as each partial is touched in subsequent branches:

- `app/views/shared/` partials including `_header.html.erb`, `_footer.html.erb`, `_navigation.html.erb`, `_user_menu.html.erb`, `_modal.html.erb`, `_confirm_dialog.html.erb`, `_theme_toggle.html.erb`, `_a11y_sim.html.erb`, `_identity_picker.html.erb`, `_toast_card.html.erb`, `_workspace_switcher.html.erb`, `_oauth_buttons.html.erb`, `_hero.html.erb`
- Several workspace pages and project/membership/invitation views
- `app/views/sessions/email_error.html.erb` — hand-rolls form-input classes, bypasses `TailwindFormBuilder`

The form builder + `.btn-touch-target` migration is the *first* unification, not the last. Run `grep -rl 'min-h-\[44px\]' app/views/` to see the current set of unmigrated sites; track as design-system-debt.

## Component utilities

Defined in `application.css` under `@layer components`. Apply via class names in templates.

### Buttons

| Class | Purpose |
|-------|---------|
| `.btn-touch-target` | 44×44 minimum sizing + flex centering. Applies WCAG 2.2 AAA touch-target compliance. Reads `--form-input-height`. |
| `.btn-text`         | Base text-only button styling: font-weight, underline, focus-visible ring base, hover. |
| `.btn-text-danger`     | Color variant — danger semantic color + matching focus-visible ring. |
| `.btn-text-interactive` | Color variant — interactive semantic color + matching focus-visible ring. |

**Composition pattern:**

```erb
<%= button_to "Cancel",
      cancel_path,
      class: "btn-touch-target btn-text btn-text-danger text-sm" %>
```

**Class ordering convention:** apply in this order (sizing → base → variant → modifier):

1. `.btn-touch-target` (sizing primitive)
2. `.btn-text` (base styling — font-weight, underline, focus ring)
3. `.btn-text-{color}` (semantic color variant)
4. `text-sm` or other Tailwind modifiers (template-side decisions)

Note: text size (e.g., `text-sm`) stays in the template, not inside `.btn-text`. This keeps inheritance transparent for readers — a developer can see the size in the template without diving into component CSS.

**Focus-ring pattern:** `.btn-text` uses `focus-visible:` (not `focus:`). This means the focus ring shows for keyboard navigation but not mouse clicks — matches the project's existing `.biscuit-btn` pattern and modern WCAG-AAA UX expectations.

### Layout

| Class | Purpose |
|-------|---------|
| `.page-container` | `max-w-2xl mx-auto px-4` — apply to outer wrapper of any settings/account/form-centric page. |
| `.action-group`   | Inline-flex with `--space-action-group-gap` — wrap groups of trailing action buttons. |

`.page-container` is intentionally narrow (`max-w-2xl`, ~672px) — suited for settings, account flows, and form pages. A wider variant (`.page-container-wide`, max-w-4xl/6xl) can be added when a page needs it; don't override `max-width` inline, introduce the named variant instead.

`.action-group` uses `inline-flex` (not `flex`) deliberately — more forgiving when nested inside a flex/grid parent, which is the typical case for trailing button groups in `<li class="flex items-center justify-between">` rows.

## Adding new tokens or utilities

1. **Spacing primitives** → don't add. Use Tailwind defaults.
2. **Spacing composition** (a recurring pattern across views) → add a semantic CSS var to `_spacing.css`, consume it inside a `@layer components` rule. Never register in `@theme`.
3. **Color tokens** → see `tokens/_primitives.css`, `_semantic.css`, `_signals.css`.
4. **New component utility** → add to the existing `@layer components` block in `application.css`. Keep the class name structural (`.btn-text`, not `.danger-button`). Document in this file.
5. **Touch-target changes** → edit `--form-input-height` in `tokens/_spacing.css`. The form builder + `.btn-touch-target` will pick up the change automatically. Remaining hardcoded `min-h-[44px]` sites in view partials (see the "Known gaps" section above) will need a follow-up sweep.

## Migration recipe (before / after)

A typical refactor takes a long ad-hoc class string and collapses it to a short composition. From `app/views/account/connected_accounts/index.html.erb` (the proof view):

**Before:**

```erb
<%= button_to t("account.connected_accounts.index.cancel_action"),
      account_connected_account_path(authentication),
      method: :delete,
      class: "text-sm font-medium text-danger underline hover:no-underline
              focus:outline-none focus:ring-2 focus:ring-danger rounded
              min-h-[44px] min-w-[44px] inline-flex items-center justify-center px-2",
      form: { class: "inline" } %>
```

**After:**

```erb
<%= button_to t("account.connected_accounts.index.cancel_action"),
      account_connected_account_path(authentication),
      method: :delete,
      class: "btn-touch-target btn-text btn-text-danger text-sm",
      form: { class: "inline" } %>
```

The change is class-string only. ARIA labels, button text, paths, methods, and `form:` options stay verbatim. The `text-sm` modifier stays on the template per the convention above (`.btn-text` does not include text-size). The new class string also picks up the `focus-visible:` improvement automatically via `.btn-text`.
