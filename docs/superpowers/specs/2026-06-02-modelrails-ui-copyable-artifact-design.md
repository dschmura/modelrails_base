# Design: modelrails_ui copyable artifact — Lookbook teaches what you paste

**Date:** 2026-06-02
**Status:** Proposed (design approved in brainstorming; pending written-spec review)
**Parent arc:** [modelrails_ui component system](../../design/2026-06-01-modelrails-ui-component-system.md)
**Repo scope:** prototype in `modelrails_base` (reference app); port to the `modelrails_ui` gem templates as a follow-on

## Why this, why now

An 8-expert design panel (shadcn registry, design-system-as-product, package-manager propagation, ViewComponent/Rails, codemod, i18n, accessibility) reviewed the component system's consumption + propagation model. The strongest, most unanimous finding **relocated the critical path off SP4 (the propagation engine) and onto a more basic gap: Lookbook teaches the wrong copyable artifact.**

Concretely, two defects:

1. **Wrong language.** Lookbook's Source tab shows preview-authoring Ruby (`ui :dialog, title: … do |d| d.with_trigger { tag.button(…) }; "body" end`) — not the view-native ERB a developer pastes into a template.
2. **Incomplete artifact.** The prescribed `shared/_modal` partial is surface-only (`wrapper: false`); pasted alone it renders a `<dialog>` with no trigger and no focus-trap wrapper — it cannot open. There is no single clean, complete, copy-paste snippet for a working dialog.

Propagating a confusing interface (SP4) only spreads the confusion. Fix the artifact first.

## Goal

For each component, Lookbook presents **one complete, view-native ERB snippet that a developer copies and it works** — accessible and on-brand by construction. The dialog is the exemplar (it has the worst gap); the pattern then extends to the other five components and ports to the gem.

## Decisions carried from the panel

