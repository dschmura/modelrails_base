# Copyable Dialog Artifact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Lookbook teach one complete, copy-paste-able view-native ERB snippet for the dialog — a single `render "shared/modal", …, trigger:` call that renders a working, accessible modal — and prove it with specs.

**Architecture:** Give `app/views/shared/_modal.html.erb` an optional `trigger:` local. When present it renders the self-contained `wrapper + trigger + <dialog>` via the existing `UI::DialogComponent` (`wrapper: true` + its `trigger` slot); when absent it keeps today's surface-only behavior (the 3 existing callers are untouched). Convert the dialog Lookbook preview to template-backed `.html.erb` scenarios so the Source tab shows the copyable ERB. Host behavior/a11y specs on the ViewComponent previews controller (enabled in test).

**Tech Stack:** Rails 8.1, ViewComponent 4, Lookbook 2.3, RSpec + Capybara/Playwright, axe-core (`wcag2aaa`), Nokogiri. App commands run via `mise exec --`.

**Design doc:** `docs/superpowers/specs/2026-06-02-modelrails-ui-copyable-artifact-design.md`

**body_id decision (was open in the design):** surface mode keeps the fixed `body_id: "modal-body"` (preserves the existing `turbo_stream.append "modal-body"` contract for the 3 callers); complete mode omits `body_id` so the component's unique default is used (no collision when a page has multiple complete modals).

**Scope:** dialog exemplar only. The other five components and the gem-template port are explicit follow-ons, NOT in this plan.

**Toolchain note:** single-file `rspec` runs trip the SimpleCov 40% floor and exit non-zero — judge pass/fail by the `N examples, M failures` line, not the exit code.

---

### Task 1: Enable ViewComponent previews in the test environment

Behavior/a11y specs need a server-rendered host page with JS. Lookbook is dev-only, but ViewComponent's previews controller (`/rails/view_components/…`) works in test once preview paths are registered there.

**Files:**

- Modify: `config/initializers/modelrails_ui_lookbook.rb`
- Test: `spec/requests/view_component_previews_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/view_component_previews_spec.rb
require "rails_helper"

RSpec.describe "ViewComponent previews (test host)", type: :request do
  it "serves an existing component preview" do
    get "/rails/view_components/ui/button_component_preview/default"
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mise exec -- bundle exec rspec spec/requests/view_component_previews_spec.rb`
Expected: FAIL — routing error / 404 (preview paths not registered in test).

- [ ] **Step 3: Register preview paths in test (and keep Lookbook dev-only)**

Edit `config/initializers/modelrails_ui_lookbook.rb` so the ViewComponent preview config also runs in test; the Lookbook *engine* config stays development-only:

```ruby
# frozen_string_literal: true

# Lookbook — interactive component explorer / living docs for modelrails_ui (dev-only).
# Mounted at /lookbook (see config/routes.rb). Previews live in spec/components/previews.
# ViewComponent 4 nests preview config under `previews`.
#
# ViewComponent's own previews controller (/rails/view_components) is enabled in
# development AND test so system/request specs can render previews as host pages.
# The Lookbook engine itself stays development-only (see config/routes.rb).
if Rails.env.development? || Rails.env.test?
  vc = Rails.application.config.view_component
  preview_dir = Rails.root.join("spec/components/previews").to_s
  vc.previews.paths = Array(vc.previews.paths) | [ preview_dir ]
  vc.previews.default_layout = "component_preview"

  Rails.application.config.lookbook.preview_paths = [ preview_dir ] if Rails.env.development?
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mise exec -- bundle exec rspec spec/requests/view_component_previews_spec.rb`
Expected: `1 example, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add config/initializers/modelrails_ui_lookbook.rb spec/requests/view_component_previews_spec.rb
git commit -m "test(ui): serve ViewComponent previews in test env as a spec host"
```

---

### Task 2: Complete-mode dialog via `trigger:` + the `basic` template (the copyable artifact)

**Files:**

- Modify: `app/views/shared/_modal.html.erb`
- Create: `spec/components/previews/ui/dialog_component_preview/basic.html.erb`
- Modify: `spec/components/previews/ui/dialog_component_preview.rb`
- Test: `spec/requests/dialog_copyable_artifact_spec.rb` (create)
- Verify keys: `config/locales/*` (`modals.cancel` exists; `modals.confirm` may need adding)

- [ ] **Step 1: Confirm/add the locale keys the artifact uses**

