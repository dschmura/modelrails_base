# Workspace OKLCH Color Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert workspace `primary_color` from hex string to integer hue (0-360), move the color picker into the identity picker modal, and derive all workspace theming from OKLCH — achieving full parity with the user avatar color system.

**Architecture:** Three-phase migration (add integer column → backfill hex→hue → drop old column + rename). Model validation switches from hex regex to integer range. Branding edit page sheds its color section (swatches, hex picker, preview) — the identity picker modal gains the hue slider. Layout/helpers/switcher all switch from hex to OKLCH rendering. The `color_picker_controller.js` is deleted.

**Tech Stack:** Rails 8.1, RSpec (TDD), Active Storage, OKLCH CSS, Stimulus

**Spec:** `docs/superpowers/specs/2026-04-16-workspace-oklch-unification-design.md`

**Important:** All commands must use `mise exec --` prefix.

**Design token lightness values (documented per spec requirement):**
- `L=0.40, C=0.15` — interactive/branding (`--ws-primary` for buttons, links, focus rings, workspace dots)
- `L=0.35, C=0.20` — initials circles (small text on avatar/logo circles, both user and workspace)

---

## File Structure

### Files to create
- `db/migrate/TIMESTAMP_add_primary_color_hue_to_workspaces.rb`
- `db/migrate/TIMESTAMP_backfill_primary_color_hue_on_workspaces.rb`
- `db/migrate/TIMESTAMP_replace_primary_color_with_hue_on_workspaces.rb`

### Files to modify
- `app/models/workspace.rb` — validation change (hex → integer)
- `app/views/workspaces/brandings/edit.html.erb` — enable color picker in modal, remove color section
- `app/views/shared/_identity_picker.html.erb` — simplify `current_hue`
- `app/views/layouts/application.html.erb` — OKLCH `--ws-primary`
- `app/views/shared/_workspace_switcher.html.erb` — OKLCH dot color
- `app/helpers/workspace_helper.rb` — OKLCH initials
- `app/controllers/workspaces/brandings_controller.rb` — integer coercion in `branding_params`
- `config/locales/en/workspaces.en.yml` — remove color picker locale keys
- `spec/models/workspace_spec.rb` — update validation tests
- `spec/requests/workspaces/brandings_spec.rb` — update hex → integer in all tests

### Files to delete
- `app/javascript/controllers/color_picker_controller.js`

---

### Task 1: Three-phase migration (hex → integer hue)

**Files:**
- Create: 3 migration files
- Test: `spec/models/workspace_spec.rb`

- [ ] **Step 1: Write failing model spec for integer primary_color**

Add to `spec/models/workspace_spec.rb`, replacing any existing `primary_color` tests (if they exist):

```ruby
describe "primary_color (integer hue)" do
  it "defaults to 210 (blue)" do
    workspace = create(:workspace)
    expect(workspace.primary_color).to eq(210)
  end

  it "validates inclusion in 0..360" do
    workspace = build(:workspace, primary_color: 180)
    expect(workspace).to be_valid

    workspace.primary_color = -1
    expect(workspace).not_to be_valid

    workspace.primary_color = 361
    expect(workspace).not_to be_valid
  end

  it "allows nil" do
    workspace = build(:workspace, primary_color: nil)
    expect(workspace).to be_valid
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/models/workspace_spec.rb -e "primary_color" --format documentation
```

Expected: FAIL — column is still a string with hex validation.

- [ ] **Step 3: Create migration 1 — add integer column**

```bash
mise exec -- bin/rails generate migration AddPrimaryColorHueToWorkspaces primary_color_hue:integer
```

Edit the generated file:

```ruby
class AddPrimaryColorHueToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :primary_color_hue, :integer, default: 210
  end
end
```

- [ ] **Step 4: Create migration 2 — backfill hex→hue**

```bash
mise exec -- bin/rails generate migration BackfillPrimaryColorHueOnWorkspaces
```

Edit:

