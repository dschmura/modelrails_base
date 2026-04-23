# Footer Cohesion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pull the Biscuit gem's floating "Manage cookies" button into the footer as a regular link, regroup the nav links into two semantic clusters separated by a vertical divider, and restructure the footer into a two-row layout with a centered copyright, responsive down to mobile.

**Architecture:** The footer partial is fully rewritten. Two rows: (1) brand + two `<nav>` clusters + a11y-sim trigger + spacer and (2) a centered copyright below a horizontal divider. The gem's `.biscuit-manage-link` is hidden via one global CSS rule. A tiny Stimulus controller (`footer_controller.js`) dispatches clicks from a new footer button to the now-hidden gem button, invoking the gem's existing reopen behavior with zero coupling to its internals.

**Tech Stack:** Rails 8.1 ERB, TailwindCSS 4 with semantic tokens, Stimulus, RSpec (view + system), Playwright-backed Capybara, Biscuit-rails gem.

**Spec:** [docs/superpowers/specs/2026-04-22-footer-cohesion-design.md](docs/superpowers/specs/2026-04-22-footer-cohesion-design.md)

---

## File Map

| Path | Action | Purpose |
| ---- | ------ | ------- |
| `config/locales/en/application.en.yml` | Modify | Add `footer.manage_cookies`, `footer.aria.product`, `footer.aria.legal` |
| `app/assets/tailwind/application.css` | Modify | Hide `.biscuit-manage-link` globally |
| `app/javascript/controllers/footer_controller.js` | Create | Stimulus controller with `reopenCookies` action |
| `app/views/shared/_footer.html.erb` | Rewrite | New two-row layout with link clusters |
| `spec/views/shared/footer_spec.rb` | Create | View spec asserting structure, clusters, accessibility |
| `spec/system/footer_cookies_spec.rb` | Create | System spec: click Manage cookies → Biscuit panel opens |

Six files touched. Net ~120 lines.

---

## Task 1 — Add I18n keys

**Files:**

- Modify: `config/locales/en/application.en.yml:27-33`

- [ ] **Step 1.1: Read the current `footer:` section to confirm indentation**

Run: `sed -n '27,33p' config/locales/en/application.en.yml`

Expected output:

```text
  footer:
    about: "About"
    privacy: "Privacy"
    contact: "Contact"
    docs: "Docs"
    copyright: "ModelRails. All rights reserved."
```

- [ ] **Step 1.2: Extend the `footer:` key tree**

Edit `config/locales/en/application.en.yml`. Replace the `footer:` block (lines 27–33) with:

```yaml
  footer:
    about: "About"
    privacy: "Privacy"
    contact: "Contact"
    docs: "Docs"
    manage_cookies: "Manage cookies"
    copyright: "ModelRails. All rights reserved."
    aria:
      product: "Product"
      legal: "Legal and privacy"
```

- [ ] **Step 1.3: Verify YAML is valid**

Run: `mise exec -- bundle exec ruby -ryaml -e 'YAML.load_file("config/locales/en/application.en.yml")' && echo OK`

Expected: `OK`

- [ ] **Step 1.4: Commit**

```bash
git add config/locales/en/application.en.yml
git commit -m "i18n: add footer keys for cookies link and nav cluster labels"
```

---

## Task 2 — Hide the Biscuit gem's floating manage-link via CSS

**Files:**

- Modify: `app/assets/tailwind/application.css` (append at end)

- [ ] **Step 2.1: Confirm the gem's CSS class name**

Run: `grep -n "biscuit-manage-link" /Users/dschmura/.local/share/mise/installs/ruby/4.0.2/lib/ruby/gems/4.0.0/gems/biscuit-rails-0.1.4/app/views/biscuit/banner/_banner.html.erb`

Expected: one line showing `<button type="button" class="biscuit-manage-link" ...>`. This confirms the selector we target.

- [ ] **Step 2.2: Append the override rule**

Append to `app/assets/tailwind/application.css`:

```css

/* ==========================================================================
   Override Biscuit's post-consent floating "Manage cookies" button.
   We render our own footer-integrated link instead. The gem's button
   remains in the DOM (footer_controller dispatches clicks to it).
   ========================================================================== */

.biscuit-manage-link {
  display: none !important;
}
```

- [ ] **Step 2.3: Verify Tailwind still builds**

Run: `mise exec -- bin/rails tailwindcss:build 2>&1 | tail -3`

Expected: ends with something like `Done in Xms.` — no errors about unknown syntax.

