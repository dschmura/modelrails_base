# Path Z — Mobile Header-Accordion (Drawer Replacement)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Supersedes:** #148 (Settings hub: mobile drawer pattern). Drawer shipped 2026-05-20 in commits `17d6849`, `4d59b5e`, `8c9e2d9`, `126608d`, `781007d`; this plan retires it and replaces it with the agent_os-style header-accordion pattern after a unanimous panel review (Fried, Schoger, Wathan, AAA specialist, Metz).

**Goal:** Replace the off-canvas mobile drawer (currently mounted in `settings.html.erb` and `application.html.erb`) with a header-accordion pattern modeled on `~/Documents/code/modelrails_agent_os`. On mobile (below `md`), the header expands *downward* to reveal the appropriate sidebar's contents inline — no overlay scrim, no focus trap, no slide animation, no modal dialog ARIA. Desktop (`md`+) is unchanged: sidebar stays in-flow to the left of `<main>`.

**Why:** The drawer pattern was the structural cause of the dropdown-over-dropdown mobile conflict the panel flagged in Path Y. Eliminating the drawer eliminates the conflict class. One navigation paradigm across breakpoints, ~120 lines of Stimulus deleted, fewer aria-modal surfaces, identical AAA coverage, and visual continuity enforced by partial reuse (the same `_settings_sidebar` / `_workspace_sidebar` partials render in both desktop columns and the mobile header accordion).

**Architecture:**
- **Single Stimulus controller for mobile nav:** the existing `mobile-menu` controller (already mounted on `shared/_header.html.erb` line 2). Extended with one new method: `closeOnLinkClick` so navigation through the accordion auto-dismisses the panel.
- **Content delegation via `content_for`:** each layout that has a sidebar provides `content_for :mobile_menu_sidebar` containing the rendered sidebar partial. The header reads that slot and renders it inside its mobile-menu accordion. Layouts that don't have a sidebar (auth pages, marketing pages, registration) inject nothing; the accordion shows the existing header's nav links + user menu only.
- **Desktop unchanged.** Sidebar partials still render in their in-flow column on `md`+.

**Tech stack:** Stimulus, TailwindCSS 4 utilities (`hidden md:block`, `md:hidden`), RSpec system specs with Capybara + Playwright at iPhone-SE viewport (375×667), axe-core WCAG 2.2 AAA both themes both states.

**Out of scope:**
- Replacing the desktop sidebar pattern itself — desktop stays as today.
- Reworking the workspace switcher partial — `_settings_sidebar_switcher.html.erb` is unchanged.
- Mobile-menu animation polish (chevron rotation, slide transitions). Path Y left chevron rotation on the table; Path Z does not reopen it.
- The header's *user-avatar* dropdown — that's its own dropdown controller on desktop, and it gets folded into the accordion contents on mobile via the existing header structure. Not Path Z scope to refactor it.

**Branch:** `feat/path-z-mobile-accordion` off `docs/settings-hub-spec`.

**Pre-task baseline:** 1894 examples, 0 failures, 0 pending. Coverage 94.77% line, 80.65% branch. (Verified after Path Y Phase C merged: `f4d92fc`.)

**Definition of done:**
1. `settings.html.erb` and `application.html.erb` no longer reference `data-controller="settings-drawer"`, no overlay element, no slide-from-left panel.
2. `app/javascript/controllers/settings_drawer_controller.js` deleted.
3. `spec/system/settings/mobile_drawer_spec.rb` deleted (superseded).
4. New specs: `spec/system/settings/mobile_accordion_spec.rb` and `spec/system/workspaces/mobile_accordion_spec.rb` — same 4-it coverage profile (hamburger visible, open on click, auto-close on link, axe AAA both states both themes).
5. `settings.mobile_drawer.*` and `workspaces.mobile_drawer.*` locale keys removed; replaced by a single shared `navigation.mobile_menu.*` namespace (or repurposed via the existing `navigation.toggle_menu`).
6. Full suite green at 1894 (or new count if accordion specs added at 2 each).
7. Manual browser verification at 375×667 (iPhone SE), 768×1024 (iPad), 1280×800 (desktop) in both themes.
8. CHANGELOG: drawer entry marked superseded, new accordion entry under Changed.

