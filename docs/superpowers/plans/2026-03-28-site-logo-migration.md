# Site Logo Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the ModelRails SVG logo mark + app name wordmark to the header and footer, matching the pattern from modelrails_agent_os.

**Architecture:** Create a reusable `_site_logo.html.erb` partial with configurable size, color, and optional name display. Replace the plain text brand link in the header and footer with this partial. The SVG is inline (no external asset files needed) and uses `currentColor` for theming.

**Tech Stack:** ERB partial with strict locals, inline SVG, TailwindCSS, I18n

**Source file:** `/Users/dschmura/Documents/code/modelrails_agent_os/app/views/shared/_site_logo.html.erb`

---

### Task 1: Create the `_site_logo` partial

**Files:**
- Create: `app/views/shared/_site_logo.html.erb`
- Test: `spec/system/static_pages_spec.rb`

- [ ] **Step 1: Write the failing system test**

Add to `spec/system/static_pages_spec.rb` inside the `describe "layout"` block:

```ruby
it "displays the site logo SVG in the header" do
  visit root_path
  within("header nav") do
    expect(page).to have_css("svg[aria-hidden='true']")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/static_pages_spec.rb -e "displays the site logo SVG in the header"`

Expected: FAIL — no SVG in the header yet.

- [ ] **Step 3: Copy the site_logo partial from modelrails_agent_os**

Copy the file verbatim:

```bash
cp /Users/dschmura/Documents/code/modelrails_agent_os/app/views/shared/_site_logo.html.erb \
   app/views/shared/_site_logo.html.erb
```

Then make two changes:

1. Change `t('app_name')` to `t('application.name')` (this project's i18n convention)
2. Change the default `name_class` from `"text-xl font-bold text-slate-900"` to `"text-xl font-bold text-slate-900 dark:text-gray-100"` (this project's dark mode convention)

The strict locals line should read:

```erb
<%# locals: (size: :medium, color_class: "text-sky-700", show_name: false, name_class: "text-xl font-bold text-slate-900 dark:text-gray-100") %>
```

The full SVG content (3 geometric path elements inside nested `<g>` transforms) must be preserved exactly from the source file.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_site_logo.html.erb spec/system/static_pages_spec.rb
git commit -m "feat(ui): Add site logo partial with inline SVG and configurable options"
```

---

### Task 2: Update the header to use the logo partial

**Files:**
- Modify: `app/views/shared/_header.html.erb:6-8`
- Modify: `spec/system/static_pages_spec.rb`

**Existing test to watch:** `spec/system/static_pages_spec.rb:39` — "navigation contains the app name as home link" uses `have_link(I18n.t("application.name"))`. This should still pass after the change because the link text comes from the `<span>` inside the block link. Verify this explicitly in Step 4.

- [ ] **Step 1: Replace the plain text link with the logo partial**

In `app/views/shared/_header.html.erb`, replace lines 6-8:

```erb
<%= link_to t("application.name"), main_app.root_path,
      class: "text-lg font-bold text-slate-900 dark:text-gray-100
              focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" %>
```

With:

```erb
<%= link_to main_app.root_path,
      class: "flex items-center gap-2 hover:opacity-80 transition-opacity
              focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" do %>
  <%= render "shared/site_logo", size: :small, show_name: true %>
<% end %>
```

- [ ] **Step 2: Run tests to verify both old and new pass**

Run: `bundle exec rspec spec/system/static_pages_spec.rb`

Expected: ALL pass, including the existing "navigation contains the app name as home link" test at line 39 and the new "displays the site logo SVG in the header" test.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_header.html.erb
git commit -m "feat(ui): Replace plain text brand with logo mark in header"
```

---

### Task 3: Update the footer to use the logo partial

**Files:**
- Modify: `app/views/shared/_footer.html.erb`
- Modify: `spec/system/static_pages_spec.rb`

- [ ] **Step 1: Write the failing system test**

Add to `spec/system/static_pages_spec.rb` inside the `describe "layout"` block:

```ruby
it "displays the site logo in the footer" do
  visit root_path
  within("footer") do
    expect(page).to have_css("svg[aria-hidden='true']")
    expect(page).to have_text(I18n.t("application.name"))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/static_pages_spec.rb -e "displays the site logo in the footer"`

Expected: FAIL — no SVG in footer yet.

- [ ] **Step 3: Add the logo to the footer**

In `app/views/shared/_footer.html.erb`, the current structure is:

```erb
<div class="flex flex-col sm:flex-row items-center justify-between gap-4">  ← outer wrapper (line 3)
  <div class="flex items-center gap-6">                                      ← links container (line 4)
    <%# ... footer links ... %>
  </div>
  <p><%# copyright %></p>
</div>
```

Replace the **inner** `<div class="flex items-center gap-6">` and its contents (lines 4-20) with:

```erb
<div class="flex flex-col sm:flex-row sm:items-center gap-6">
  <%= link_to main_app.root_path,
        class: "hover:opacity-80 transition-opacity
                focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" do %>
    <%= render "shared/site_logo",
      size: :small,
      color_class: "text-slate-600 dark:text-sky-400",
      show_name: true,
      name_class: "text-base font-semibold text-slate-700 dark:text-white" %>
  <% end %>

  <div class="flex items-center gap-6">
    <%= link_to t("footer.about"), main_app.about_path,
          class: "text-sm text-slate-600 dark:text-gray-400
                  hover:text-sky-700 dark:hover:text-sky-400
                  focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" %>
    <%= link_to t("footer.privacy"), main_app.privacy_path,
          class: "text-sm text-slate-600 dark:text-gray-400
                  hover:text-sky-700 dark:hover:text-sky-400
                  focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" %>
    <%= link_to t("footer.contact"), main_app.contact_path,
          class: "text-sm text-slate-600 dark:text-gray-400
                  hover:text-sky-700 dark:hover:text-sky-400
                  focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" %>
    <%= link_to t("footer.docs"), "/docs",
          class: "text-sm text-slate-600 dark:text-gray-400
                  hover:text-sky-700 dark:hover:text-sky-400
                  focus:outline-none focus:ring-2 focus:ring-sky-700 rounded" %>
  </div>
</div>
```

**Color rationale (WCAG AAA):**
- Light mode: `text-slate-600` logo mark on `bg-gray-50` = 5.9:1 contrast (AAA large text). `text-slate-700` name on `bg-gray-50` = 8.2:1 (AAA all text).
- Dark mode: `text-sky-400` logo mark is decorative (`aria-hidden`). `text-white` name on `bg-gray-800` = 12.6:1 (AAA).

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/system/static_pages_spec.rb -e "displays the site logo in the footer"`

Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `bundle exec rspec`

Expected: All specs pass, no regressions.

- [ ] **Step 6: Commit**

```bash
git add app/views/shared/_footer.html.erb spec/system/static_pages_spec.rb
git commit -m "feat(ui): Add logo mark to footer with mode-aware colors"
```