- [ ] **Step 2.4: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "css: hide Biscuit floating manage-link, footer renders its own"
```

---

## Task 3 — Create the footer Stimulus controller

**Files:**

- Create: `app/javascript/controllers/footer_controller.js`

- [ ] **Step 3.1: Create the controller file**

Write `app/javascript/controllers/footer_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Footer controller. Currently has one responsibility:
// dispatch a click to Biscuit's hidden manage-link so our footer
// button can reopen the cookie preferences panel.
export default class extends Controller {
  reopenCookies(event) {
    event.preventDefault()
    document.querySelector(".biscuit-manage-link")?.click()
  }
}
```

- [ ] **Step 3.2: Verify Stimulus auto-registers it**

Run: `grep -n "eagerLoadControllersFrom" app/javascript/controllers/index.js`

Expected: shows `eagerLoadControllersFrom("controllers", application)`. This means the controller is auto-discovered — no manual registration needed.

- [ ] **Step 3.3: Commit**

```bash
git add app/javascript/controllers/footer_controller.js
git commit -m "js: add footer Stimulus controller for cookie preferences reopen"
```

---

## Task 4 — View spec + footer partial rewrite (TDD)

**Files:**

- Create: `spec/views/shared/footer_spec.rb`
- Rewrite: `app/views/shared/_footer.html.erb`

- [ ] **Step 4.1: Write the failing view spec**

Create `spec/views/shared/footer_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "shared/_footer", type: :view do
  before { render "shared/footer" }

  describe "structure" do
    it "renders a footer landmark" do
      expect(rendered).to have_css("footer")
    end

    it "renders the site logo link to root" do
      expect(rendered).to have_css("a[href='/']")
    end

    it "renders a centered copyright row with the current year" do
      expect(rendered).to have_css("p.text-center", text: Date.current.year.to_s)
      expect(rendered).to have_css("p.text-center", text: I18n.t("footer.copyright"))
    end

    it "includes an aria-hidden divider element" do
      expect(rendered).to have_css("[aria-hidden='true']", visible: :all)
    end
  end

  describe "Product cluster" do
    let(:selector) { "nav[aria-label='#{I18n.t('footer.aria.product')}']" }

    it "is a nav landmark with the correct aria-label" do
      expect(rendered).to have_css(selector)
    end

    it "contains the About link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.about"))
    end

    it "contains the Docs link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.docs"))
    end
  end

  describe "Legal cluster" do
    let(:selector) { "nav[aria-label='#{I18n.t('footer.aria.legal')}']" }

    it "is a nav landmark with the correct aria-label" do
      expect(rendered).to have_css(selector)
    end

    it "contains the Privacy link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.privacy"))
    end

    it "contains the Contact link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.contact"))
    end

    it "contains a Manage cookies button wired to footer#reopenCookies" do
      expect(rendered).to have_css(
        "#{selector} button[data-action*='click->footer#reopenCookies']",
        text: I18n.t("footer.manage_cookies")
      )
    end

    it "marks the Manage cookies button as opening a dialog" do
      expect(rendered).to have_css(
        "#{selector} button[data-action*='click->footer#reopenCookies'][aria-haspopup='dialog']"
      )
    end
  end
end
```

- [ ] **Step 4.2: Run the spec to verify it fails**

Run: `mise exec -- bundle exec rspec spec/views/shared/footer_spec.rb 2>&1 | tail -20`

Expected: FAIL — current footer doesn't render `<nav>` elements, doesn't have the Manage cookies button, etc. You should see 6+ failed examples with messages like "expected to find css `nav[aria-label='Product']`".

- [ ] **Step 4.3: Rewrite the footer partial**

Replace the entire contents of `app/views/shared/_footer.html.erb` with:

```erb
<footer class="bg-surface border-t border-border mt-auto">
  <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <%# Row 1: brand + nav clusters + dev trigger (responsive) %>
    <div class="flex flex-col items-center gap-5
                sm:flex-row sm:flex-wrap sm:items-center sm:justify-center sm:gap-4
                lg:flex-nowrap lg:justify-start lg:gap-6">
      <%= link_to main_app.root_path,
            class: "hover:opacity-80 transition-opacity
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" do %>
        <%= render "shared/site_logo", size: :small, show_name: true %>
      <% end %>

      <div class="flex flex-col items-center gap-5 sm:flex-row sm:items-center sm:gap-6">
        <nav aria-label="<%= t("footer.aria.product") %>"
             class="flex items-center gap-5">
          <%= link_to t("footer.about"), main_app.about_path,
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
          <%= link_to t("footer.docs"), "/docs",
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
        </nav>

        <span class="hidden sm:block w-px h-3.5 bg-border" aria-hidden="true"></span>

        <nav aria-label="<%= t("footer.aria.legal") %>"
             class="flex items-center gap-5">
          <%= link_to t("footer.privacy"), main_app.privacy_path,
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
          <%= link_to t("footer.contact"), main_app.contact_path,
                class: "text-sm text-text-muted
                        hover:text-interactive-hover
                        focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
          <button type="button"
                  data-controller="footer"
                  data-action="click->footer#reopenCookies"
                  aria-haspopup="dialog"
                  class="text-sm text-text-muted
                         hover:text-interactive-hover
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
            <%= t("footer.manage_cookies") %>
          </button>
        </nav>
      </div>

      <div class="lg:flex-1" aria-hidden="true"></div>

      <%= render "shared/a11y_sim" %>
    </div>

    <%# Horizontal divider between rows %>
    <div class="mt-6 border-t border-border" aria-hidden="true"></div>

    <%# Row 2: centered copyright %>
    <p class="mt-6 text-xs text-text-muted text-center">
      &copy; <%= Date.current.year %> <%= t("footer.copyright") %>
    </p>
  </div>