---

## File Map

**Delete:**
- `app/javascript/controllers/settings_drawer_controller.js` (~120 lines)
- `spec/system/settings/mobile_drawer_spec.rb` (~57 lines)

**Create:**
- `spec/system/settings/mobile_accordion_spec.rb` — settings-hub layout coverage (parallel to drawer spec)
- `spec/system/workspaces/mobile_accordion_spec.rb` — application layout (workspace-scoped pages) coverage

**Modify:**
- `app/javascript/controllers/mobile_menu_controller.js` — add `closeOnLinkClick` action
- `app/views/shared/_header.html.erb` — render `content_for(:mobile_menu_sidebar)` slot inside the existing mobile-menu panel, wire the new action
- `app/views/layouts/settings.html.erb` — remove drawer wrapper (toggle + overlay + aside drawer), make sidebar `hidden md:flex`, provide `content_for(:mobile_menu_sidebar)` with the settings sidebar
- `app/views/layouts/application.html.erb` — same pattern: remove drawer wrapper, sidebar desktop-only, provide `content_for(:mobile_menu_sidebar)` with the workspace sidebar
- `config/locales/en/settings.en.yml` — remove `settings.mobile_drawer.*` keys
- `config/locales/en/workspaces.en.yml` — remove `workspaces.mobile_drawer.*` keys
- `config/locales/en/application.en.yml` — add `navigation.mobile_menu.open` / `navigation.mobile_menu.close` / `navigation.mobile_menu.aria_label` (or repurpose existing `navigation.toggle_menu`)
- `CHANGELOG.md` — supersede note + Changed entry

---

## Task 1: Extend `mobile-menu` controller with auto-dismiss-on-link-click

**Why first:** Pure additive change to an existing controller. No layouts touched yet. Tested in isolation by the header's existing mobile menu (header has a `mobile-menu-target="menu"` panel today with workspace + user links inside). The behavior is a latent UX bug fix that the accordion pattern depends on.

**Files:** Modify `app/javascript/controllers/mobile_menu_controller.js`.

**Steps:**

- [ ] **Step 1: Failing spec.** Write a system spec at 375×667 that authenticates a user, taps the hamburger in `_header.html.erb`, clicks any link inside the expanded panel, and asserts the panel is hidden after navigation completes. Location: `spec/system/shared/header_mobile_menu_spec.rb`. Title: "auto-closes when a link inside the panel is clicked." Run with `mise exec -- bundle exec rspec spec/system/shared/header_mobile_menu_spec.rb` and verify it FAILS for the right reason (panel still visible / aria-expanded still true after nav).

- [ ] **Step 2: Add the action.** Append `closeOnLinkClick` to the controller:

```javascript
closeOnLinkClick(event) {
  if (event.target.closest("a") && !this.menuTarget.classList.contains("hidden")) {
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }
}
```

The action is wired at the partial level in Task 3 via `data-action="click->mobile-menu#closeOnLinkClick"` on the menu element. (Wiring it in Task 1 would orphan the action — postpone to header partial work in Task 3.)

- [ ] **Step 3: Run targeted spec.** Expected: still FAILS — wiring is in Task 3. Mark spec as `pending: "wiring in Task 3"` to keep the suite green between tasks. **Do not delete the failing assertion.**

- [ ] **Step 4: Run FULL suite.** Expected: 1894/0/1 pending.

- [ ] **Step 5: Commit.**

```bash
git add app/javascript/controllers/mobile_menu_controller.js spec/system/shared/header_mobile_menu_spec.rb
git commit -m "feat(stimulus): mobile-menu closeOnLinkClick action (Path Z prep)

Adds a closeOnLinkClick action that hides the menu panel and resets
aria-expanded when any anchor inside the panel is clicked. Wiring
lands in Task 3 when the header partial migrates to the accordion
pattern; this commit only adds the controller method so the layout
changes have a stable hook to use.

Pending spec records the wiring expectation."
```

