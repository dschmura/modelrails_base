# Settings Hub Mobile Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Closes:** #148 (Settings hub: add mobile drawer pattern for sidebar below 768px).

**Goal:** Settings hub sidebar becomes an off-canvas drawer on mobile (below `md` / 768px). Today the sidebar is `hidden md:block` — mobile users have no in-app navigation between settings destinations once they're on one. A hamburger button + slide-in drawer + overlay + focus trap fills the gap.

**Architecture:** Single Stimulus controller (`settings-drawer`) handles open/close, ESC, click-outside (via overlay element), focus trap, and auto-close on link click. CSS transitions slide the drawer in from the left with an opacity-fading overlay backing. Desktop (`md` and up) bypasses the drawer entirely — the sidebar continues to render in its inline position. No layout structural change beyond adding the hamburger button + overlay element + Stimulus wiring.

**Tech Stack:** Stimulus, TailwindCSS 4 (existing `motion-safe:` + transitions), RSpec system specs with Capybara + Playwright (specifically the 375px viewport pattern from `spec/system/account/notification_preferences_mobile_spec.rb`), axe-core (WCAG 2.2 AAA + WAI-ARIA dialog modal pattern).

**Out of scope:**
- Header user menu drawer (separate concern; mobile pattern there may differ)
- Persistent drawer state across navigation (Stimulus state is per-page; sidebar auto-closes on Turbo visit which is the desired behavior)
- Right-aligned drawers, top drawers, other drawer variants

**Branch:** `feat/settings-hub-mobile-drawer` off `docs/settings-hub-spec` (already checked out).

**Pre-task baseline:** 1891 examples, 0 failures, 0 pending. Coverage 94.77% line.

---

## File Map

**Create:**
- `app/javascript/controllers/settings_drawer_controller.js` — toggle, ESC, focus trap, click-outside, close-on-nav

**Modify:**
- `app/views/layouts/settings.html.erb` — add hamburger button (visible md:hidden), wrap sidebar in drawer container (with mobile classes), add overlay element, wire Stimulus controller
- `config/locales/en/settings.en.yml` — add `mobile_drawer.open` + `mobile_drawer.close` + `mobile_drawer.aria_label` keys
- `CHANGELOG.md` — note mobile drawer

**Create:**
- `spec/system/settings/mobile_drawer_spec.rb` — system spec at 375px viewport: open drawer, navigate, close

---

## Task 1: I18n keys for drawer controls

**Files:** Modify `config/locales/en/settings.en.yml`

**Steps:**

- [ ] **Step 1: Add keys.** Append to `settings.en.yml` under `settings:` (alongside existing `sidebar:` and `pages:`):

```yaml
mobile_drawer:
  open: "Open settings menu"
  close: "Close settings menu"
  aria_label: "Settings menu"
```

- [ ] **Step 2: Smoke check.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rails runner "puts I18n.t('settings.mobile_drawer.open'); puts I18n.t('settings.mobile_drawer.close'); puts I18n.t('settings.mobile_drawer.aria_label')"
```

Expected three lines, all rendered correctly.

- [ ] **Step 3: Run FULL suite.**

Expected: 1891/0/0 (no behavior change).

- [ ] **Step 4: Commit.**

```bash
git add config/locales/en/settings.en.yml
git commit -m "feat(i18n): mobile drawer keys for settings hub

Three keys under settings.mobile_drawer.* for the hamburger button
label (open) state, close state, and the drawer container's
aria-label. Consumed by the new settings-drawer Stimulus controller
+ settings layout in subsequent tasks."
```

---

## Task 2: Stimulus drawer controller

**Files:** Create `app/javascript/controllers/settings_drawer_controller.js`

**Steps:**

- [ ] **Step 1: Inspect Stimulus auto-load pattern.** Run `cat app/javascript/controllers/index.js | head -10`. Confirm `eagerLoadControllersFrom("controllers", application)` or similar — the new file will be auto-discovered as `data-controller="settings-drawer"`.

- [ ] **Step 2: Create the controller.** Write `app/javascript/controllers/settings_drawer_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Off-canvas drawer for the Settings hub sidebar on mobile (below md).
// Handles open/close via hamburger toggle, ESC key, click-outside on
// overlay, and auto-close when a sidebar link is clicked (so navigating
// to a different settings destination dismisses the drawer cleanly).
//
// Focus trap: on open, focus moves to the first focusable element inside
// the drawer; on close, focus restores to the toggle button. Tab/Shift+Tab
// cycling stays within the drawer while open.
//
// Desktop (md and up) bypasses all of this — the sidebar is rendered
// inline and the toggle button is `md:hidden`.
export default class extends Controller {
  static targets = ["panel", "overlay", "toggle"]

