# Workspace Branding Cascade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the dormant workspace-branding CSS cascade by emitting `data-workspace-branded` and a `--ws-primary` custom property on `<main>` whenever `Current.workspace` is present, so interactive tokens automatically recolor per workspace.

**Architecture:** The CSS cascade in `app/assets/tailwind/application.css` already defines `[data-workspace-branded] { --color-interactive: var(--ws-primary); ... }` with `color-mix(in oklch, ...)` derivations for hover/focus/subtle and a `.dark` variant. The only missing piece is the layout emitting the attribute + the custom property. This plan wires that up and nothing else.

**Tech Stack:** Rails 8.1 ERB, TailwindCSS 4 with OKLCH semantic tokens, RSpec request specs.

**Spec:** [docs/superpowers/specs/2026-04-24-workspace-branding-cascade-design.md](docs/superpowers/specs/2026-04-24-workspace-branding-cascade-design.md)

---

## File Map

| Path | Action | Purpose |
| ---- | ------ | ------- |
| `app/views/layouts/application.html.erb` | Modify | Replace `<main>` block to emit `data-workspace-branded` + `--ws-primary` when `Current.workspace` is present; delete stale "planned" comment |
| `spec/requests/workspaces/branding_cascade_spec.rb` | Create | Request spec proving the attribute+style are emitted on workspace routes and absent elsewhere |
| `app/docs/ui-patterns.md` | Modify | Add "Workspace branding" subsection under Design Token Architecture |
| `docs/superpowers/specs/2026-04-24-workspace-branding-cascade-design.md` | Already created | Design spec (already on disk, will be committed with Task 1) |
| `docs/superpowers/plans/2026-04-24-workspace-branding-cascade.md` | Already created | This plan (will be committed at end) |

Three files touched (layout, spec, docs). Two docs already on disk, to commit alongside implementation.

---

## Task 1 — Request spec: attribute emission (TDD red + green)

**Files:**

- Create: `spec/requests/workspaces/branding_cascade_spec.rb`

- [ ] **Step 1.1: Create the request spec file**

Write `spec/requests/workspaces/branding_cascade_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Workspace branding cascade", type: :request do
  let(:user) { create(:user) }
  let!(:owner_role) { Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" } }

  describe "on workspace-scoped routes" do
    let(:workspace) { create(:workspace, primary_color: 270) }
    let!(:membership) { create(:membership, user: user, workspace: workspace, role: owner_role) }

    before { sign_in(user) }

    it "emits data-workspace-branded on <main>" do
      get workspace_path(workspace)
      expect(response.body).to match(/<main[^>]+data-workspace-branded/)
    end

    it "emits --ws-primary using the workspace's primary_color hue" do
      get workspace_path(workspace)
      expect(response.body).to include("--ws-primary: oklch(0.40 0.15 270)")
    end

    it "falls back to hue 210 when primary_color is nil" do
      workspace.update!(primary_color: nil)
      get workspace_path(workspace)
      expect(response.body).to include("--ws-primary: oklch(0.40 0.15 210)")
    end
  end

  describe "on non-workspace routes" do
    it "does not emit data-workspace-branded on the home page" do
      get root_path
      expect(response.body).not_to include("data-workspace-branded")
    end

    it "does not emit data-workspace-branded on the home page when signed in" do
      sign_in(user)
      get root_path
      expect(response.body).not_to include("data-workspace-branded")
    end
  end
end
```

- [ ] **Step 1.2: Run the spec to verify it fails**

Run: `mise exec -- bundle exec rspec spec/requests/workspaces/branding_cascade_spec.rb 2>&1 | tail -20`

Expected: 5 failures. The "does not emit" tests may PASS (current layout never emits the attribute), but the 3 "emits" tests will fail because the layout never renders `data-workspace-branded` today. Concrete expected messages: `expected "..." to match /<main[^>]+data-workspace-branded/`.

This confirms the test exercises the behavior we're about to add.

- [ ] **Step 1.3: Modify the layout to emit the attribute**

Open `app/views/layouts/application.html.erb`. Find this block (currently around lines 29–36):

```erb
    <%# Workspace branding (--ws-primary theming buttons/links/focus rings) is planned
        but not yet implemented. When ready, set data-workspace-branded and --ws-primary
        here based on a dedicated brand_color column. For now, primary_color only affects
        the workspace icon/initials circle background via workspace_helper. %>
    <main id="main-content" tabindex="-1" class="flex-1">
      <%= yield %>
    </main>
```

Replace the entire block (including the comment) with:

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

Note: keep the `<%= yield %>` inside `<main>` exactly as before. The only changes are (a) remove the 4-line comment, (b) add the conditional ERB block before the closing `>` of the opening tag.

- [ ] **Step 1.4: Run the spec to verify it passes**

Run: `mise exec -- bundle exec rspec spec/requests/workspaces/branding_cascade_spec.rb 2>&1 | tail -10`

Expected: `5 examples, 0 failures`.

- [ ] **Step 1.5: Run the full test suite for regressions**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: `1028 examples, 0 failures` (5 new examples added from Task 1; prior total was 1028 inclusive of new auth-guards tests — should rise to 1033).