---

## Task 2: Failing accordion specs (settings + workspace)

**Why now:** TDD discipline — describe the target behavior in tests before changing the layouts. Both specs fail today (drawer still exists), pass after Tasks 3 and 4.

**Files:** Create `spec/system/settings/mobile_accordion_spec.rb` and `spec/system/workspaces/mobile_accordion_spec.rb`.

### Settings accordion spec

- [ ] **Step 1: Author the spec.** Mirror the drawer spec's coverage profile — hamburger visible at 375px, opens on tap (assert `aria-expanded="true"` on the header toggle, panel `hidden` class removed), navigation closes the panel, axe AAA both themes both states. Critical difference: assertions target the header's `mobile-menu-target="menu"` panel, NOT a separate drawer panel. No `[data-drawer-state]` selectors. No `role="dialog"`. No `aria-modal`. Use `have_button(I18n.t("navigation.mobile_menu.open"))` for the toggle (key landed in Task 5).

```ruby
# spec/system/settings/mobile_accordion_spec.rb
require "rails_helper"

# Mobile-viewport behavior for the settings-hub header accordion (below md).
# Replaces the off-canvas drawer pattern: the header expands downward to
# reveal the same _settings_sidebar partial inline. No modal context.
RSpec.describe "Settings hub — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: ["wcag2aaa"] } } }

  before do
    sign_in_via_form(user)
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
  end

  it "shows the hamburger toggle below md" do
    visit edit_account_profile_path
    expect(page).to have_button(I18n.t("navigation.mobile_menu.open"))
  end

  it "opens the accordion when the hamburger is tapped" do
    visit edit_account_profile_path
    click_button I18n.t("navigation.mobile_menu.open")
    expect(page.find("[data-mobile-menu-target='button']"))
      .to match_selector("[aria-expanded='true']")
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")
  end

  it "auto-closes the accordion when a sidebar link inside is tapped" do
    visit edit_account_profile_path
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      click_link I18n.t("settings.sidebar.items.notifications")
    end
    expect(page).to have_current_path(edit_account_notification_preferences_path)
    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden")
  end

  it "passes axe AAA both themes in both accordion states" do
    visit edit_account_profile_path

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (collapsed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("navigation.mobile_menu.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (expanded):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
```

### Workspace accordion spec

- [ ] **Step 2: Author the workspace spec.** Same shape, but visits `workspace_members_path(workspace)` and asserts the workspace sidebar items appear in the panel. Owner membership required for Members link.

```ruby
# spec/system/workspaces/mobile_accordion_spec.rb
require "rails_helper"

RSpec.describe "Workspace pages — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:axe_options) { { runOnly: { type: "tag", values: ["wcag2aaa"] } } }

  before do
    sign_in_via_form(user)
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
  end

  it "shows the hamburger and reveals the workspace sidebar on tap" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      expect(page).to have_link(I18n.t("workspaces.sidebar.items.overview"))
      expect(page).to have_link(I18n.t("workspaces.sidebar.items.settings"))
    end
  end

  it "auto-closes on link tap inside the panel" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      click_link I18n.t("workspaces.sidebar.items.settings")
    end
    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden")
  end

  it "passes axe AAA both themes both states" do
    visit workspace_path(workspace)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true)

    click_button I18n.t("navigation.mobile_menu.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true)
  end
end
```

