# Drop `projects.primary_color` Orphan — Design Spec

**Goal:** Remove the vestigial `primary_color` string column from `projects` and strip `:primary_color` from the project strong-params whitelist. Reduces the codebase's color-representation sprawl from three columns (two integer hues + one orphan string) to two consistent integer-hue columns (users + workspaces).

**Scope:** One new migration, one strong-params edit, auto-regenerated `db/schema.rb`. No tests added. Full suite must continue passing.

---

## Motivation

[db/schema.rb:158](db/schema.rb#L158) defines `t.string "primary_color"` on the `projects` table. The column was introduced by [db/migrate/20260326214450_create_projects.rb:9](db/migrate/20260326214450_create_projects.rb#L9) as part of the original project-creation migration and has not been touched since (roughly four weeks of git history).

**Nothing reads the column:**

- No views reference `project.primary_color` or any form field for it.
- No controller action sets or reads it (aside from the strong-params permission, below).
- No model method depends on it.
- No factories, fixtures, seeds, or tests set it.
- Full-suite grep confirms zero references in `app/`, `spec/factories/`, `spec/fixtures/`, `db/seeds*`.

**One place allows writes:** [app/controllers/workspaces/projects_controller.rb:61](app/controllers/workspaces/projects_controller.rb#L61) has `params.require(:project).permit(:name, :description, :primary_color)`. Any form posting `project[primary_color]=...` would write the value to the column, where nothing would ever read it. This is a principled-whitelist nit: strong-params should only permit fields the app actively uses.

**Why this column is the "three color representations" concern in memory.** The memory entry [project_color_strategy_needed.md](~/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_color_strategy_needed.md) flags three color representations in the codebase. Concretely:

| Table | Column | Type | Status |
| ----- | ------ | ---- | ------ |
| `users` | `primary_color` | integer | Active — drives user avatar/initials hue |
| `workspaces` | `primary_color` | integer | Active — drives workspace initials + branding cascade |
| `projects` | `primary_color` | **string** | Orphan — never read, never written by any production code path |

Workspaces originally had a `string` column too but went through a three-step migration in April 2026 to adopt the integer-hue pattern ([db/migrate/20260416163753_add_primary_color_hue_to_workspaces.rb](db/migrate/20260416163753_add_primary_color_hue_to_workspaces.rb), 20260416163801_backfill, 20260416163818_replace). Projects never got that treatment because nothing actually used the column.

## Non-Goals

- **Adding project branding** or any replacement color field. If project-level branding is ever needed, it will get its own full design cycle and adopt the `integer` OKLCH-hue pattern that `users` and `workspaces` use. Keeping a mis-shaped string placeholder for speculative future use is worse than dropping it cleanly — the eventual project-branding feature will want the correct schema anyway, not this one.
- **Touching `users.primary_color` or `workspaces.primary_color`.** Both are active and correct.
- **The planned OKLCH color-strategy unification** (from [project_oklch_color_unification.md](~/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_oklch_color_unification.md)). That work harmonizes the user/workspace hue representations with a future design pattern; it is unrelated to this orphan cleanup.
- **Preserving any existing data** in the column. User has confirmed no data worth keeping.

---

## Implementation

### Migration

Create `db/migrate/<timestamp>_remove_primary_color_from_projects.rb`:

```ruby
class RemovePrimaryColorFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :primary_color, :string
  end
end
```

Providing the `:string` type argument makes the migration fully reversible via `rails db:rollback` — Rails will re-add the column as `string` on rollback. Any data that was in the column is not restored (confirmed empty; no loss).

### Strong-params edit

In [app/controllers/workspaces/projects_controller.rb](app/controllers/workspaces/projects_controller.rb), line 61 (`project_params` method):

**Before:**

```ruby
params.require(:project).permit(:name, :description, :primary_color)
```

**After:**

```ruby
params.require(:project).permit(:name, :description)
```

### Schema dump

`db/schema.rb` will regenerate automatically when the migration runs (`bin/rails db:migrate`). Line 158 (the `t.string "primary_color"` entry in the projects table) disappears. No manual edit to `schema.rb`.

---

## Testing

No new tests added. Rationale:

- The migration's correctness is proven by the full suite (1033 examples) continuing to pass after it runs. If anything read or wrote the column, removing it would break those tests immediately.
- A defensive assertion like `expect(Project.columns.map(&:name)).not_to include("primary_color")` is tautological — the `schema.rb` diff already proves the column is gone.
- Removing `:primary_color` from strong params has no observable effect because no form or API call ever submits that parameter. Writing a test for "this parameter is no longer permitted" would be testing Rails's strong-params machinery, not our code.

The implicit test is: **full suite stays green after the migration runs and the strong-params entry is removed.** The plan will verify this explicitly.

---

## Files Touched

| Path | Change |
| ---- | ------ |
| `db/migrate/<timestamp>_remove_primary_color_from_projects.rb` | New — single `remove_column` migration |
| [app/controllers/workspaces/projects_controller.rb](app/controllers/workspaces/projects_controller.rb) | Remove `:primary_color` from `project_params` whitelist |
| [db/schema.rb](db/schema.rb) | Auto-regenerated when migration runs — the `t.string "primary_color"` line on projects disappears |

Two files modified, one file created. Schema dump regenerates itself.

## Rollout

- Standard Rails migration flow: `bin/rails db:migrate` runs the column drop, then the strong-params edit takes effect on deploy.
- Order of deploy doesn't matter: the strong-params change can land before the column drop (requests with `project[primary_color]` silently drop the param, same outcome as today's "write to an unused column"), and the column drop can land before the strong-params change (requests with the param would trigger an `ActiveRecord::UnknownAttributeError` — but no request sends this param today).
- Reversal: `rails db:rollback` re-adds the column as string (empty). Re-adding `:primary_color` to strong-params is a trivial revert of the controller edit.

## Open Questions

None.
