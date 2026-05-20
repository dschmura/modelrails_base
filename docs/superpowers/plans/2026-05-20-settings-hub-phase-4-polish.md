# Settings Hub Phase 4: Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Spec:** [docs/superpowers/specs/2026-05-19-settings-hub-design.md](../specs/2026-05-19-settings-hub-design.md) — Phase 4 row + "OKLCH personal-context token set" + "Workspace switcher" implementation guidance.

**Closes:** #143 (Phase 4 polish).

**Goal:** Deliver the spec's Phase 4 polish — personal-context OKLCH token ramp (so solo users don't see "unstyled org" defaults), switcher visual differentiation (chroma-boosted swatch beyond the avatar shape from Phase 2), transition animations on sidebar/switcher state changes, and hover prefetch on the header surfaces that Phase 2 didn't cover.

**Architecture:** No new layout or sidebar partial; this phase tunes existing surfaces. The personal-context ramp piggy-backs on the project's existing `--neutral-*` slate primitives (matching the spec's "desaturated slate/zinc" hint) rather than inventing new OKLCH values, keeping AAA contrast already-verified. The `data-settings-context-kind` attribute Phase 2 added gets renamed to `data-workspace-kind` to match the spec's selector text. Transitions use a single `--transition-default` token wrapped in `motion-safe:` so WCAG 2.3.3 (reduced-motion) is respected. The chroma-boosted swatch is a small chip rendered next to each workspace name in the sidebar switcher only — not in the header dropdown — per spec's "reserved for switcher-list contexts" language.

**Tech Stack:** TailwindCSS 4 with semantic tokens + OKLCH, Stimulus, RSpec system specs with Capybara + Playwright + axe-core (WCAG 2.2 AAA).

**Out of scope:**