  connect() {
    this.boundEscape = this.onEscape.bind(this)
    this.boundLinkClick = this.onLinkClick.bind(this)
    this.boundFocusTrap = this.onFocusTrap.bind(this)
    document.addEventListener("keydown", this.boundEscape)
    this.panelTarget.addEventListener("click", this.boundLinkClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEscape)
    document.removeEventListener("keydown", this.boundFocusTrap)
    this.panelTarget.removeEventListener("click", this.boundLinkClick)
  }

  open() {
    this.element.dataset.drawerState = "open"
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.removeAttribute("inert")
    this.panelTarget.removeAttribute("aria-hidden")
    document.body.style.overflow = "hidden"
    document.addEventListener("keydown", this.boundFocusTrap)
    requestAnimationFrame(() => this.focusFirstElement())
  }

  close() {
    this.element.dataset.drawerState = "closed"
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.panelTarget.setAttribute("inert", "")
    this.panelTarget.setAttribute("aria-hidden", "true")
    document.body.style.overflow = ""
    document.removeEventListener("keydown", this.boundFocusTrap)
    this.toggleTarget.focus()
  }

  toggle() {
    this.element.dataset.drawerState === "open" ? this.close() : this.open()
  }

  onEscape(event) {
    if (event.key === "Escape" && this.element.dataset.drawerState === "open") {
      this.close()
    }
  }

  onLinkClick(event) {
    if (event.target.closest("a")) this.close()
  }