```ruby
class BackfillPrimaryColorHueOnWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.where.not(primary_color: [nil, ""]).find_each do |ws|
      hex = ws.read_attribute(:primary_color)
      next unless hex.match?(/\A#[0-9a-fA-F]{6}\z/)

      hue = hex_to_hue(hex)
      ws.update_column(:primary_color_hue, hue)
    end
  end

  def down
    # No-op: reverse conversion is lossy
  end

  private

  def hex_to_hue(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
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

- [ ] **Step 5: Create migration 3 — drop old column, rename new**

```bash
mise exec -- bin/rails generate migration ReplacePrimaryColorWithHueOnWorkspaces
```

Edit:

```ruby
class ReplacePrimaryColorWithHueOnWorkspaces < ActiveRecord::Migration[8.1]
  def change
    remove_column :workspaces, :primary_color, :string
    rename_column :workspaces, :primary_color_hue, :primary_color
  end
end
```

- [ ] **Step 6: Run all three migrations**

```bash
mise exec -- bin/rails db:migrate
```

- [ ] **Step 7: Update model validation**

In `app/models/workspace.rb`, remove the hex validation:

```ruby
validates :primary_color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: :invalid_hex_color },
          allow_blank: true
```

Replace with:

```ruby
validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
```

- [ ] **Step 8: Run model spec**

```bash
mise exec -- bundle exec rspec spec/models/workspace_spec.rb -e "primary_color" --format documentation
```

Expected: PASS.

- [ ] **Step 9: Run full suite to find breakage**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: FAILURES in branding request specs (they send hex strings). That's expected — Task 2 fixes those.

- [ ] **Step 10: Commit**

```bash
git add db/migrate/ app/models/workspace.rb spec/models/workspace_spec.rb db/schema.rb
git commit -m "feat: migrate workspace primary_color from hex string to integer hue"
```

---

### Task 2: Update request specs (hex → integer)

**Files:**
- Modify: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Update all hex references to integer hue**

In `spec/requests/workspaces/brandings_spec.rb`, find and replace ALL hex color values with integer hues:

- `"#6366f1"` → `270` (approximate indigo hue)
- `"#0d9488"` → `170` (approximate teal hue)
- `"bad-value"` → `"bad-value"` (keep as invalid for error tests — or use `999` for integer-based invalid value)

Specific changes:

1. "updates the primary color" test (around line 26-30):
```ruby
it "updates the primary color" do
  patch workspace_branding_path(workspace), params: {
    workspace: { primary_color: 270 }
  }
  expect(workspace.reload.primary_color).to eq(270)
end
```

2. "redirects with success message" test (around line 41-46): change `primary_color: "#6366f1"` to `primary_color: 270`

3. "updates both logo and color" test (around line 49-50): change `primary_color: "#0d9488"` to `primary_color: 170`

4. Turbo stream test (around line 114): change `primary_color: "#6366f1"` to `primary_color: 270`

5. Save failure tests (around line 194-208): change `primary_color: "bad-value"` to `primary_color: 999`. Also update the mocked error message from "Primary color is invalid" to something the integer validation would produce, or simply use `allow_any_instance_of(Workspace).to receive(:save).and_return(false)` to simulate failure without depending on the specific validation message.

- [ ] **Step 2: Run the full brandings spec**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb --format documentation
```

Expected: PASS — all tests adapted to integer.

- [ ] **Step 3: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass (973+ examples, 0 failures).

- [ ] **Step 4: Commit**

```bash
git add spec/requests/workspaces/brandings_spec.rb
git commit -m "test: update branding specs from hex to integer hue"
```

---

### Task 3: Enable color picker in modal + simplify identity picker

**Files:**
- Modify: `app/views/workspaces/brandings/edit.html.erb`
- Modify: `app/views/shared/_identity_picker.html.erb`

- [ ] **Step 1: Enable color picker for workspace**

In `app/views/workspaces/brandings/edit.html.erb`, line 43, change:

```erb
has_color_picker: false,
```

To:

```erb
has_color_picker: true,
```

- [ ] **Step 2: Simplify `current_hue` in identity picker**

In `app/views/shared/_identity_picker.html.erb`, line 6, change:

```ruby
current_hue = is_user ? (model.primary_color || 210) : 210
```

To:

```ruby
current_hue = model.primary_color || 210
```

Both User and Workspace now have integer `primary_color`. No conditional needed.

