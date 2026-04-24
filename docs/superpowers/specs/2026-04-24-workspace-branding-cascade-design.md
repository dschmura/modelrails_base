# Workspace Branding CSS Activation — Design Spec

**Goal:** Activate the dormant workspace-branding CSS cascade by wiring the application layout to emit `data-workspace-branded` and a `--ws-primary` CSS custom property on `<main>` whenever a workspace is active. Interactive tokens (`--color-interactive`, hover, focus, subtle) will then recolor automatically per workspace, in both light and dark modes.

**Scope:** One layout file, one request spec, one docs addition. No schema changes, no controller changes, no new helpers. The cascade rules already exist in the stylesheet; this spec only connects the two ends.

---

## Motivation

[app/views/layouts/application.html.erb:30-33](app/views/layouts/application.html.erb#L30-L33) carries an explicit note:

> Workspace branding (`--ws-primary` theming buttons/links/focus rings) is planned but not yet implemented. When ready, set `data-workspace-branded` and `--ws-primary` here based on a dedicated `brand_color` column. For now, `primary_color` only affects the workspace icon/initials circle background via `workspace_helper`.

The infrastructure is complete:

- `workspaces.primary_color` (integer, 0–360 OKLCH hue, default `210`) is migrated, validated, persisted, editable via the identity picker hub.
- [app/assets/tailwind/application.css:128-145](app/assets/tailwind/application.css#L128-L145) defines `[data-workspace-branded] { --color-interactive: var(--ws-primary); ... }` with `color-mix(in oklch, ...)` derivations for hover/focus/subtle, plus a `.dark [data-workspace-branded]` variant.
- `WorkspaceScoped` concern ([app/controllers/concerns/workspace_scoped.rb](app/controllers/concerns/workspace_scoped.rb)) sets `Current.workspace` on all `/workspaces/...` routes.

What's missing: the layout never emits `data-workspace-branded` or `--ws-primary`, so the cascade never runs. Wiring it up is a handful of lines of ERB and a request spec.

The comment's reference to a "dedicated `brand_color` column" is superseded by the existing `primary_color` column — same semantics, already in place.

## Non-Goals

- **Projects branding.** `projects.primary_color` exists as a vestigial string column from an earlier design; the unification / cleanup is a separate conversation (Task B).
- **Color-strategy unification.** The memory entry [project_oklch_color_unification.md](~/.claude/projects/.../memory/project_oklch_color_unification.md) describes a future refactor to unify user + workspace color representations via the Evil Martians OKLCH pattern. Out of scope here; the existing integer-hue column is sufficient for this activation.
- **Changing the picker UX.** The identity picker hub and color-choice flow ([app/views/shared/_identity_picker_hub.html.erb](app/views/shared/_identity_picker_hub.html.erb)) are untouched.
- **Dark-mode tuning.** The cascade already provides a `.dark` variant at lines 140–145 of application.css. No new dark-mode work.
- **Personal workspaces as a special case.** Personal workspaces carry `primary_color` like any other workspace and will brand the same way. The schema default (210) matches the app's sky base, so a personal workspace with no color change is visually indistinguishable from today.

---

## Design Decisions (locked during brainstorming)

| Decision | Choice | Reasoning |
| -------- | ------ | --------- |
| DOM target for `data-workspace-branded` | `<main>` | Content area only. Header (workspace switcher, theme toggle, user menu) and footer (site links, cookie settings, dev trigger) stay neutral. Matches the existing comment's intent and preserves a clear boundary. |
| OKLCH formula for `--ws-primary` | `oklch(0.40 0.15 <hue>)` | Same L/C as the existing `bg-hue-interactive` utility. Reuses a proven AAA-safe pattern, keeps the design system coherent. `color-mix()` derivations in the cascade work correctly on this base. |
| When to emit the attribute | Always on workspace-scoped routes (when `Current.workspace` is present) | Database default is `210`, which matches the app's native sky hue — branding with 210 is a visual no-op. No need to distinguish "default" from "explicitly set to 210." |
| Nil fallback | `workspace.primary_color || 210` | The column allows nil; guard with 210 to prevent rendering `oklch(0.40 0.15 )` which browsers would reject. |

---

## Architecture

```text
Request to /workspaces/:slug/...
    │
    ▼
WorkspaceScoped concern sets Current.workspace
    │
    ▼
Layout renders <main> with:
  data-workspace-branded
  style="--ws-primary: oklch(0.40 0.15 <hue>)"
    │
    ▼
CSS cascade (application.css) matches [data-workspace-branded]:
  --color-interactive          ← var(--ws-primary)
  --color-interactive-hover    ← color-mix(oklch, ws-primary 80%, black)
  --color-interactive-focus    ← var(--ws-primary)
  --color-interactive-subtle   ← color-mix(oklch, ws-primary 10%, white)
    │
    ▼
Tailwind utilities that use these tokens (bg-interactive, hover:bg-interactive-hover,
focus:ring-interactive-focus, etc.) now render in the workspace's brand hue.
    │
    ▼ (dark mode)
.dark [data-workspace-branded] variants mix with white for appropriate contrast.
```

The feature has two parts — the *emitter* (layout ERB) and the *consumer* (CSS cascade). The consumer already exists; this spec only introduces the emitter.

---

## Implementation

### Layout change

Replace the current `<main>` block in [app/views/layouts/application.html.erb](app/views/layouts/application.html.erb):

**Before:**

```erb
<%# Workspace branding (--ws-primary theming buttons/links/focus rings) is planned
    but not yet implemented. When ready, set data-workspace-branded and --ws-primary
    here based on a dedicated brand_color column. For now, primary_color only affects
    the workspace icon/initials circle background via workspace_helper. %>
<main id="main-content" tabindex="-1" class="flex-1">
  <%= yield %>
</main>
```

**After:**

```erb
<main id="main-content"
      tabindex="-1"
      class="flex-1"
      <% if Current.workspace %>
        data-workspace-branded
        style="--ws-primary: oklch(0.40 0.15 <%= Current.workspace.primary_color || 210 %>);"
      <% end %>>
  <%= yield %>
</main>
```

No helper extraction — a single call site and a one-line inline style doesn't warrant its own method.

### CSP

Already satisfied. [config/initializers/content_security_policy.rb:14](config/initializers/content_security_policy.rb#L14) permits `style-src :self, :unsafe_inline`. This is the same pattern used by `workspace_helper.render_workspace_initials` for its `--hue` inline style — precedent in the codebase.

### Hue value sanitization

`primary_color` is an integer column with an `inclusion: { in: 0..360 }` validation (see [app/models/workspace.rb:27](app/models/workspace.rb#L27)). The value is numeric and bounded at the model layer — no ERB escaping concerns, no injection risk. `|| 210` guards against nil.

---

## Testing

New request spec: `spec/requests/workspaces/branding_cascade_spec.rb`

Four examples:

1. **Workspace route emits the attribute.** Sign in an owner, visit a workspace-scoped page, assert the response body includes `data-workspace-branded` and `--ws-primary: oklch(0.40 0.15 <hue>)` matching the workspace's `primary_color`.
2. **Non-workspace route omits the attribute.** Visit `/` (signed in or out), assert the response does NOT include `data-workspace-branded`.
3. **Custom hue rendering.** Workspace with `primary_color = 270` (purple). Assert the style string contains `oklch(0.40 0.15 270)`.
4. **Nil hue fallback.** Workspace with `primary_color = nil`. Assert the style falls back to `oklch(0.40 0.15 210)`.

No system spec. The cascade's effect (CSS variables recoloring buttons) is a consequence of the CSS layer, not a behavior to verify in Playwright. Attribute emission is the only new contract we're adding, and request specs verify that at the right layer.

---

## Documentation

Small addition to [app/docs/ui-patterns.md](app/docs/ui-patterns.md) under "Design Token Architecture" → new subsection "Workspace branding":

- Briefly describe that workspace-scoped routes emit `--ws-primary` on `<main>`.
- Show the cascade chain so developers understand which tokens recolor.
- Reference the hue-integer pattern and the default (210).

No other docs need updating. The CHANGELOG entry will accompany the implementation commit.

---

## Files Touched

| Path | Change |
| ---- | ------ |
| [app/views/layouts/application.html.erb](app/views/layouts/application.html.erb) | Replace `<main>` block; remove "planned but not yet implemented" comment |
| [app/docs/ui-patterns.md](app/docs/ui-patterns.md) | Add "Workspace branding" subsection under Design Token Architecture |
| `spec/requests/workspaces/branding_cascade_spec.rb` | New request spec (4 examples) |

Three files, ~40 lines net.

## Rollout

- No migration.
- No feature flag — the effect is purely visual, and the default hue (210) produces output indistinguishable from today.
- If reverted, set of workspaces with custom hues snap back to sky-base; no data loss.

## Open Questions

None. All scope and behavior decided during brainstorming.