Run: `mise exec -- bin/rails runner 'puts [I18n.t("modals.cancel", default: "MISSING"), I18n.t("modals.confirm", default: "MISSING")].inspect'`
If `modals.confirm` prints `"MISSING"`, add it under the same file/namespace as `modals.cancel` (find it with `grep -rn "cancel:" config/locales | grep -i modal`), e.g.:

```yaml
# config/locales/<the file with modals:> — add alongside cancel:
    modals:
      confirm: "Confirm"
```

- [ ] **Step 2: Add the `basic` scenario template (the copyable ERB)**

```erb
<%# spec/components/previews/ui/dialog_component_preview/basic.html.erb %>
<%# The complete, copy-paste dialog: trigger + focus-trapped modal + footer actions. %>
<%= render "shared/modal",
      title: "Confirm action",
      description: "This action cannot be undone.",
      trigger: "Open dialog",
      trigger_class: "btn-primary" do %>
  <p class="text-text-body leading-relaxed">
    Are you sure you want to proceed? All related data will be permanently removed.
  </p>

  <div class="flex gap-3 justify-end mt-6 pt-4 border-t border-border">
    <button type="button" data-action="click->modal#close" class="btn-secondary">
      <%= t("modals.cancel") %>
    </button>
    <button type="button" class="btn-primary">
      <%= t("modals.confirm") %>
    </button>
  </div>
<% end %>
```

- [ ] **Step 3: Point the preview at the template (template-backed)**

In `spec/components/previews/ui/dialog_component_preview.rb`, keep the class doc-comment teaching notes, and replace the inline `default` method with an empty template-backed `basic` method:

```ruby
    # Renders spec/components/previews/ui/dialog_component_preview/basic.html.erb —
    # the complete, copy-paste snippet shown in Lookbook's Source tab.
    def basic; end
```

(Leave `large` and `dont_no_title` as-is for now; Task 4 converts them.)

- [ ] **Step 4: Write the failing structure test**

```ruby
# spec/requests/dialog_copyable_artifact_spec.rb
require "rails_helper"

RSpec.describe "Dialog copyable artifact", type: :request do
  it "renders a complete, self-contained dialog (wrapper + trigger + dialog)" do
    get "/rails/view_components/ui/dialog_component/basic"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    wrapper = doc.at_css('[data-controller="modal"]')
    expect(wrapper).to be_present, "expected a data-controller=\"modal\" wrapper"

    trigger = wrapper.at_css("button")
    expect(trigger.text).to include("Open dialog")
    # the component wires the open action on the slot wrapper:
    expect(wrapper.at_css('[data-action*="modal#open"]')).to be_present

    dialog = wrapper.at_css('dialog[role="dialog"]')
    expect(dialog["aria-modal"]).to eq("true")
    expect(dialog["aria-labelledby"]).to be_present
  end
end
```

- [ ] **Step 5: Run it to verify it fails**