  onFocusTrap(event) {
    if (event.key !== "Tab") return
    const focusables = this.focusableElements()
    if (focusables.length === 0) return
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  focusableElements() {
    return Array.from(
      this.panelTarget.querySelectorAll(
        'a, button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.hasAttribute("disabled") && el.offsetParent !== null)
  }

  focusFirstElement() {
    const first = this.focusableElements()[0]
    if (first) first.focus()
  }
}
```

- [ ] **Step 3: Smoke-check the file loads.** Run `/opt/homebrew/bin/mise exec -- bin/rails s` is overkill; just verify syntax via:

```bash
node -c app/javascript/controllers/settings_drawer_controller.js 2>&1 || echo "Note: node -c doesn't work on ES modules; ignore syntax-only check"
```

Stimulus controllers parse at boot; a real smoke is opening a page that mounts it (next task).

- [ ] **Step 4: Run FULL suite.**

Expected: 1891/0/0 (no integration yet; the controller exists but isn't mounted anywhere).

- [ ] **Step 5: Commit.**

```bash
git add app/javascript/controllers/settings_drawer_controller.js
git commit -m "feat(a11y): Stimulus controller for Settings hub mobile drawer

Handles open/close via toggle button, ESC, click-outside (via
overlay), and auto-close on sidebar link click. Focus trap cycles
Tab/Shift+Tab within the panel; on close, focus restores to the
toggle button per WAI-ARIA dialog modal pattern. body overflow
locked during open state to prevent background scroll.

Mounted in the next task via the settings layout. Desktop (md+)
doesn't touch any of this — the toggle button is md:hidden, and
the sidebar renders inline."
```

---

## Task 3: Layout integration — hamburger + drawer wrapper + overlay

**Files:** Modify `app/views/layouts/settings.html.erb`

**Steps:**

- [ ] **Step 1: Inspect current layout state.** Read `app/views/layouts/settings.html.erb`. Find the current sidebar wrapper (likely `<div class="hidden md:block"> <%= render "shared/settings_sidebar" ... %> </div>` from Phase 2 Task 9 fix).

- [ ] **Step 2: Restructure the mobile section.** Replace the current `<div class="hidden md:block">...sidebar...</div>` with a drawer-aware structure. The desktop behavior MUST remain identical — sidebar rendered inline at md and up.

New structure (placement: same position in the layout where the existing `<div class="hidden md:block">` block lives):

```erb
<%# Mobile drawer + desktop inline sidebar. Below md, the toggle
    button reveals the drawer (slides from left, overlay, focus
    trapped). At md and up, the desktop column renders inline. %>
<div data-controller="settings-drawer"
     data-drawer-state="closed"
     class="contents">
  <%# Hamburger toggle — visible only below md. Aria-controls points
      to the panel; aria-expanded reflects state. %>
  <button type="button"
          data-settings-drawer-target="toggle"
          data-action="click->settings-drawer#toggle"
          aria-expanded="false"
          aria-controls="settings-drawer-panel"
          class="md:hidden fixed top-4 left-4 z-30 inline-flex items-center justify-center w-11 h-11 rounded-md bg-surface border border-border text-text-heading shadow-md focus:outline-none focus:ring-2 focus:ring-interactive-focus">
    <span class="sr-only" data-open-label="<%= t("settings.mobile_drawer.open") %>"
                          data-close-label="<%= t("settings.mobile_drawer.close") %>">
      <%= t("settings.mobile_drawer.open") %>
    </span>
    <%# Hamburger icon (SVG) %>
    <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6" fill="none" viewBox="0 0 24 24"
         stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
    </svg>
  </button>

  <%# Overlay — covers the page when drawer open. Clicking it closes. %>
  <div data-settings-drawer-target="overlay"
       data-action="click->settings-drawer#close"
       aria-hidden="true"
       class="md:hidden fixed inset-0 z-30 bg-black/50 opacity-0 pointer-events-none transition-opacity duration-200
              [[data-drawer-state=open]_&]:opacity-100 [[data-drawer-state=open]_&]:pointer-events-auto"></div>

  <%# Drawer panel: contains the sidebar. Below md, slides in from
      the left with a transition. At md and up, the panel becomes
      part of the normal flex layout via md:relative + md:translate-x-0. %>
  <aside data-settings-drawer-target="panel"
         id="settings-drawer-panel"
         role="dialog"
         aria-modal="true"
         aria-label="<%= t("settings.mobile_drawer.aria_label") %>"
         inert
         aria-hidden="true"
         class="fixed top-0 left-0 z-40 h-full w-72 bg-surface shadow-xl -translate-x-full transition-transform duration-200
                md:relative md:z-auto md:h-auto md:w-auto md:shadow-none md:translate-x-0
                md:!inert-false
                [[data-drawer-state=open]_&]:translate-x-0
                motion-safe:transition-transform">
    <%= render "shared/settings_sidebar",
          workspaces: Current.user.workspaces.kept.includes(:logo_attachment, memberships: [ :role, { user: :avatar_attachment } ]),
          current_workspace: Current.workspace %>
  </aside>
</div>
```

Key things in this structure:
- `data-drawer-state="closed"` on the controller's root element — drives the open/close CSS via the `[[data-drawer-state=open]_&]:` arbitrary variants
- Toggle button: `fixed top-4 left-4 z-30` so it floats over content; `md:hidden` ensures desktop doesn't see it
- Overlay: hidden until `data-drawer-state="open"`, then opacity fades in
- Panel: starts `-translate-x-full` (off-screen left); when `data-drawer-state=open`, translates to 0. At `md+`, becomes `relative + translate-x-0` always, integrated into normal flow
- `inert` attribute: removes the panel from tabbing + accessibility tree when closed. Controller toggles it
- `motion-safe:transition-transform`: respects reduced-motion
- Sidebar render preserved unchanged — same `workspaces` preload from before

**On `[[data-drawer-state=open]_&]:` syntax:** Tailwind 4 arbitrary variants matching parent attribute selectors. The `_` is the space → child selector. So `[[data-drawer-state=open]_&]:translate-x-0` translates to: when the ancestor with `data-drawer-state="open"` exists, translate-x-0 applies. If this Tailwind syntax doesn't work in this project's Tailwind version, fall back to a small `@layer` CSS rule in `app/assets/tailwind/application.css`.

**On `md:!inert-false`:** there's no Tailwind utility to remove `inert` at a breakpoint. Either (a) JavaScript removes `inert` on resize past md (rare scenario), or (b) accept that on desktop the panel is `inert` by default but irrelevant because `md:translate-x-0` makes it always-visible. Actually, **the inert attribute prevents interaction even when visible**, so we DO need to handle it. Simpler approach: move the inert logic into the Stimulus controller's `connect()`. On connect, check viewport — if `md+`, remove `inert`; otherwise keep. Then add a resize listener to update on breakpoint crossings.

Actually, the simplest fix: only apply `inert` when explicitly closed AND we're below md. Use the controller to manage this directly. The initial markup omits `inert`; the controller in `connect()` sets `inert` if viewport < 768px AND state is closed.

Update the controller (revise `connect()` from Task 2):

```javascript
connect() {
  // ... existing event listeners ...
  this.mediaQuery = window.matchMedia("(max-width: 767px)")
  this.boundUpdateInert = this.updateInert.bind(this)
  this.mediaQuery.addEventListener("change", this.boundUpdateInert)
  this.updateInert()
}

disconnect() {
  // ... existing cleanup ...
  this.mediaQuery.removeEventListener("change", this.boundUpdateInert)
}

updateInert() {
  const isMobile = this.mediaQuery.matches
  const isOpen = this.element.dataset.drawerState === "open"
  if (isMobile && !isOpen) {
    this.panelTarget.setAttribute("inert", "")
    this.panelTarget.setAttribute("aria-hidden", "true")
  } else {
    this.panelTarget.removeAttribute("inert")
    this.panelTarget.removeAttribute("aria-hidden")
  }
}
```

And remove `inert` + `aria-hidden` from the initial markup (the controller sets them on connect based on viewport).

This is the cleanest path. Apply both changes — view markup AND controller updates — as one cohesive commit in this task.

- [ ] **Step 3: Run FULL suite.**

Existing system specs that visit settings pages will now encounter the hamburger button (always rendered, `md:hidden` only at md+). At desktop viewports (Playwright default), it should be hidden by CSS and ignored. axe AAA might flag something — verify.

Expected: 1891/0/0. If failures, investigate.

- [ ] **Step 4: Commit.**

```bash
git add app/views/layouts/settings.html.erb app/javascript/controllers/settings_drawer_controller.js
git commit -m "feat(views): mobile drawer for Settings hub sidebar (closes #148)

Hamburger toggle (md:hidden, fixed top-left) reveals an off-canvas
drawer that slides in from the left below 768px. Overlay backs the
drawer; clicking closes. Stimulus controller manages open/close,
ESC, focus trap, click-outside, and auto-close on sidebar nav.
inert + aria-hidden toggle via the controller based on viewport
breakpoint so desktop (md+) keeps the panel fully interactive.

Sidebar partial unchanged — same render call, same preload. The
mobile/desktop split lives entirely in the layout's structural
classes."
```

---

## Task 4: System spec at 375px viewport

**Files:** Create `spec/system/settings/mobile_drawer_spec.rb`

**Steps:**

- [ ] **Step 1: Read the existing mobile spec for pattern reference.** Look at `spec/system/account/notification_preferences_mobile_spec.rb` — it sets a 375px viewport. Note the exact `page.driver.browser.set_viewport_size` or similar Capybara/Playwright API call.

- [ ] **Step 2: Write the spec.** Create `spec/system/settings/mobile_drawer_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Settings hub — mobile drawer", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    # Set mobile viewport (375x667 — iPhone SE 2nd gen)
    page.driver.resize_window(375, 667)
  end

  it "shows the hamburger toggle and hides the sidebar below md" do
    visit edit_account_profile_path
    expect(page).to have_button(I18n.t("settings.mobile_drawer.open"))
    # Sidebar panel is in DOM but inert + translated off-screen
    aside = page.find("aside[role='dialog']")
    expect(aside["inert"]).to be_truthy
  end

  it "opens the drawer when the toggle is clicked" do
    visit edit_account_profile_path
    click_button I18n.t("settings.mobile_drawer.open")
    aside = page.find("aside[role='dialog']")
    expect(aside["inert"]).to be_falsey
    # data-drawer-state on the controller root toggles to "open"
    expect(page).to have_css("[data-drawer-state='open']")
  end

  it "closes the drawer when a sidebar link is clicked (auto-dismiss on nav)" do
    visit edit_account_profile_path
    click_button I18n.t("settings.mobile_drawer.open")

    # Click a sidebar item — drawer closes, page navigates
    within("[data-settings-drawer-target='panel']") do
      click_link I18n.t("settings.sidebar.items.notifications")
    end

    # After navigation, drawer should be closed
    expect(page).to have_css("[data-drawer-state='closed']")
    expect(page).to have_current_path(edit_account_notification_preferences_path)
  end

  it "passes axe-core at WCAG 2.2 AAA both states (closed + open)" do
    visit edit_account_profile_path

    # Closed state — axe runs on initial mount
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations (closed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    # Open state — same axe check
    click_button I18n.t("settings.mobile_drawer.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations (open):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
```

**Important:** the exact Capybara API for resizing the window may differ. The Phase 2 Task 9 fix added the `notification_preferences_mobile_spec.rb` which already proves the 375x667 viewport pattern works — copy whatever API it uses (likely `page.driver.resize_window` or `Capybara.current_session.driver.browser.set_viewport_size`).

- [ ] **Step 3: Run the spec in isolation.**

```bash
/opt/homebrew/bin/mise exec -- bundle exec rspec spec/system/settings/mobile_drawer_spec.rb
```

Expected: all 4 examples PASS.

- [ ] **Step 4: Run FULL suite.**

Expected: 1895 examples (1891 + 4), 0 failures, 0 pending.

If failures occur in OTHER specs (e.g., something else now breaks at 375px because of the hamburger button), investigate. The button is `md:hidden` so desktop tests shouldn't see it. But the always-rendered overlay + drawer DOM elements might affect something.

- [ ] **Step 5: Commit.**

```bash
git add spec/system/settings/mobile_drawer_spec.rb
git commit -m "test(system): mobile drawer behavior + axe AAA both states

Asserts hamburger visibility at 375px, drawer open/close via toggle
+ via sidebar link click (auto-dismiss on nav), inert attribute
toggling, and axe AAA in both closed + open states across light +
dark themes."
```

---

## Task 5: CHANGELOG + close #148

**Files:** Modify `CHANGELOG.md`

**Steps:**

- [ ] **Step 1: Add CHANGELOG entry.** Under `## [Unreleased]` → `### Added`:

```markdown
- Settings hub mobile drawer: hamburger toggle below 768px slides the sidebar in as an off-canvas drawer with overlay, focus trap, ESC + click-outside dismiss, and auto-close on sidebar navigation (closes #148).
```

- [ ] **Step 2: Close #148.**

```bash
gh issue close 148 --comment "Closed by feat/settings-hub-mobile-drawer — hamburger toggle + slide-in drawer + overlay + focus trap + auto-close on nav. WCAG 2.2 AAA verified in both closed + open states. See CHANGELOG entry under [Unreleased]."
```

Verify: `gh issue view 148 --json state -q .state` → `CLOSED`.

- [ ] **Step 3: Run FULL suite one last time.**

Expected: 1895 examples, 0 failures, 0 pending.

- [ ] **Step 4: Commit.**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note settings hub mobile drawer (closes #148)"
```

---

## Self-Review

**Spec coverage:** Stimulus controller + view markup + system spec at mobile viewport + axe AAA both states. The 4-example spec covers: toggle visibility, open behavior, auto-close on nav, AAA compliance.

**Placeholder scan:** all steps have exact file paths and full code blocks.

**Identifier consistency:** `data-controller="settings-drawer"` (DOM) ↔ `settings_drawer_controller.js` (file) ↔ Stimulus auto-discovery convention. `data-settings-drawer-target="toggle|overlay|panel"` (DOM) ↔ `static targets = ["panel", "overlay", "toggle"]` (controller).

**Out-of-scope items explicitly deferred** — header user menu drawer, persistent state, other variants.

---

## Execution Handoff

Plan complete. Continuing with subagent-driven execution.