- [ ] **Step 3: Run both new specs.** Expected: ALL fail (no accordion yet; locale keys don't exist yet). Failures should be for the *right* reasons: missing key, missing toggle, etc. — NOT syntax errors.

- [ ] **Step 4: Mark both as pending with reason.**

```ruby
# At top of each describe block:
pending "Path Z Task 5: locale keys + Task 3/4: layout migration"
```

This keeps the suite green between Task 2 and Task 5. The pending list becomes the punch list.

- [ ] **Step 5: Run FULL suite.** Expected: 1894/0/N pending (N = original pending + 7 new). Spec count rises.

- [ ] **Step 6: Commit.**

```bash
git add spec/system/settings/mobile_accordion_spec.rb spec/system/workspaces/mobile_accordion_spec.rb
git commit -m "test(system): failing accordion specs for settings + workspace layouts (Path Z)

Pending until Tasks 3-5 land the locale keys, header partial wiring,
and layout migrations. Covers the same surface area as the existing
mobile_drawer_spec: hamburger visibility, open-on-tap, auto-close on
internal link tap, axe AAA both themes both states. No modal ARIA
or drawer-state selectors — assertions target the standard
mobile-menu-target='menu' panel directly."
```

---

## Task 3: Header partial — accordion slot + wire closeOnLinkClick

**Files:** Modify `app/views/shared/_header.html.erb`.

**Steps:**

- [ ] **Step 1: Locate the mobile-menu panel** (currently around line 41 — `<div data-mobile-menu-target="menu" class="hidden md:hidden pb-4">`). This is where the new sidebar slot lands.

- [ ] **Step 2: Add `data-action="click->mobile-menu#closeOnLinkClick"` to the menu element** so anchor clicks inside auto-dismiss. The action delegates via event bubbling to any `<a>` descendant; no per-link wiring needed.

- [ ] **Step 3: Render the `content_for(:mobile_menu_sidebar)` slot** at the top of the panel, before the existing nav links. The slot shows when a layout provides it (settings or application-workspace context) and is invisible when nothing is injected:

```erb
<div data-mobile-menu-target="menu"
     data-action="click->mobile-menu#closeOnLinkClick"
     class="hidden md:hidden pb-4">
  <% if content_for?(:mobile_menu_sidebar) %>
    <div class="mb-3 pb-3 border-b border-border">
      <%= yield :mobile_menu_sidebar %>
    </div>
  <% end %>
  <%# ... existing header nav + user menu links remain below ... %>
</div>
```

- [ ] **Step 4: Update header toggle button labels.** Change the hamburger button's `aria-label` from `t("navigation.toggle_menu")` to the more specific open/close pair (added in Task 5). For now wire `t("navigation.toggle_menu")` as the placeholder; Task 5 swaps to the dedicated keys.

- [ ] **Step 5: Run accordion specs.** Expected: still pending (Tasks 4 + 5 remain). Don't un-pend yet.

- [ ] **Step 6: Run FULL suite.** Expected: 1894 + pending count unchanged, 0 failures. Existing header behavior unchanged because no layout injects the slot yet.

- [ ] **Step 7: Commit.**

```bash
git add app/views/shared/_header.html.erb
git commit -m "feat(views): mobile_menu_sidebar slot + auto-close wiring (Path Z)

Header mobile-menu panel now (a) renders content_for(:mobile_menu_sidebar)
inline above its standard nav links when a layout provides one, and
(b) auto-dismisses on any anchor-click via the new closeOnLinkClick
action. Layouts wire the slot in Tasks 4 and 5; with no layout
injecting yet, the header behaves identically to before."
```

---

## Task 4: Settings layout — drop drawer, inject sidebar via content_for

**Files:** Modify `app/views/layouts/settings.html.erb`.

**Steps:**

- [ ] **Step 1: Remove the drawer wrapper.** Delete lines 56-94 (the `data-controller="settings-drawer"` div, hamburger button, overlay, and aside-drawer panel). Replace with a desktop-only sidebar column:

```erb
<%# Desktop sidebar — hidden on mobile where the header accordion
    surfaces the same content. %>
<div class="hidden md:flex shrink-0">
  <%= render "shared/settings_sidebar",
        workspaces: Current.user.workspaces.kept.includes(:logo_attachment, memberships: [ :role, { user: :avatar_attachment } ]),
        current_workspace: Current.workspace %>
</div>
```

- [ ] **Step 2: Inject the same sidebar into the header accordion via `content_for`.** Top of `settings.html.erb`, before the `<!DOCTYPE>` is invalid Ruby; put it inside a `<% content_for :mobile_menu_sidebar do %> ... <% end %>` block after the `<head>` and before `<body>` opens (or anywhere in the layout body before `<%= render "shared/header" %>`):

```erb
<% content_for :mobile_menu_sidebar do %>
  <%= render "shared/settings_sidebar",
        workspaces: Current.user.workspaces.kept.includes(:logo_attachment, memberships: [ :role, { user: :avatar_attachment } ]),
        current_workspace: Current.workspace %>
<% end %>
```

Place it before `<%= render "shared/header" %>` so the slot is populated when the header renders.

- [ ] **Step 3: Verify N+1 protection.** Bullet is enabled in test env. The eager-loads on `Current.user.workspaces.kept.includes(...)` already prevent N+1 for the existing desktop render; sharing the same scope across both renders is intentional. **Do not** call the workspace scope twice with different `.includes` chains — define a local once and pass it to both renders if Rails fails to memoize:

```erb
<% workspaces_scope = Current.user.workspaces.kept.includes(:logo_attachment, memberships: [ :role, { user: :avatar_attachment } ]) %>
<% content_for :mobile_menu_sidebar do %>
  <%= render "shared/settings_sidebar", workspaces: workspaces_scope, current_workspace: Current.workspace %>
<% end %>
<%= render "shared/header" %>
<%# ... %>
<div class="hidden md:flex shrink-0">
  <%= render "shared/settings_sidebar", workspaces: workspaces_scope, current_workspace: Current.workspace %>
</div>
```

- [ ] **Step 4: Remove the comment block referencing the drawer** (lines 46-50 currently — `"Settings hub layout. The data-workspace-kind hook stays..."`). Update it to describe the accordion pattern.

- [ ] **Step 5: Un-pend `mobile_accordion_spec.rb` for settings.** Run it. Expected: still partially failing on locale keys (Task 5).

- [ ] **Step 6: Run FULL suite.** Expected: 1894 + new accordion examples; failures only on locale-key lookups. Drawer spec STILL passes (we haven't deleted it yet — its assertions are against drawer markup which is now gone… wait, that's a problem).

  **REVISED:** Delete `spec/system/settings/mobile_drawer_spec.rb` in this same task — it will fail otherwise because its assertions reference removed markup. If you delete here, also delete `settings_drawer_controller.js` (no consumer left in settings; application layout still has it until Task 5).

  Better ordering: keep the drawer controller and spec around until Task 6 deletes them. To avoid breaking the drawer spec in Task 4, mark it pending here with reason "superseded by mobile_accordion_spec; deleted in Task 6":

  ```ruby
  # At top of mobile_drawer_spec.rb describe block:
  pending "superseded by Path Z mobile_accordion_spec — deleted in Task 6"
  ```

- [ ] **Step 7: Commit.**

```bash
git add app/views/layouts/settings.html.erb spec/system/settings/mobile_drawer_spec.rb
git commit -m "refactor(layouts): settings.html.erb uses header accordion (Path Z)

Removes off-canvas drawer markup (toggle button, overlay, sliding
panel) in favor of: (a) desktop-only inline sidebar via hidden md:flex,
and (b) content_for(:mobile_menu_sidebar) that the header renders
inside its existing mobile-menu accordion. One workspaces scope
defined as a local var so both renders share the same eager-loaded
relation.

mobile_drawer_spec pended for deletion in Task 6.
mobile_accordion_spec remains pended for locale keys (Task 5)."
```

---

## Task 5: Application layout — same migration for workspace sidebar

**Files:** Modify `app/views/layouts/application.html.erb`.

**Steps:**

- [ ] **Step 1: Remove the drawer wrapper.** Delete the `data-controller="settings-drawer"` block (around lines 38-72) and replace with desktop-only column:

```erb
<% if Current.workspace.present? %>
  <div class="hidden md:flex shrink-0">
    <%= render "shared/workspace_sidebar", workspace: Current.workspace %>
  </div>
<% end %>
```

- [ ] **Step 2: Inject workspace sidebar via content_for.** Before `render "shared/header"`:

```erb
<% if Current.workspace.present? %>
  <% content_for :mobile_menu_sidebar do %>
    <%= render "shared/workspace_sidebar", workspace: Current.workspace %>
  <% end %>
<% end %>
```

- [ ] **Step 3: Verify the flex layout still works.** The main content wrapper needs to handle "no sidebar" gracefully when `Current.workspace` is nil (root, marketing pages). Check that `<main>` still renders full-width when no sidebar column is present. If the existing flex-row wrapper needs adjustment, do it here.

- [ ] **Step 4: Un-pend `mobile_accordion_spec.rb` for workspace.** Run it. Expected: partially failing on locale keys; pass on structural assertions.

- [ ] **Step 5: Run FULL suite.** Expected: 1894 + accordion examples; failures only on locale keys.

- [ ] **Step 6: Commit.**

```bash
git add app/views/layouts/application.html.erb
git commit -m "refactor(layouts): application.html.erb uses header accordion (Path Z)

Drops the workspace-context off-canvas drawer (toggle + overlay +
sliding panel from Phase B) for the same content_for-injected
accordion pattern. Sidebar renders desktop-only on the left; the
header accordion surfaces the same _workspace_sidebar partial inline
on mobile.

Awaiting locale-key cleanup (Task 6) for full spec pass."
```

---

## Task 6: Locale cleanup + delete drawer artifacts

**Files:**
- Delete: `app/javascript/controllers/settings_drawer_controller.js`
- Delete: `spec/system/settings/mobile_drawer_spec.rb`
- Modify: `config/locales/en/settings.en.yml` (remove `mobile_drawer:` block)
- Modify: `config/locales/en/workspaces.en.yml` (remove `mobile_drawer:` block)
- Modify: `config/locales/en/application.en.yml` (add `navigation.mobile_menu.*` keys)
- Modify: `app/views/shared/_header.html.erb` (swap placeholder `navigation.toggle_menu` for the new keys)

**Steps:**

- [ ] **Step 1: Add the new locale keys.** Under `navigation:` in `config/locales/en/application.en.yml`:

```yaml
mobile_menu:
  open: "Open menu"
  close: "Close menu"
  aria_label: "Main menu"
```

Keep `navigation.toggle_menu: "Toggle navigation menu"` for now; it may still be referenced. Verify via grep before deciding to delete.

- [ ] **Step 2: Update header partial.** Swap the hamburger button's `aria-label` to use `t("navigation.mobile_menu.open")` (closed state) — Stimulus toggles `aria-expanded` but the underlying label can stay "Open menu" since AT will announce expanded/collapsed via the attribute.

- [ ] **Step 3: Remove `settings.mobile_drawer.*`.** Verify no remaining references:

```bash
grep -rn "mobile_drawer" app/ config/ spec/
```

Expect zero matches after the layout edits in Tasks 4 + 5. If matches exist, fix them before deletion.

Then delete the `mobile_drawer:` block from `config/locales/en/settings.en.yml`.

- [ ] **Step 4: Remove `workspaces.mobile_drawer.*`** the same way.

- [ ] **Step 5: Delete `settings_drawer_controller.js`.**

```bash
rm app/javascript/controllers/settings_drawer_controller.js
```

Verify no remaining references:

```bash
grep -rn "settings-drawer\|settings_drawer\|data-settings-drawer" app/ spec/
```

Expect zero matches.

- [ ] **Step 6: Delete `spec/system/settings/mobile_drawer_spec.rb`.**

- [ ] **Step 7: Un-pend the two accordion specs.** Remove the `pending` blocks; the specs should now pass in full.

- [ ] **Step 8: Run FULL suite.** Expected: 1894 + 7 (4 settings accordion + 3 workspace accordion) − 4 (drawer spec deletion) + 1 (header mobile menu spec) = 1898 examples, 0 failures, 0 pending. Adjust counts based on exact assertions added.

- [ ] **Step 9: Manual browser verification.** Run `bin/dev`, visit at three viewports in both themes:
  - 375×667 (iPhone SE): accordion opens, sidebar contents visible, link tap navigates + auto-closes
  - 768×1024 (iPad portrait): below md breakpoint? If yes, accordion still shows. If no, desktop sidebar shows. Verify which side of the boundary the tablet falls on.
  - 1280×800 (desktop): inline sidebar, no hamburger visible

- [ ] **Step 10: Commit.**

```bash
git add app/javascript/controllers/settings_drawer_controller.js app/views/shared/_header.html.erb config/locales/en/settings.en.yml config/locales/en/workspaces.en.yml config/locales/en/application.en.yml spec/system/settings/mobile_drawer_spec.rb spec/system/settings/mobile_accordion_spec.rb spec/system/workspaces/mobile_accordion_spec.rb
git commit -m "refactor: retire mobile drawer; header accordion is the mobile nav (Path Z)

Deletes settings_drawer_controller.js (~120 LOC), the old
mobile_drawer_spec, and the settings.mobile_drawer + workspaces.mobile_drawer
locale namespaces. Adds navigation.mobile_menu.* shared keys consumed
by the header. Un-pends the accordion specs which now pass in full.

Net: -120 JS LOC, -57 spec LOC, +unified mobile pattern across both
workspace-scoped and settings-scoped layouts."
```

---

## Task 7: CHANGELOG + branch merge

**Files:** Modify `CHANGELOG.md`.

**Steps:**

- [ ] **Step 1: Update CHANGELOG.** Under `### Changed`, add one lean-format entry (per `feedback_lean_changelog.md`):

```markdown
- Mobile shell: header now expands accordion-style on mobile to surface the active sidebar's contents inline. Replaces the off-canvas drawer pattern shipped earlier this cycle (#148) — one navigation paradigm across breakpoints, no overlay/focus-trap/dialog ARIA, same axe AAA coverage. Workspace-scoped pages and settings pages both use the unified pattern.
```

Under `### Removed`, append:

```markdown
- `settings-drawer` Stimulus controller, `settings.mobile_drawer.*` and `workspaces.mobile_drawer.*` locale namespaces, and the off-canvas drawer markup from `settings.html.erb` and `application.html.erb` — superseded by the header accordion (see Changed).
```

Optionally annotate the existing drawer entry (`feat #148`) with a `[superseded]` marker, but a clean Changed/Removed pair is enough to tell the story.

- [ ] **Step 2: Run FULL suite once more.** Expected: clean.

- [ ] **Step 3: Commit.**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note Path Z header accordion supersedes mobile drawer"
```

- [ ] **Step 4: Fast-forward merge into `docs/settings-hub-spec`.**

```bash
git checkout docs/settings-hub-spec
git merge --ff-only feat/path-z-mobile-accordion
git branch -d feat/path-z-mobile-accordion
git log --oneline -8
```

---

## Verification plan

After Task 7 completion:

1. **Full RSpec suite** — `/opt/homebrew/bin/mise exec -- bundle exec rspec`. Expect green, count higher than baseline by net +1 to +4 examples.
2. **Lefthook pre-push** (will run on actual push) — same suite.
3. **Manual browser** at three viewports, two themes, exercised paths:
   - Settings → click sidebar destinations on mobile (375). Each should navigate AND collapse the accordion.
   - Workspace overview → tap hamburger → tap "Settings" → land on workspaces#edit AND accordion closed.
   - Switch workspace from accordion's sidebar switcher → land on new workspace's overview.
   - Resize browser from 1280 to 375 with accordion open: panel should transition cleanly (hamburger visible, sidebar column hidden, accordion stays expanded).
4. **axe-core both themes both states** — the spec already asserts this. Local axe-core CAN miss violations CI catches (per `feedback_ci_vs_local_axe.md`); push to remote and verify CI before merging the spec branch upstream.
5. **Bundle log monitoring** — `tail -f log/test.log` during system specs; ensure no N+1 warnings from Bullet on the doubly-rendered sidebar (Task 4 Step 3 mitigation).

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Double-render of `_settings_sidebar` (once in `content_for`, once desktop) causes N+1 | Medium | Define workspaces scope as a layout-local; pass the same Relation to both renders. Bullet config in `test.rb` is strict; spec failures will surface this. |
| Sidebar contents are too tall on small phones, accordion pushes main content off-screen | Medium | Apply `max-h-[calc(100vh-4rem)] overflow-y-auto` to the slot wrapper in the header. Schoger flagged this in panel review. |
| `content_for(:mobile_menu_sidebar)` block doesn't fire if defined after `render "shared/header"` | Medium | Place `content_for` blocks at the top of each layout body, BEFORE the header render. Document this in the layout comment. |
| Existing `header_mobile_menu_spec` reveals other Stimulus race conditions | Low | Spec is new in Task 1; it isolates the auto-close behavior. If race surfaces, add `expect(page).to have_no_css(...)` with explicit wait. |
| Removing `navigation.toggle_menu` breaks something | Low | Grep for it before removing; keep it if any partial still uses it. Path Z doesn't require deletion — only addition of the more specific keys. |
| Tablets (768-1023) feel awkward at md breakpoint | Low | Verify in browser at 768×1024. If awkward, raise breakpoint to `lg`; that's a one-class change (`md:hidden` → `lg:hidden`). |
| `Current.workspace` is nil on a settings page (auth pages, etc.) — sidebar render explodes | Medium | The settings sidebar partial already handles `current_workspace` nil/absent. Verify by visiting Appearance (workspace-agnostic) and Profile (personal) without a workspace switch context. |
| Mobile menu pre-existing in `_header.html.erb` already has its own anchor list; injecting the sidebar slot above it creates a long stack | Medium | Acceptable — the accordion is the only mobile nav surface. If too long, hide the redundant header anchor list on settings/workspace pages where the slot is populated: `<% unless content_for?(:mobile_menu_sidebar) %>...<% end %>` around the existing nav block. |

---

## Rollback strategy

Path Z lands as a single branch off `docs/settings-hub-spec`. If issues surface:

- **Pre-merge:** delete the branch. No production impact (this branch isn't deployed; `docs/settings-hub-spec` is the staging branch for the settings hub work).
- **Post-merge to `docs/settings-hub-spec`:** revert the Path Z commits as a single range. Drawer code returns. Spec files restore. Locale keys restore.
- **Post-merge to `main`:** treat as any other regression — revert the merge commit, push hotfix, then re-plan Path Z with the lesson learned.

The drawer pattern is preserved in git history at `f4d92fc` and earlier; any revert lands the drawer exactly as it shipped originally.

---

## Out-of-scope (re-stated)

- Refactoring the header user-avatar dropdown into the accordion at the controller level. Path Z keeps the user-avatar dropdown as-is on desktop; on mobile its menu items already appear inside the accordion's expanded panel.
- Chevron rotation animation on the workspace switcher trigger (deferred from Path Y discussion).
- Changing the workspace switcher partial's internal markup.
- Adding new mobile-specific destinations to the sidebars.
- Header sticky-positioning changes.
- Theme-toggle position changes on mobile.

---

## Panel sign-offs (from Path Y discussion, 2026-05-20)

- **Jason Fried** — Strong support. "One paradigm, no scrim, no slide. What Basecamp does."
- **Steve Schoger** — Support with polish note. "Cap the panel height: `max-h-[calc(100vh-4rem)] overflow-y-auto`."
- **Adam Wathan** — Support. "Less code, fewer breakpoints. Just utilities."
- **WCAG 2.2 AAA specialist** — Support, accessibility-positive. "Accordion is *easier* to make AAA than a modal drawer."
- **Sandi Metz / frontend architect** — Support with budget. "Net code negative. Drawer just shipped — earn the churn with a Phase Z commit history and a changelog narrative."

Verdict: 5-0 in favor. Plan ratified.