Run: `mise exec -- bundle exec rspec spec/requests/dialog_copyable_artifact_spec.rb`
Expected: FAIL — strict-locals on `shared/_modal` raises on the undeclared `trigger:` local (the partial doesn't accept it yet).

- [ ] **Step 6: Implement the `trigger:` complete mode in the partial**

Replace `app/views/shared/_modal.html.erb` with:

```erb
<%# locals: (title:, id: nil, size: :md, description: nil, trigger: nil, trigger_class: "btn-secondary") -%>
<%#
  Thin adapter over UI::DialogComponent.

  Surface-only (default, no trigger:): renders ONLY the <dialog> (wrapper: false).
  Callers own the surrounding data-controller="modal" wrapper + trigger button.
  body_id stays "modal-body" to preserve the Turbo Stream contract
  (turbo_stream.append "modal-body"). Existing call sites are unchanged.

  Complete (pass trigger:): renders the data-controller="modal" wrapper + a trigger
  button + the <dialog> as one copy-paste unit (wrapper: true). body_id uses the
  component's unique default so multiple complete modals on a page don't collide.
-%>
<% if trigger.present? %>
  <%= render UI::DialogComponent.new(
        title: title, id: id, size: size, description: description, wrapper: true) do |d| %>
    <% d.with_trigger do %>
      <%= tag.button(trigger, type: "button", class: trigger_class) %>
    <% end %>
    <%= yield %>
  <% end %>
<% else %>
  <%= render UI::DialogComponent.new(
        title: title, id: id, size: size, description: description,
        wrapper: false, body_id: "modal-body") do %><%= yield %><% end %>
<% end %>
```

- [ ] **Step 7: Run it to verify it passes**

Run: `mise exec -- bundle exec rspec spec/requests/dialog_copyable_artifact_spec.rb`
Expected: `1 example, 0 failures`.

- [ ] **Step 8: Verify the 3 existing surface-only callers are unchanged**

Run: `mise exec -- bundle exec rspec spec/system/identity_picker_spec.rb spec/system/workspaces_spec.rb 2>&1 | tail -5`
(If those exact files differ, run the system specs that exercise the identity-picker / workspace-logo / profile-picture modals.)
Expected: green — the existing callers pass no `trigger:`, hit the `else` branch, and render identically to before.

- [ ] **Step 9: Commit**

```bash
git add app/views/shared/_modal.html.erb \
        spec/components/previews/ui/dialog_component_preview.rb \
        spec/components/previews/ui/dialog_component_preview/basic.html.erb \
        spec/requests/dialog_copyable_artifact_spec.rb \
        config/locales
git commit -m "feat(ui): shared/_modal optional trigger: renders a complete copyable dialog"
```

---

### Task 3: Behavior + accessibility system spec (focus, Escape, axe both themes)

axe tests the rendered DOM but cannot test focus-trap or keyboard flow — so assert those behaviors directly, and keep the `wcag2aaa` gate green.

**Files:**

- Test: `spec/system/dialog_copyable_artifact_spec.rb` (create)

- [ ] **Step 1: Write the behavior + a11y system spec**

```ruby
# spec/system/dialog_copyable_artifact_spec.rb
require "rails_helper"

RSpec.describe "Complete dialog behavior", type: :system do
  it "opens via its trigger, traps focus, and closes on Escape — accessibly" do
    visit "/rails/view_components/ui/dialog_component/basic"

    expect(page).to have_css("dialog[open]", visible: :all, wait: 0).or have_no_css("dialog[open]")

    click_button "Open dialog"
    expect(page).to have_css("dialog[open]")

    # focus moved into the dialog
    focused_in_dialog = page.evaluate_script("document.querySelector('dialog[open]').contains(document.activeElement)")
    expect(focused_in_dialog).to be(true)

    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # reopen in case theme switching closed it, then test Escape
    click_button "Open dialog" unless page.has_css?("dialog[open]")
    page.send_keys(:escape)
    expect(page).to have_no_css("dialog[open]")
  end
end
```

- [ ] **Step 2: Run it**

Run: `mise exec -- bundle exec rspec spec/system/dialog_copyable_artifact_spec.rb`
Expected: PASS. If the axe assertion flags a real AAA issue in the preview layout (not the dialog), note it; the dialog itself bakes AAA semantics. If focus/Escape fail, the host page is missing the modal Stimulus controller — confirm `component_preview` layout loads the app JS bundle.

- [ ] **Step 3: Commit**

```bash
git add spec/system/dialog_copyable_artifact_spec.rb
git commit -m "test(ui): system spec proves complete dialog focus-trap + Escape + AAA"
```

---

### Task 4: Remaining template-backed scenarios + teaching notes

Convert the other scenarios to template-backed ERB so every Source tab shows copyable view code. Keep the rich teaching notes in the preview class doc-comment.

**Files:**

- Create: `spec/components/previews/ui/dialog_component_preview/with_form.html.erb`
- Create: `spec/components/previews/ui/dialog_component_preview/confirm_destructive.html.erb`
- Create: `spec/components/previews/ui/dialog_component_preview/dont_no_title.html.erb`
- Modify: `spec/components/previews/ui/dialog_component_preview.rb`
- Test: extend `spec/requests/dialog_copyable_artifact_spec.rb`

- [ ] **Step 1: `with_form` template (edit-modal pattern)**

```erb
<%# spec/components/previews/ui/dialog_component_preview/with_form.html.erb %>
<%= render "shared/modal", title: "Edit profile", size: :lg,
      description: "Update your display name.",
      trigger: "Edit profile", trigger_class: "btn-secondary" do %>
  <%= form_with url: "#", method: :patch do |f| %>
    <div class="mb-4">
      <%= f.text_field :name, label: "Display name" %>
    </div>
    <div class="flex gap-3 justify-end mt-6 pt-4 border-t border-border">
      <button type="button" data-action="click->modal#close" class="btn-secondary">
        <%= t("modals.cancel") %>
      </button>
      <%= f.submit t("modals.save", default: "Save"), class: "btn-primary" %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 2: Confirm which form builder the artifact needs**

The app renders form fields through a custom builder (it owns `label:` / help / error / ARIA). Confirm its constant and whether it is the app-wide default the preview controller will use:

Run: `grep -rn "default_form_builder\|FormBuilder" app/ config/ | head`

If the custom builder is NOT the app-wide default (so `f.text_field :name, label: …` would raise in the preview controller), pass it explicitly in the Step 1 template: `form_with url: "#", builder: <TheBuilderConstant>`, and adjust the template accordingly.

- [ ] **Step 3: `confirm_destructive` template (uses the confirm partial)**

```erb
<%# spec/components/previews/ui/dialog_component_preview/confirm_destructive.html.erb %>
<%# Destructive confirmation: wrapper + trigger around the prebuilt confirm body. %>
<div data-controller="modal" class="inline">
  <button type="button" data-action="click->modal#open" class="btn-danger">Delete project</button>

  <%= render "shared/confirm_dialog",
        title: "Delete project",
        message: "This cannot be undone. All related data will be permanently removed.",
        confirm_text: t("modals.delete", default: "Delete"),
        confirm_url: "#",
        confirm_method: :delete,
        variant: :danger %>
</div>
```

- [ ] **Step 4: `dont_no_title` template (the labeled "Don't")**

```erb
<%# spec/components/previews/ui/dialog_component_preview/dont_no_title.html.erb %>
<%# ✗ A vague title gives screen-reader users no context via aria-labelledby. %>
<%= render "shared/modal", title: "Untitled", trigger: "Open", trigger_class: "btn-secondary" do %>
  Body content.
<% end %>
```

- [ ] **Step 5: Make the preview methods template-backed + keep notes**

```ruby
    def with_form; end

    def confirm_destructive; end

    # @label Don't · no title (breaks aria-labelledby)
    def dont_no_title; end
```

Delete the old inline `large` method (replaced by `with_form`); `default` was already replaced by `basic` in Task 2. Keep the class-level doc-comment (overview / use-when / don't-use-when / a11y contract).

- [ ] **Step 6: Smoke test each scenario renders**

Add to `spec/requests/dialog_copyable_artifact_spec.rb`:

```ruby
  %w[basic with_form confirm_destructive dont_no_title].each do |scenario|
    it "renders the #{scenario} preview scenario" do
      get "/rails/view_components/ui/dialog_component/#{scenario}"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("dialog")).to be_present
    end
  end
