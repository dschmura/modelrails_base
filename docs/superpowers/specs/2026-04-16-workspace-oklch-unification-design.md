# Workspace OKLCH Color Unification — Design Spec

**Goal:** Unify workspace and user color systems by converting workspace `primary_color` from hex string to integer hue (0-360). Move the color picker from the branding edit page into the identity picker modal. Derive all workspace theming from OKLCH.

**Scope:** Migration, model, views, CSS, helpers, one Stimulus controller deletion. Resolves the three-color-representation inconsistency documented in memory (`project_color_strategy_needed.md`).

---

## Design Token Lightness Values

Two OKLCH lightness values serve different rendering contexts. Both use chroma C=0.15 (slightly desaturated for professional appearance at these lightness levels).

| Context | Lightness | Chroma | Contrast vs white | Use |
|---------|-----------|--------|-------------------|-----|
| Interactive/branding (`--ws-primary`) | L=0.40 | C=0.15 | ~8:1 AAA | Buttons, links, focus rings, workspace dot in switcher |
| Initials circles (helpers) | L=0.35 | C=0.20 | ~9:1 AAA | Small text on avatar/logo circles (both user and workspace) |

**Why two values:** Interactive elements need to feel "clickable" — L=0.40 gives richness without being oppressively dark. Initials circles need maximum text contrast because the text is small (`text-xs` on source cards). L=0.35 gives more headroom above the 7:1 threshold.

These values must be documented as constants/comments where they appear, not scattered as magic numbers.

---

## Migration Strategy

SQLite cannot change a column's type in-place. The migration uses a three-step approach:

### Migration 1 — Add integer column

```ruby
class AddPrimaryColorHueToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :primary_color_hue, :integer, default: 210
  end
end
```

### Migration 2 — Backfill hex → hue

```ruby
class BackfillPrimaryColorHueOnWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.where.not(primary_color: [nil, ""]).find_each do |ws|
      hex = ws.primary_color
      hue = hex_to_hue(hex)
      ws.update_column(:primary_color_hue, hue)
    end
  end

  def down
    # No-op: reverse conversion is lossy
  end

  private

  def hex_to_hue(hex)
    r, g, b = hex.scan(/../).map { |c| c.to_i(16) / 255.0 }
    max = [r, g, b].max
    min = [r, g, b].min
    delta = max - min

    return 0 if delta.zero?

    hue = if max == r
            60 * (((g - b) / delta) % 6)
          elsif max == g
            60 * (((b - r) / delta) + 2)
          else
            60 * (((r - g) / delta) + 4)
          end

    hue.round.then { |h| h < 0 ? h + 360 : h }
  end
end
```

Best-effort conversion — the hue is extracted from the hex RGB via the standard HSL formula. The resulting OKLCH rendering will look similar but not identical to the original hex (different lightness/chroma). Workspace owners can fine-tune via the new slider.

### Migration 3 — Drop old column, rename new

```ruby
class ReplacePrimaryColorWithHueOnWorkspaces < ActiveRecord::Migration[8.1]
  def change
    remove_column :workspaces, :primary_color, :string
    rename_column :workspaces, :primary_color_hue, :primary_color
  end
end
```

After this migration, `workspaces.primary_color` is an integer column (0-360), matching `users.primary_color`.

---

## Model Changes

### `app/models/workspace.rb`

Remove:
```ruby
validates :primary_color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: :invalid_hex_color },
          allow_blank: true
```

Add:
```ruby
validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
```

Now matches `User#primary_color` validation exactly.

---

## Identity Picker Modal — Enable Color Picker for Workspace

### `app/views/workspaces/brandings/edit.html.erb`

Change:
```erb
has_color_picker: false,
```

To:
```erb
has_color_picker: true,
```

### `app/views/shared/_identity_picker.html.erb`

Change the `current_hue` computation (line 6) from:

```ruby
current_hue = is_user ? (model.primary_color || 210) : 210
```

To:

```ruby
current_hue = model.primary_color || 210
```

Both User and Workspace now have integer `primary_color`. No `is_user` branch needed.

---

## Branding Edit Page Cleanup

### Remove from `app/views/workspaces/brandings/edit.html.erb`

Delete the entire color section:
- Color palette heading + preset swatches radio group
- Custom color input (native `<input type="color">` + text field)
- Live color preview section
- Any references to `color-picker` Stimulus controller

The page retains:
- Heading (`t("workspaces.brandings.edit.title")`)
- Logo section (trigger → identity picker modal, which now includes the color picker)
- Submit button (for the `form_with` that wraps the page — still needed for form structure)

### Delete `app/javascript/controllers/color_picker_controller.js`

No other views reference this controller. Dead code after the branding page cleanup.

Remove any importmap pin for this controller if one exists.

---

## CSS Theming — `--ws-primary` from OKLCH

### `app/views/layouts/application.html.erb`