- [ ] **Step 3: Run system specs to verify modal works**

```bash
mise exec -- bundle exec rspec spec/system/workspaces/brandings_spec.rb --format documentation
```

Expected: 2 examples, 0 failures.

- [ ] **Step 4: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/views/workspaces/brandings/edit.html.erb app/views/shared/_identity_picker.html.erb
git commit -m "feat: enable OKLCH color picker in workspace identity picker modal"
```

---

### Task 4: Remove color section from branding page + delete color_picker_controller

**Files:**
- Modify: `app/views/workspaces/brandings/edit.html.erb`
- Delete: `app/javascript/controllers/color_picker_controller.js`
- Modify: `config/locales/en/workspaces.en.yml` (remove unused keys)

- [ ] **Step 1: Remove the color section from branding edit page**

In `app/views/workspaces/brandings/edit.html.erb`, delete everything from line 50 (the `<%# Color palette %>` comment) through line 111 (the closing `</div>` of the live preview section). This removes:
- The color palette heading
- The preset swatch radio group
- The custom color input (native picker + text field)
- The live preview

Also remove the `data: { controller: "color-picker" }` attribute from the `form_with` tag on line 9. Change:

```erb
<%= form_with model: @workspace, url: workspace_branding_path(@workspace), method: :patch,
      class: "mt-8 space-y-6", data: { controller: "color-picker" } do |form| %>
```

To:

```erb
<%= form_with model: @workspace, url: workspace_branding_path(@workspace), method: :patch,
      class: "mt-8 space-y-6" do |form| %>
```

The resulting page should contain only:
1. Heading
2. Logo section (trigger → identity picker modal with color picker inside)
3. Submit button

- [ ] **Step 2: Delete the color picker Stimulus controller**

```bash
rm app/javascript/controllers/color_picker_controller.js
```

- [ ] **Step 3: Remove unused locale keys**

In `config/locales/en/workspaces.en.yml`, under `workspaces.brandings.edit`, remove keys that were only used by the deleted color section:
- `color_palette_label`
- `color_custom_label`
- `preview`
- `color_label` (check if still used elsewhere — if not, remove)

Keep `logo_label`, `change_logo`, `remove_logo`, `title`, `submit`.

- [ ] **Step 4: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass. If any test references `color-picker` controller or the deleted locale keys, update/remove those references.

- [ ] **Step 5: Rebuild Tailwind CSS**

```bash
mise exec -- bin/rails tailwindcss:build
```

The deleted controller's class references may have been included in the CSS build. Rebuild to prune.

- [ ] **Step 6: Commit**

```bash
git add app/views/workspaces/brandings/edit.html.erb config/locales/en/workspaces.en.yml
git rm app/javascript/controllers/color_picker_controller.js
git commit -m "chore: remove hex color picker from branding page (now in identity modal)"
```

---