```

- [ ] **Step 7: Run the scenario specs**

Run: `mise exec -- bundle exec rspec spec/requests/dialog_copyable_artifact_spec.rb`
Expected: all examples pass.

- [ ] **Step 8: Commit**

```bash
git add spec/components/previews/ui/dialog_component_preview \
        spec/components/previews/ui/dialog_component_preview.rb \
        spec/requests/dialog_copyable_artifact_spec.rb
git commit -m "feat(ui): template-backed dialog previews show copyable ERB for every scenario"
```

---

### Task 5: Full-suite verification + live Lookbook check

- [ ] **Step 1: Run the full suite**

Run: `mise exec -- bundle exec rspec 2>&1 | tail -8`
Expected: `0 failures`. Investigate any failure before proceeding.

- [ ] **Step 2: Visual check in Lookbook**

Run: `mise exec -- bin/rails server` (or the project's dev command), open `http://localhost:3000/lookbook`, navigate to Dialog. Confirm for each scenario: it renders, opens on trigger click, and the **Source tab shows the view-native ERB** (the `render "shared/modal", …, trigger:` snippet) — not Ruby. This is the whole point of the change; verify it by eye.

- [ ] **Step 3: Final commit (if any tweaks)**

```bash
git add -A
git commit -m "chore(ui): polish dialog teaching catalog after live review"
```

---

## Out of scope (follow-ons)

- Apply the template-backed-ERB + complete-artifact pattern to button, input, textarea, file_input, avatar (each has its own prescribed call).
- Port the validated preview templates + the `shared/_modal` `trigger:` change into the `modelrails_ui` gem generator `.tt` templates (needs the gem working clone; honor semantic-not-byte parity).
- SP4 propagation engine; gem-namespaced fallback locales + missing-key check; the hardcoded-string/color cops (revive only if direct ownership of vendored components becomes common).