- **Consumption model: hybrid, library-first** (unanimous). Developers copy a *call* to a centralized vendored component; directly editing the vendored implementation is an escape hatch, not the default. The partial / helper / `ui` facade is the public API; the component class is an implementation detail.
- **Lookbook copyable mechanism: template-backed previews.** Scenario bodies become `.html.erb` files so the Source tab shows the actual view ERB. Teaching notes (overview / use-when / don't-use-when / a11y contract / "Don't") stay in the preview class doc-comment.
- **Accessibility stays correct-by-construction at the component boundary.** The focus-trap, `role`/`aria-modal`/`aria-labelledby`, and the i18n'd close button live in `UI::DialogComponent`. The copyable artifact must include the wrapper so the focus-trap is never silently dropped — the panel's accessibility seat called surface-only-by-default a "footgun."
- **Out of scope here (deferred to their own passes):** the SP4 propagation engine, gem-namespaced fallback locales + missing-key checks, per-component a11y behavioral specs, and the hardcoded-string/color cops. The cops' value is conditional on ownership becoming common; staying library-first keeps them deferred.

## Design

### 1. Self-contained dialog via one partial + optional `trigger:`

`UI::DialogComponent` already supports a self-contained mode: `wrapper: true` (its default) renders `<div data-controller="modal" class="inline">` wrapping a `trigger` slot (auto-wired with `data-action="click->modal#open"`) and the `<dialog>`. Today `shared/_modal` deliberately passes `wrapper: false` for the three existing call sites that own their wrapper.

The fix exposes the self-contained mode as clean ERB by giving `shared/_modal` an optional `trigger:` local:

- **`trigger:` present** → render the component with `wrapper: true`, filling the `trigger` slot with a button (`trigger_class:` for styling, default `btn-secondary`). This is the complete, copyable artifact.
- **`trigger:` omitted** → current `wrapper: false` surface-only behavior. The three existing callers pass no `trigger:` and are untouched. **Non-breaking, single file.**

Sketch (final shape decided in the plan):

```erb
<%# locals: (title:, id: nil, size: :md, description: nil, trigger: nil, trigger_class: "btn-secondary") -%>
<% if trigger.present? %>
  <%= render UI::DialogComponent.new(title: title, id: id, size: size,
        description: description, wrapper: true, body_id: "modal-body") do |d| %>
    <% d.with_trigger do %>
      <%= tag.button(trigger, type: "button", class: trigger_class) %>
    <% end %>
    <%= yield %>
  <% end %>
<% else %>
  <%= render UI::DialogComponent.new(title: title, id: id, size: size,
        description: description, wrapper: false, body_id: "modal-body") do %><%= yield %><% end %>
<% end %>
```

The taught, copyable snippet a developer pastes becomes:

```erb
<%= render "shared/modal", title: "Confirm deletion", trigger: "Delete", trigger_class: "btn-danger" do %>
  <p>This can't be undone.</p>
<% end %>
```

For a custom, non-button trigger (an icon, a link), the developer drops to the surface-only mode (omit `trigger:`, supply their own `data-controller="modal"` wrapper + trigger) — the documented "full control" path.

**Open detail for the plan:** `body_id: "modal-body"` is a fixed id preserving the Turbo Stream append contract (`turbo_stream.append "modal-body"`). A page rendering multiple complete modals would collide on it. The plan decides whether complete mode (a) keeps the fixed id with a documented single-target caveat, or (b) defaults `body_id` to the component's unique id and treats `"modal-body"` as opt-in for the stream-target case.

### 2. Template-backed Lookbook preview for the dialog

Convert `spec/components/previews/ui/dialog_component_preview.rb` from inline `ui :dialog` render methods to template-backed scenarios (`.html.erb` files Lookbook renders, whose source it displays). Scenarios:

- **Basic** — trigger + title + body + a footer with cancel/confirm.
- **With form** — `form_with` + `f.text_field` inside the dialog (the edit-modal pattern).
- **Confirm (destructive)** — via `shared/_confirm_dialog`.
- **Don't · no title** — preserved as the misuse example (kept in the doc-comment / a labeled scenario).

Each scenario's Source tab shows the complete view-native ERB above. The class doc-comment keeps the teaching notes and the a11y contract.

## Testing strategy (TDD)

- **Partial behavior (request/system spec):** with `trigger:`, the rendered output contains the `data-controller="modal"` wrapper, a trigger button with `data-action="click->modal#open"`, and the `<dialog>`; without `trigger:`, output is the surface-only `<dialog>` (the three existing callers' contract is unchanged).
- **Accessibility:** a system spec opens the complete dialog via its trigger, asserts focus moves into the dialog and Escape closes it (behavior axe cannot see), and the existing axe `wcag2aaa` gate stays green in both themes.
- **Lookbook renders:** each template-backed scenario renders without error (the preview is exercised by the suite / a smoke spec).
- **Assertions parse rendered HTML with Nokogiri/Capybara matchers, not regex against `response.body`** (avoids source-scanning false positives — see prior guidance).

## Rollout

1. **This prototype (app-side, dialog-first):** the `shared/_modal` `trigger:` change + the template-backed dialog preview + specs, validated live in `/lookbook`.
2. **Extend (follow-on):** apply the template-backed-ERB + complete-artifact pattern to button, input, textarea, file_input, avatar (each has its own prescribed call: `f.text_field` via the form builder, `avatar_for`, `ui :button`).
3. **Port to the gem (follow-on):** move the validated preview templates + any partial change into the `modelrails_ui` generator `.tt` templates so new and updating apps get it. (Needs the gem working clone, which is not on this machine yet.)

## Open questions / risks

- **`body_id` collision** in complete mode with multiple modals per page (see plan detail above).
- **Template-backed previews + form context:** the "with form" scenario needs a throwaway model/`form_with` in the preview template; confirm Lookbook renders it cleanly under the app's CSP and form builder.
- **Trigger flexibility:** `trigger:`-as-text covers the common button; richer triggers use the surface-only path. Confirm that split reads clearly in the catalog.
- **Gem port fidelity:** vendored parity is semantic, not byte-identical — the gem template output is normalized by each app's RuboCop (see the parent design doc), so the port must not assume byte-identical output.