### Task 5: OKLCH theming — layout, helper, switcher

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/helpers/workspace_helper.rb`
- Modify: `app/views/shared/_workspace_switcher.html.erb`

- [ ] **Step 1: Update layout — `--ws-primary` from OKLCH**

In `app/views/layouts/application.html.erb`, replace lines 30-35:

```erb
    <% ws_color = Current.workspace&.primary_color&.match(/\A#[0-9a-fA-F]{6}\z/)&.to_s %>
    <main id="main-content" tabindex="-1" class="flex-1"
          <% if ws_color.present? %>
            data-workspace-branded
            style="--ws-primary: <%= ws_color %>;"
          <% end %>>
```

With:

```erb
    <% ws_hue = Current.workspace&.primary_color %>
    <main id="main-content" tabindex="-1" class="flex-1"
          <% if ws_hue.present? %>
            data-workspace-branded
            style="--ws-primary: oklch(0.40 0.15 <%= ws_hue %>);"
          <% end %>>
```

- [ ] **Step 2: Update workspace_helper — OKLCH initials**

In `app/helpers/workspace_helper.rb`, replace the `render_workspace_initials` method (lines 34-42):

```ruby
def render_workspace_initials(workspace, config)
  ws_color = workspace.primary_color&.match(/\A#[0-9a-fA-F]{6}\z/)&.to_s

  content_tag :div, workspace.initials,
    class: "#{config[:css]} #{config[:text]} rounded-full flex items-center justify-center
            font-semibold text-white",
    style: "background: #{ws_color || 'var(--color-interactive)'};",
    aria: { hidden: true }
end
```

With:

```ruby
def render_workspace_initials(workspace, config)
  hue = workspace.primary_color || 210
  # L=0.35, C=0.20 — AAA contrast with white text for initials circles
  style = "background-color: oklch(0.35 0.2 #{hue});"

  content_tag :div, workspace.initials,
    class: "#{config[:css]} #{config[:text]} rounded-full flex items-center justify-center
            font-semibold text-white",
    style: style,
    aria: { hidden: true }
end
```

- [ ] **Step 3: Update workspace switcher — OKLCH dots**

In `app/views/shared/_workspace_switcher.html.erb`, replace line 30:

```erb
<% ws_dot_color = workspace.primary_color&.match(/\A#[0-9a-fA-F]{6}\z/)&.to_s || "var(--color-interactive)" %>
```

With:

```erb
<% ws_dot_hue = workspace.primary_color || 210 %>
<% ws_dot_color = "oklch(0.40 0.15 #{ws_dot_hue})" %>
```

- [ ] **Step 4: Rebuild Tailwind CSS**

```bash
mise exec -- bin/rails tailwindcss:build
```

- [ ] **Step 5: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/application.html.erb app/helpers/workspace_helper.rb app/views/shared/_workspace_switcher.html.erb
git commit -m "feat: derive workspace theming from OKLCH hue instead of hex"
```

---

### Task 6: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: 973+ examples, 0 failures.

- [ ] **Step 2: Run system specs with CI=true**

```bash
CI=true mise exec -- bundle exec rspec spec/system/ --format progress
```

Expected: All system specs pass.

- [ ] **Step 3: Visual verification in browser**

Start dev server and check:

1. **Workspace show page** — logo/initials render correctly with OKLCH color
2. **Branding edit page** — only shows logo section + identity picker modal (no color section on page)
3. **Identity picker modal** — hue slider appears when Initials is selected, color updates live preview
4. **Workspace theming** — buttons, links, focus rings themed with the OKLCH-derived `--ws-primary`
5. **Dark mode** — workspace theming adapts correctly (lighter brand color on dark backgrounds)
6. **Workspace switcher** — dot colors render as OKLCH circles, visually match the workspace theme
7. **Switch color + save** — change hue in modal, save, verify page reflects the new color everywhere

- [ ] **Step 4: Verify no references to hex primary_color remain**

```bash
grep -rn '#[0-9a-fA-F]\{6\}\|hex_color\|match.*#.*fA-F' app/ --include='*.rb' --include='*.erb' --include='*.js' | grep -i 'primary_color\|ws.primary\|ws_color'
```

Expected: No matches (all hex references replaced with OKLCH).

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|-----------------|------|
| Migration: hex string → integer hue (3-phase) | Task 1 ✓ |
| Model: integer validation 0..360 | Task 1 ✓ |
| Identity picker: enable color picker for workspace | Task 3 ✓ |
| Identity picker: simplify `current_hue` | Task 3 ✓ |
| Branding page: remove color section | Task 4 ✓ |
| Delete `color_picker_controller.js` | Task 4 ✓ |
| Layout: `--ws-primary` from OKLCH (L=0.40, C=0.15) | Task 5 ✓ |
| workspace_helper: OKLCH initials (L=0.35, C=0.20) | Task 5 ✓ |
| Workspace switcher: OKLCH dots | Task 5 ✓ |
| Lightness values documented | Task 5 (comments in code) + plan header ✓ |
| Test updates (hex → integer) | Task 2 ✓ |
| Verify no hex references remain | Task 6 ✓ |

### Placeholder scan

No TBD, TODO, or vague instructions.

### Type consistency

- `primary_color` — integer throughout (model, specs, views, helpers)
- `oklch(0.40 0.15 hue)` — consistent for interactive/branding contexts
- `oklch(0.35 0.2 hue)` — consistent for initials circles
- `ws_hue` variable name — used in layout and switcher (consistent)