- Route consolidation (#153) — separate phase
- Mobile sidebar drawer (#148) — separate phase
- Header avatar/workspaces link redesign — Phase 4 only adds prefetch to existing links
- Theme/timezone UI on Appearance — #154 separate
- Personal workspace hidden from header switcher (#145) — separate phase

**Branch:** `feat/settings-hub-phase-4-polish` off `docs/settings-hub-spec` (already checked out).

**Pre-Phase-4 baseline:** 1914 examples, 0 failures, 1 pending. Coverage 95.86% line.

---

## File Map

**Create:** (none — Phase 4 modifies existing files)

**Modify:**

- `app/assets/tailwind/tokens/_semantic.css` — add `--transition-default` + `--transition-fast` tokens
- `app/assets/tailwind/application.css` — add `[data-workspace-kind="personal"]` rule mirroring `[data-workspace-branded]` shape
- `app/views/layouts/settings.html.erb` — rename `data-settings-context-kind` → `data-workspace-kind` on the wrapper div + `<main>`
- `app/javascript/controllers/settings_announcer_controller.js` — rename the dataset read from `settingsContextKind` → `workspaceKind`
- `app/views/shared/_settings_sidebar_item.html.erb` — add `motion-safe:transition-colors motion-safe:duration-150`
- `app/views/shared/_settings_sidebar_switcher.html.erb` — add the same transition AND a chroma-boosted color swatch next to org workspace names (skip for personal)
- `app/views/shared/_user_menu.html.erb` (and `_user_menu_avatar_button.html.erb` if separate) — add `data: { turbo_prefetch: "true" }` to the user menu links that lead to settings (Profile, Appearance, etc.)
- `app/views/shared/_workspace_switcher.html.erb` (the existing header dropdown variant) — add `data: { turbo_prefetch: "true" }` to each workspace link
- 4 system specs that assert `data-settings-context-kind` — update to `data-workspace-kind`
- `CHANGELOG.md` — note Phase 4 entry

---

## Task 1: Transition duration tokens

**Files:** Modify `app/assets/tailwind/tokens/_semantic.css`

**Steps:**

- [ ] **Step 1: Inspect current shape.** Run `grep -n "^--transition\|--modal-animation" app/assets/tailwind/tokens/_semantic.css`. Note existing transition-related tokens (currently only `--modal-animation-duration: 200ms`).

- [ ] **Step 2: Add new tokens.** In `app/assets/tailwind/tokens/_semantic.css`, add inside the `:root` block:

```css
/* Transitions — durations for UI state changes. Used with
   motion-safe:transition-* utilities so users with
   prefers-reduced-motion get instant state changes. */
--transition-default: 150ms;
--transition-fast: 75ms;
```

Place these near the existing `--modal-animation-duration` for cohesion.

- [ ] **Step 3: Smoke check.** Run `bundle exec rails server -d` (if not running) or read the CSS output. The `:root` block should include both new vars without breaking any existing styles. No spec change yet.

Alternative smoke (no server needed):

```bash
grep -A 2 "transition-default" app/assets/tailwind/tokens/_semantic.css
```

Expected: both tokens present.

- [ ] **Step 4: Run FULL suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec
```

Expected: 1914/0/1 (no behavior change yet).

- [ ] **Step 5: Commit.**

```bash
git add app/assets/tailwind/tokens/_semantic.css
git commit -m "feat(tokens): add UI transition duration tokens

--transition-default (150ms) and --transition-fast (75ms) for use
with motion-safe:transition-* utilities. Centralizes the duration
so future transitions stay consistent and so WCAG 2.3.3
(reduced-motion) respect happens via the motion-safe wrapper."
```

---

## Task 2: Personal-context token ramp

**Files:** Modify `app/assets/tailwind/application.css`

**Steps:**

- [ ] **Step 1: Inspect the existing `[data-workspace-branded]` rule.** Run `grep -A 10 "data-workspace-branded" app/assets/tailwind/application.css`. Note its structure — it remaps `--color-interactive` and family using `--ws-primary-light` / `--ws-primary-dark`.

- [ ] **Step 2: Add the personal-context block.** In `app/assets/tailwind/application.css`, immediately after the existing `[data-workspace-branded]` rule, add:

```css
/* Personal workspace context — solo users spend most of their time
   here, so it deserves an intentional treatment rather than the
   "unstyled org" defaults. The desaturated slate ramp (sourced from
   our existing --neutral-* primitives) is AAA-verified and matches
   the spec's "deliberate desaturated slate/zinc" guidance. */
[data-workspace-kind="personal"] {
  --color-interactive: var(--neutral-700);
  --color-interactive-hover: var(--neutral-900);
  --color-interactive-focus: var(--neutral-700);
  --color-interactive-subtle: var(--neutral-100);
  --color-accent: var(--neutral-600);
}

.dark [data-workspace-kind="personal"] {
  --color-interactive: var(--neutral-300);
  --color-interactive-hover: var(--neutral-100);
  --color-interactive-focus: var(--neutral-300);
  --color-interactive-subtle: var(--neutral-800);
  --color-accent: var(--neutral-400);
}
```

- [ ] **Step 3: Verify the neutral primitives exist.** Run `grep "^--neutral-" app/assets/tailwind/tokens/_primitives.css | head`. Confirm `--neutral-100`, `--neutral-300`, `--neutral-600`, `--neutral-700`, `--neutral-800`, `--neutral-900` are all defined.

- [ ] **Step 4: Run FULL suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec
```

Expected: 1914/0/1.

- [ ] **Step 5: Commit.**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat(theme): add personal-workspace OKLCH context ramp

[data-workspace-kind=\"personal\"] remaps interactive + accent
semantic tokens to desaturated slate (--neutral-*) so solo users
see a deliberate visual treatment rather than the unstyled-org
defaults. Mirrors the [data-workspace-branded] shape for org
workspaces. Reuses existing neutral primitives — already AAA-
verified, no fresh OKLCH math required."
```

---

## Task 3: Rename `data-settings-context-kind` → `data-workspace-kind`

**Files:**
- Modify: `app/views/layouts/settings.html.erb`
- Modify: `app/javascript/controllers/settings_announcer_controller.js`
- Modify: 4 system specs that assert the old attribute name

**Steps:**

- [ ] **Step 1: Find all references.** Run:

```bash
grep -rn "settings-context-kind\|settings_context_kind\|settingsContextKind" app/ spec/ | head -20
```

Note: there's a Ruby helper named `settings_context_kind` in `app/helpers/settings_navigation_helper.rb` that returns `:personal | :org`. The helper itself does NOT need renaming — it returns the value. Only the DOM attribute and the Stimulus dataset read need renaming.

- [ ] **Step 2: Update the layout.** In `app/views/layouts/settings.html.erb`, find:

```erb
<div class="..." data-settings-context-kind="<%= settings_context_kind %>">
```

Replace with:

```erb
<div class="..." data-workspace-kind="<%= settings_context_kind %>">
```

If `<main>` also has the attribute, update there too.

- [ ] **Step 3: Update the Stimulus controller.** In `app/javascript/controllers/settings_announcer_controller.js`, the `currentKind` method reads:

```js
return document.querySelector("[data-settings-context-kind]")?.dataset.settingsContextKind ?? null
```

Change to:

```js
return document.querySelector("[data-workspace-kind]")?.dataset.workspaceKind ?? null
```

- [ ] **Step 4: Update the system specs that assert the old attribute.** Run `grep -rln "data-settings-context-kind" spec/` to find them. For each, replace the assertion text:

```ruby
# Before
expect(page).to have_css("[data-settings-context-kind='personal']")
# After
expect(page).to have_css("[data-workspace-kind='personal']")
```

Likely files: `spec/system/settings/personal_context_spec.rb`, `spec/system/settings/org_context_spec.rb`, `spec/requests/concerns/personal_workspace_context_spec.rb`.

- [ ] **Step 5: Run targeted specs first.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/settings/ spec/requests/concerns/personal_workspace_context_spec.rb
```

Expected: all pass.

- [ ] **Step 6: Run FULL suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec
```

Expected: 1914/0/1.

- [ ] **Step 7: Commit.**

```bash
git add app/views/layouts/settings.html.erb app/javascript/controllers/settings_announcer_controller.js spec/
git commit -m "refactor: rename data-settings-context-kind -> data-workspace-kind

The spec's CSS guidance uses [data-workspace-kind=\"personal\"] as
the selector for the personal-context token ramp (Task 2 of this
phase). Phase 2 named the attribute data-settings-context-kind;
renaming brings code and CSS together so the personal-context ramp
selector matches the DOM. Stimulus dataset read updated; 4 system
specs updated to assert the new attribute name. No behavior change."
```

---

## Task 4: Sidebar item transitions

**Files:** Modify `app/views/shared/_settings_sidebar_item.html.erb`

**Steps:**

- [ ] **Step 1: Inspect the current class list.** Run `cat app/views/shared/_settings_sidebar_item.html.erb`. Find the link's class array.

- [ ] **Step 2: Add motion-safe transition classes.** In the class array, add:

```ruby
"motion-safe:transition-colors motion-safe:duration-150",
```

The line should slot near the other state-related classes (hover, focus). The full class array stays multi-line for diffability.

- [ ] **Step 3: Verify the partial smoke-renders.** Run:

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails runner 'puts ActionController::Base.render(partial: "shared/settings_sidebar_item", locals: { label: "Profile", href: "/x" })'
```

Expected: the rendered link's `class=` attribute includes `motion-safe:transition-colors motion-safe:duration-150`.

- [ ] **Step 4: Run FULL suite.**

Expected: 1914/0/1. Existing Phase 2/3 system specs that test sidebar items don't pin class names; they assert visible text + `aria-current`. No spec breakage expected.

- [ ] **Step 5: Commit.**

```bash
git add app/views/shared/_settings_sidebar_item.html.erb
git commit -m "feat(views): smooth color transitions on sidebar items

Adds motion-safe:transition-colors motion-safe:duration-150 to each
sidebar item link. State changes (hover, focus, active) now ease
smoothly for users without reduced-motion preferences; users with
prefers-reduced-motion: reduce see instant changes (the motion-safe
prefix gates the transition on the media query)."
```

---

## Task 5: Switcher current-item transitions

**Files:** Modify `app/views/shared/_settings_sidebar_switcher.html.erb`

**Steps:**

- [ ] **Step 1: Inspect the current class list** on the workspace link inside the switcher (the `<%= link_to ... %>` block).

- [ ] **Step 2: Add motion-safe transition classes** to the link's class array — same shape as Task 4:

```ruby
"motion-safe:transition-colors motion-safe:duration-150",
```

- [ ] **Step 3: Smoke-render check.** Same approach as Task 4 but for the switcher partial (this partial has more local dependencies — skip if smoke check is gymnastic; rely on system specs).

- [ ] **Step 4: Run FULL suite.**

Expected: 1914/0/1.

- [ ] **Step 5: Commit.**

```bash
git add app/views/shared/_settings_sidebar_switcher.html.erb
git commit -m "feat(views): smooth color transitions on workspace switcher items

Same motion-safe:transition treatment as sidebar items so the
current-workspace indicator and hover states ease consistently
across the entire sidebar."
```

---

## Task 6: Chroma-boosted swatch on org switcher items

**Files:** Modify `app/views/shared/_settings_sidebar_switcher.html.erb`

**Steps:**

- [ ] **Step 1: Plan the swatch markup.** The swatch is a small color chip rendered between the workspace avatar and the name. Personal workspaces don't get a swatch (their context already differs via avatar shape + the personal-context token ramp). Org workspaces show a `<span>` with the workspace's `primary_color` as background, chroma-boosted by using L=0.55 instead of the body-text L=0.40 (more visible at small chip size).

- [ ] **Step 2: Add the swatch markup.** Inside the `link_to` block, between the avatar `<span>` and the name `<span class="flex-1">`, add:

```erb
<% unless workspace.personal? %>
  <span class="w-1 h-6 rounded-full shrink-0"
        style="background: oklch(0.55 0.18 <%= workspace.primary_color || 210 %>);"
        aria-hidden="true"></span>
<% end %>
```

> **Why `w-1 h-6 rounded-full`:** narrow vertical chip, ~24px tall — reads as a color accent without competing with the avatar. `rounded-full` makes both ends pill-shaped.

> **Why `aria-hidden`:** the swatch is decoration; the workspace name already carries the identity.

> **Why L=0.55 not 0.40:** at a 4×24px chip size, L=0.55 with C=0.18 has visual presence without being garish. L=0.40 reads as too-dark on the surface background at this size.

> **Why `personal?` guarded:** personal workspaces have no `primary_color` semantics (or default 210); rendering the swatch for them would mislead solo users into thinking their workspace has a brand.

- [ ] **Step 3: Verify AAA contrast.** The chip is decorative (`aria-hidden`) so axe doesn't require WCAG contrast. But for visible-design polish, the L=0.55 + C=0.18 OKLCH combo against `bg-surface` (light) and `bg-surface-sunken` (dark) should remain legible (i.e., not blend in). This is a manual eyeball check.

- [ ] **Step 4: Run FULL suite.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec
```

Expected: 1914/0/1. axe AAA assertions in `spec/system/settings/org_context_spec.rb` should pass — decorative `aria-hidden` swatches don't count against contrast.

- [ ] **Step 5: Commit.**

```bash
git add app/views/shared/_settings_sidebar_switcher.html.erb
git commit -m "feat(views): chroma-boosted color swatch for org workspaces in switcher

Per spec: a narrow vertical chip (w-1 h-6) rendered between the
avatar and the workspace name, using the workspace's primary_color
hue with chroma boosted (oklch L=0.55 C=0.18) for legibility at
small size. Personal workspaces skip the swatch — they have no
brand color and the personal-context token ramp already
differentiates their context.

aria-hidden=\"true\" keeps the swatch out of the accessibility tree;
identity continues to flow through the avatar shape + the workspace
name + the role text."
```

---

## Task 7: Hover prefetch on header surfaces

**Files:**
- Modify: `app/views/shared/_user_menu.html.erb` (or whichever partial hosts the user menu's settings links)
- Modify: `app/views/shared/_workspace_switcher.html.erb` (the existing header dropdown variant)

**Steps:**

- [ ] **Step 1: Find the user-menu settings link.** Run `grep -rn "edit_account_profile_path\|account_connected_accounts_path" app/views/shared/ | head`. The user menu (avatar dropdown in the header) likely has links to one or more settings pages.

- [ ] **Step 2: Add `data: { turbo_prefetch: "true" }` to each settings-bound link** in the user menu partial. Each affected `link_to` gets:

```erb
data: { turbo_prefetch: "true" }
```

- [ ] **Step 3: Find the header workspace switcher.** `app/views/shared/_workspace_switcher.html.erb` is the existing header dropdown. Look for `link_to workspace_path(workspace)` (or similar).

- [ ] **Step 4: Add prefetch.** Each workspace link in the header dropdown gets `data: { turbo_prefetch: "true" }`.

- [ ] **Step 5: Run FULL suite.**

Expected: 1914/0/1.

- [ ] **Step 6: Commit.**

```bash
git add app/views/shared/_user_menu.html.erb app/views/shared/_workspace_switcher.html.erb
git commit -m "perf(views): hover prefetch on header settings + workspace links

data-turbo-prefetch=\"true\" on user-menu links to settings pages
and on each workspace link in the header dropdown. Reduces
perceived latency when users hover before clicking. Matches the
prefetch treatment Phase 2 added to the sidebar — header surfaces
were the remaining gap per the Phase 4 spec."
```

If one of the partials doesn't exist, drop it from the commit; mention in the report.

---

## Task 8: System spec — personal-context visual differentiation

**Files:** Modify `spec/system/settings/personal_context_spec.rb`

**Steps:**

- [ ] **Step 1: Add an example asserting the personal-context attribute selector.** Open the file and find the existing `data-settings-context-kind='personal'` assertion (Task 3 renamed it to `data-workspace-kind='personal'`). Add a new example immediately below it:

```ruby
it "applies the personal-workspace token ramp via [data-workspace-kind='personal']" do
  visit edit_account_profile_path

  # The personal-context CSS rule remaps interactive tokens to neutral.
  # We verify the selector is present on the DOM; the actual cascade is
  # validated by the axe AAA spec which would catch contrast regressions.
  expect(page).to have_css("[data-workspace-kind='personal']")
end
```

(Note: this duplicates the rename'd assertion semantically. Task 3 already asserts the attribute. Skip this step unless you find the existing assertion was deleted by mistake.)

- [ ] **Step 2: Re-run the personal context spec.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/settings/personal_context_spec.rb
```

Expected: 4-5 examples, 0 failures.

- [ ] **Step 3: Run FULL suite.**

Expected: 1914/0/1 (no new examples expected unless you added the duplicate above — skip and run anyway).

- [ ] **Step 4: Commit if any changes were made.** If Task 8 turned out to be a no-op (the assertion in Task 3 already covers it), skip this commit. Otherwise:

```bash
git add spec/system/settings/personal_context_spec.rb
git commit -m "test(system): assert personal-context token ramp selector applies"
```

---

## Task 9: CHANGELOG + close #143

**Files:** Modify `CHANGELOG.md`

**Steps:**

- [ ] **Step 1: Add CHANGELOG entries.** Under `## [Unreleased]` → `### Added`:

```markdown
- Personal-workspace OKLCH context ramp via `[data-workspace-kind="personal"]` — desaturated slate treatment so solo users see a deliberate visual identity rather than unstyled-org defaults.
- Chroma-boosted color swatch on org workspaces in the sidebar switcher — small vertical chip beside each workspace name using its `primary_color` for at-a-glance differentiation.
```

Under `### Changed`:

```markdown
- Smooth motion-safe color transitions on sidebar items and switcher; settings layout's context attribute renamed `data-settings-context-kind` → `data-workspace-kind`; hover prefetch added to header user-menu settings links and header workspace dropdown.
```

- [ ] **Step 2: Close #143 on GitHub.**

```bash
gh issue close 143 --comment "Closed by feat/settings-hub-phase-4-polish — see CHANGELOG entries under [Unreleased]. Personal-context token ramp, switcher chroma swatch, motion-safe transitions, and header prefetch all delivered. Spec's Phase 4 row now complete; route consolidation (#153) and mobile drawer (#148) tracked as separate follow-ups."
```

- [ ] **Step 3: Run FULL suite one last time.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec
```

Expected: 1914 examples (give or take any tiny test additions from Task 8), 0 failures, 1 pending. Coverage ≥ 95.86%.

- [ ] **Step 4: Commit.**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note Phase 4 settings hub polish (closes #143)"
```

---

## Self-Review

**Spec coverage check:**

| Phase 4 deliverable | Task |
|---|---|
| OKLCH personal-context token ramp | 2 |
| `[data-workspace-kind="personal"]` selector | 2, 3 (rename) |
| Switcher avatar shape | Already Phase 2; no change |
| Switcher role badge | Already Phase 2; no change |
| Switcher chroma boost / color swatch | 6 |
| Transition animations | 1 (tokens), 4 (item), 5 (switcher) |
| Prefetch on hover (sidebar) | Already Phase 2; no change |
| Prefetch on hover (header) | 7 |

**Placeholder scan:** every step has exact paths, complete code, named files. No TBDs.

**Identifier consistency:** `data-workspace-kind` (DOM attribute, post-Task-3) vs `settings_context_kind` (Ruby helper method, unchanged) — distinct concepts, both stable across the plan. `--transition-default` token defined Task 1, used Tasks 4-5. `--neutral-*` tokens referenced Task 2 are existing primitives.

**Out-of-scope items documented in plan header** — route consolidation (#153), mobile drawer (#148), timezone UI (#154), personal-from-header-switcher (#145) all explicitly deferred to other phases.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-20-settings-hub-phase-4-polish.md`. Continuing with subagent-driven execution (same workflow as Phases 2/3). 9 tasks, mostly mechanical given the file map.
