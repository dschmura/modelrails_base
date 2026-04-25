# Drop `projects.primary_color` Orphan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the vestigial `primary_color` string column from the `projects` table and strip `:primary_color` from the project strong-params whitelist.

**Architecture:** Two surgical changes: one Rails migration (`remove_column :projects, :primary_color, :string`) and one strong-params edit. `db/schema.rb` auto-regenerates when the migration runs. No tests added — the full 1033-example suite serves as the regression check.

**Tech Stack:** Rails 8.1 migrations, RSpec suite.

**Spec:** [docs/superpowers/specs/2026-04-24-drop-project-primary-color-design.md](docs/superpowers/specs/2026-04-24-drop-project-primary-color-design.md)

---

## File Map

| Path | Action | Purpose |
| ---- | ------ | ------- |
| `db/migrate/<generated-timestamp>_remove_primary_color_from_projects.rb` | Create (via generator) | Single `remove_column` migration, reversible |
| [app/controllers/workspaces/projects_controller.rb](app/controllers/workspaces/projects_controller.rb) | Modify (line 61) | Remove `:primary_color` from `project_params` whitelist |
| [db/schema.rb](db/schema.rb) | Auto-regenerated | Line 158 (`t.string "primary_color"`) disappears when migration runs |

Two files edited by hand, one generated, one auto-regenerated.

---

## Task 1 — Generate and write the migration

**Files:**

- Create: `db/migrate/<timestamp>_remove_primary_color_from_projects.rb`

- [ ] **Step 1.1: Generate the migration skeleton**

Run: `mise exec -- bin/rails generate migration RemovePrimaryColorFromProjects`

Expected output: a new file at `db/migrate/<timestamp>_remove_primary_color_from_projects.rb` with an empty `change` method. Note the actual timestamp-prefixed filename from the command's output.

- [ ] **Step 1.2: Write the migration body**

Open the generated file and replace its contents with:

```ruby
class RemovePrimaryColorFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :primary_color, :string
  end
end
```

The `:string` type argument is important — it makes the migration reversible via `rails db:rollback`. Without it, rollback would fail.

- [ ] **Step 1.3: Inspect the current schema to confirm the column exists**

Run: `grep -n 'primary_color' db/schema.rb`

Expected output (3 lines):

```text
158:    t.string "primary_color"
230:    t.integer "primary_color", default: 210
245:    t.integer "primary_color", default: 210
```

Line 158 is the orphan on `projects`. Lines 230 and 245 are the active columns on `users` and `workspaces` and must not be affected.

- [ ] **Step 1.4: Run the migration**

Run: `mise exec -- bin/rails db:migrate`

Expected output: the migration runs successfully. `db/schema.rb` regenerates with a new version timestamp.

- [ ] **Step 1.5: Confirm the column is gone and the other two are intact**

Run: `grep -n 'primary_color' db/schema.rb`

Expected output (2 lines, no more line 158 entry):

```text
<line>:    t.integer "primary_color", default: 210
<line>:    t.integer "primary_color", default: 210
```

Exact line numbers will differ after regeneration. The key: the `t.string "primary_color"` entry for `projects` is gone; the two integer entries remain.

- [ ] **Step 1.6: Run the full test suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: `1033 examples, 0 failures`. If any test fails, stop — something in the codebase was quietly reading the column and we missed it during the spec exploration.

- [ ] **Step 1.7: Commit the migration + schema dump**

```bash
git add db/migrate/*_remove_primary_color_from_projects.rb db/schema.rb
git commit -m "chore: drop orphan projects.primary_color column"
```

---

## Task 2 — Remove `:primary_color` from the project strong-params whitelist

**Files:**

- Modify: `app/controllers/workspaces/projects_controller.rb` (line 61)

- [ ] **Step 2.1: Confirm the current state of `project_params`**

Run: `sed -n '60,62p' app/controllers/workspaces/projects_controller.rb`

Expected output:

```text
    def project_params
      params.require(:project).permit(:name, :description, :primary_color)
    end
```

- [ ] **Step 2.2: Edit the strong-params line**

In `app/controllers/workspaces/projects_controller.rb`, replace line 61:

**Before:**

```ruby
      params.require(:project).permit(:name, :description, :primary_color)
```

**After:**

```ruby
      params.require(:project).permit(:name, :description)
```

- [ ] **Step 2.3: Run the full test suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: `1033 examples, 0 failures`. Removing an unused strong-params key should have zero behavioral impact; the suite is a sanity check.

- [ ] **Step 2.4: Commit**

```bash
git add app/controllers/workspaces/projects_controller.rb
git commit -m "chore: remove :primary_color from project strong-params whitelist"
```

---

## Task 3 — Commit design artifacts and verify branch

**Files:**

- Commit only: `docs/superpowers/specs/2026-04-24-drop-project-primary-color-design.md`
- Commit only: `docs/superpowers/plans/2026-04-24-drop-project-primary-color.md`

- [ ] **Step 3.1: Verify working tree state**

Run: `git status --short`

Expected:

```text
?? docs/superpowers/plans/2026-04-24-drop-project-primary-color.md
?? docs/superpowers/specs/2026-04-24-drop-project-primary-color-design.md
```

Nothing else should be uncommitted.

- [ ] **Step 3.2: Commit the spec and plan**

```bash
git add docs/superpowers/specs/2026-04-24-drop-project-primary-color-design.md \
        docs/superpowers/plans/2026-04-24-drop-project-primary-color.md
git commit -m "docs: drop-project-primary-color spec and implementation plan"
```

- [ ] **Step 3.3: Review branch commit history**

Run: `git log --oneline $(git merge-base HEAD main)..HEAD`

Expected: 3 commits in this order (newest last):

```text
chore: drop orphan projects.primary_color column
chore: remove :primary_color from project strong-params whitelist
docs: drop-project-primary-color spec and implementation plan
```

- [ ] **Step 3.4: Final suite run on top of all commits**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: `1033 examples, 0 failures`.

- [ ] **Step 3.5: Verify rollback still works (safety check)**

Run: `mise exec -- bin/rails db:rollback` then `mise exec -- bin/rails db:migrate`

Expected: rollback re-adds the column as `string` (data empty), forward migration drops it again. Zero errors. This confirms the migration is truly reversible as documented.

After confirming, leave the DB in the forward state (column gone) — Step 3.4's suite run already did that.

---

## Deferred (post-merge, with triggers)

| Item | Trigger |
| ---- | ------- |
| OKLCH color-strategy unification (user + workspace hues) | Independent future work per memory note; unrelated to this cleanup |
| Adding project-level branding (if ever needed) | Fresh design cycle — will adopt the integer-hue pattern users/workspaces already use |

## Open Questions

None.