</footer>
```

- [ ] **Step 4.4: Run the spec to verify it passes**

Run: `mise exec -- bundle exec rspec spec/views/shared/footer_spec.rb 2>&1 | tail -10`

Expected: all examples pass (`X examples, 0 failures`).

- [ ] **Step 4.5: Commit**

```bash
git add spec/views/shared/footer_spec.rb app/views/shared/_footer.html.erb
git commit -m "feat: restructure footer with clustered nav and centered copyright"
```

---

## Task 5 — System spec for Manage cookies reopen flow

**Files:**

- Create: `spec/system/footer_cookies_spec.rb`

- [ ] **Step 5.1: Write the system spec**

Create `spec/system/footer_cookies_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Footer: Manage cookies reopens Biscuit panel", type: :system do
  it "renders a Manage cookies button in the footer on public pages" do
    visit root_path
    within("footer") do
      expect(page).to have_button(I18n.t("footer.manage_cookies"))
    end
  end

  it "reopens the Biscuit preferences panel when clicked" do
    visit root_path

    # Dismiss the initial consent banner so only the floating manage-link
    # (now hidden by our CSS) and our footer button remain.
    page.execute_script(<<~JS)
      document.querySelectorAll('[data-biscuit-target="banner"]').forEach(el => el.hidden = true);
    JS

    within("footer") do
      click_button I18n.t("footer.manage_cookies")
    end

    # Biscuit's preferences panel should become visible.
    expect(page).to have_css("[data-biscuit-target='preferencesPanel']:not([hidden])", wait: 2)
  end

  it "hides the gem's floating .biscuit-manage-link so only our footer button shows" do
    visit root_path
    # The gem still renders it in the DOM; our CSS hides it.
    expect(page).to have_css(".biscuit-manage-link", visible: :hidden)
    expect(page).not_to have_css(".biscuit-manage-link", visible: true)
  end
end
```

- [ ] **Step 5.2: Run the system spec**

Run: `mise exec -- bundle exec rspec spec/system/footer_cookies_spec.rb 2>&1 | tail -15`

Expected: all 3 examples pass.

If the "reopens the Biscuit preferences panel" test fails because the panel doesn't become visible, inspect with:

```bash
mise exec -- bundle exec rspec spec/system/footer_cookies_spec.rb:10 2>&1 | tail -30
```

And check what Biscuit's `togglePreferences` / `reopen` action actually does. Likely fix: ensure the banner element's `hidden` attribute is removed OR the preferences panel's `hidden` attribute is removed.

- [ ] **Step 5.3: Commit**

```bash
git add spec/system/footer_cookies_spec.rb
git commit -m "test: system spec for footer Manage cookies reopen flow"
```

---

## Task 6 — Full test suite and final verification

**Files:**

- None (verification only)

- [ ] **Step 6.1: Run the full test suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -5`

Expected: `X examples, 0 failures`. `X` should be around 1022 (up from 1007 pre-plan; the view spec adds 12 examples and the system spec adds 3).

If any UNRELATED test fails, stop and investigate — it likely means the footer restructure accidentally broke another spec that depended on the old DOM structure.

- [ ] **Step 6.2: Manual sanity check (optional but recommended)**

1. Start the dev server: `mise exec -- bin/dev`
2. Visit `http://localhost:3000/`
3. Confirm:
   - Footer has two rows; copyright is centered below
   - Two nav clusters separated by a vertical divider on desktop
   - The Biscuit cookie banner (if first visit) still works normally
   - Clicking "Manage cookies" in the footer reopens the preferences panel
   - The old floating "Manage cookies" button in the bottom-left corner is gone
4. Resize the browser to ~375px (mobile). Confirm:
   - Footer stacks vertically
   - Vertical divider between nav clusters is hidden
   - Copyright remains centered
5. Resize to ~700px (tablet). Confirm row 1 items wrap gracefully.

- [ ] **Step 6.3: Review git log**

Run: `git log --oneline $(git merge-base HEAD main)..HEAD`

Expected: 5 commits from this plan (i18n, css, js controller, footer+view spec, system spec), each with a clear conventional-commit subject.

- [ ] **Step 6.4: Commit the design doc and plan**

```bash
git add docs/superpowers/specs/2026-04-22-footer-cohesion-design.md \
        docs/superpowers/plans/2026-04-22-footer-cohesion.md
git commit -m "docs: footer cohesion spec and implementation plan"
```

---

## Deferred (post-merge)

None. All spec requirements covered in Tasks 1–5.

## Open Questions

None. All decisions locked during brainstorming and spec review.