If any unrelated test fails, stop and investigate — a layout change can surface unexpected HTML-matching assertions elsewhere.

- [ ] **Step 1.6: Commit**

```bash
git add app/views/layouts/application.html.erb spec/requests/workspaces/branding_cascade_spec.rb
git commit -m "feat: emit --ws-primary on <main> for workspace branding cascade"
```

---

## Task 2 — Documentation addition

**Files:**

- Modify: `app/docs/ui-patterns.md`

- [ ] **Step 2.1: Add "Workspace branding" subsection**

Open `app/docs/ui-patterns.md`. Find the "Dark Mode" subsection at the end of "Design Token Architecture" (currently ends with a paragraph about class-based toggle). Append a new subsection immediately after it, before the "Form Builder" section.

Insert this content:

```markdown
### Workspace Branding

Workspace-scoped routes emit a `--ws-primary` CSS custom property and a
`data-workspace-branded` marker on `<main>`, activating a cascade that
recolors the interactive tokens for that workspace:

```erb
<main data-workspace-branded
      style="--ws-primary: oklch(0.40 0.15 <hue>);">
```

The cascade ([app/assets/tailwind/application.css](app/assets/tailwind/application.css) in the "Workspace Branding Override" block) remaps:

- `--color-interactive` ← `var(--ws-primary)`
- `--color-interactive-hover` ← `color-mix(in oklch, --ws-primary 80%, black)`
- `--color-interactive-focus` ← `var(--ws-primary)`
- `--color-interactive-subtle` ← `color-mix(in oklch, --ws-primary 10%, white)`

Dark-mode variants mix with white instead of black for appropriate contrast.

The `primary_color` column on `workspaces` is an integer OKLCH hue (0–360) with default `210` (the app's sky base). When the column matches the default, the cascade computes values identical to the untouched tokens — no visual change. Explicit hue changes light up immediately.
```

(Note the fenced code block has `erb` as its language.)

- [ ] **Step 2.2: Verify markdown lints clean**

Run: `mise exec -- bundle exec rake markdown:check 2>&1 | grep "app/docs/ui-patterns.md" || echo "clean"`

Expected: `clean` (no lint issues introduced for this file).

- [ ] **Step 2.3: Commit**

```bash
git add app/docs/ui-patterns.md
git commit -m "docs: document workspace branding cascade in ui-patterns"
```

---

## Task 3 — Final verification + commit design artifacts

**Files:**

- Commit only: `docs/superpowers/specs/2026-04-24-workspace-branding-cascade-design.md`
- Commit only: `docs/superpowers/plans/2026-04-24-workspace-branding-cascade.md`

- [ ] **Step 3.1: Manual dev-server sanity check (optional but recommended)**

1. Start the dev server: `mise exec -- bin/dev`
2. Sign in, navigate to a workspace (e.g., `/workspaces/<slug>`)
3. Inspect `<main>` in devtools. Confirm:
   - Attribute `data-workspace-branded` is present
   - Inline style `--ws-primary: oklch(0.40 0.15 <hue>);` is present (hue matches the workspace's primary_color)
4. Change the workspace's primary color via the branding UI. Reload.
5. Confirm the `--ws-primary` value updated; any primary-branded button (e.g., main CTA in the workspace) visibly recolors.
6. Navigate to `/` (home page). Confirm `<main>` does NOT carry `data-workspace-branded`.

If anything is off, stop and investigate.

- [ ] **Step 3.2: Run full test suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: 0 failures. Example count should be higher than previous (1028 → 1033 with 5 new examples from Task 1).

- [ ] **Step 3.3: Verify working tree status**

Run: `git status --short`

Expected: only the two untracked docs files:

```text
?? docs/superpowers/specs/2026-04-24-workspace-branding-cascade-design.md
?? docs/superpowers/plans/2026-04-24-workspace-branding-cascade.md
```

- [ ] **Step 3.4: Commit the design doc and plan**

```bash
git add docs/superpowers/specs/2026-04-24-workspace-branding-cascade-design.md \
        docs/superpowers/plans/2026-04-24-workspace-branding-cascade.md
git commit -m "docs: workspace branding cascade spec and implementation plan"
```

- [ ] **Step 3.5: Review commit history on this branch**

Run: `git log --oneline $(git merge-base HEAD main)..HEAD`

Expected: 3 commits in this order (newest last):

```text
feat: emit --ws-primary on <main> for workspace branding cascade
docs: document workspace branding cascade in ui-patterns
docs: workspace branding cascade spec and implementation plan
```

---

## Deferred (post-merge, with triggers)

| Item | Trigger |
| ---- | ------- |
| Drop `projects.primary_color` orphan column | Task B discussion (separate) |
| OKLCH color-strategy unification per [project_oklch_color_unification.md](~/.claude/projects/-Users-dschmura-Documents-code-modelrails-base/memory/project_oklch_color_unification.md) | When user-vs-workspace color semantics diverge or a new consumer needs the unified representation |
| Visual verification via screenshot testing | If a branded-button regression is ever reported |

## Open Questions

None. All scope, behavior, and edge cases decided during brainstorming.