Change the `--ws-primary` inline style from hex to OKLCH.

Replace the entire block (lines 30-34):
```erb
<% ws_color = Current.workspace&.primary_color&.match(/\A#[0-9a-fA-F]{6}\z/)&.to_s %>
...
<% if ws_color.present? %>
  data-workspace-branded
  style="--ws-primary: <%= ws_color %>;"
```

With:
```erb
<% ws_hue = Current.workspace&.primary_color %>
...
<% if ws_hue.present? %>
  data-workspace-branded
  style="--ws-primary: oklch(0.40 0.15 <%= ws_hue %>);"
```

The hex regex guard (`match(/\A#[0-9a-fA-F]{6}\z/)`) must be replaced with a simple presence check — the value is now an integer, not a hex string.

The existing CSS rules in `app/assets/tailwind/application.css` work unchanged — `color-mix(in oklch, var(--ws-primary) 80%, black)` operates on the OKLCH value the same way it operated on hex.

### Dark mode

The existing dark-mode CSS:
```css
.dark [data-workspace-branded] {
  --color-interactive: color-mix(in oklch, var(--ws-primary) 70%, white);
}
```

This lightens the OKLCH value for dark backgrounds. Works identically with an OKLCH input — `color-mix` is color-space-aware.

---

## Workspace Helper

### `app/helpers/workspace_helper.rb` — `render_workspace_initials`

Change from raw hex:
```ruby
ws_color = workspace.primary_color&.match(/\A#[0-9a-fA-F]{6}\z/)&.to_s
style: "background: #{ws_color || 'var(--color-interactive)'};"
```

To OKLCH (matching `avatar_helper.rb`):
```ruby
hue = workspace.primary_color || 210
# L=0.35, C=0.20 — AAA contrast with white text for initials circles
style: "background-color: oklch(0.35 0.2 #{hue});"
```

---

## Workspace Switcher

### `app/views/shared/_workspace_switcher.html.erb`

Change the dot color from hex:
```erb
<% ws_dot_color = workspace.primary_color&.match(/\A#[0-9a-fA-F]{6}\z/)&.to_s || "var(--color-interactive)" %>
```

To OKLCH:
```erb
<% ws_dot_hue = workspace.primary_color || 210 %>
<% ws_dot_color = "oklch(0.40 0.15 #{ws_dot_hue})" %>
```

Uses the interactive lightness (L=0.40) since the dot is a UI indicator, not a text-bearing element.

---

## Controller

### `app/controllers/workspaces/brandings_controller.rb`

`branding_params` stays the same structurally — `params.require(:workspace).permit(:primary_color)`. The value arriving from the identity picker's hidden field is already an integer (the hue slider's value). Rails coerces to integer for the integer column.

The identity picker's hub form submits `primary_color` as a hidden field value synced by the `handleColorChange` JS method — this already works for User and will work for Workspace with no JS changes.

---

## Files Summary

### Files to create
- `db/migrate/TIMESTAMP_add_primary_color_hue_to_workspaces.rb`
- `db/migrate/TIMESTAMP_backfill_primary_color_hue_on_workspaces.rb`
- `db/migrate/TIMESTAMP_replace_primary_color_with_hue_on_workspaces.rb`

### Files to modify
- `app/models/workspace.rb` — validation change
- `app/views/workspaces/brandings/edit.html.erb` — enable color picker, remove color section
- `app/views/shared/_identity_picker.html.erb` — simplify `current_hue`
- `app/views/layouts/application.html.erb` — OKLCH `--ws-primary`
- `app/views/shared/_workspace_switcher.html.erb` — OKLCH dot color
- `app/helpers/workspace_helper.rb` — OKLCH initials
- `app/assets/tailwind/application.css` — possibly update `[data-workspace-branded]` condition (verify hex regex guard removal)
- `config/locales/en/workspaces.en.yml` — remove color picker locale keys if any
- `spec/models/workspace_spec.rb` — update validation tests
- `spec/requests/workspaces/brandings_spec.rb` — update any hex-dependent tests

### Files to delete
- `app/javascript/controllers/color_picker_controller.js`

---

## Testing Strategy

- **Model specs:** TDD for integer validation (0..360), replaces hex format tests
- **Request specs:** Update tests that send hex `primary_color` to send integer hue
- **System specs:** Existing workspace branding specs should pass (identity picker flow is the same, now with color picker enabled)
- **Visual verification:** Check workspace theming in both light and dark mode — buttons, links, focus rings, initials circles, workspace switcher dots
- **Full suite + CI=true** after all changes

## What this does NOT cover

- Project `primary_color` — projects also have a `primary_color` column (per `projects_controller.rb:61`). That's a separate concern and untouched by this work.
- Evil Martians single-hue derivation pattern — this spec uses fixed lightness values, not the full auto-derivation system described in the article. The fixed values are simpler and sufficient for now.
- Accent tokens (secondary palette) — unchanged, separate concern.
