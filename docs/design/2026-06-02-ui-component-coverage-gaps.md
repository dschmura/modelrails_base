# UI Component Coverage — Gaps and Next-Milestone Candidates

**Date:** 2026-06-02
**Status:** Reference / roadmap input
**Related:** [modelrails_ui component system](2026-06-01-modelrails-ui-component-system.md)

## Context

The `UI::*` component catalog is **six primitives**: `button`, `input`, `textarea`, `file_input`, `avatar`, `dialog`. A UI coverage audit of modelrails_base found ~40 distinct UI patterns in use, so the catalog covers a minority of the app's surface.

That is **partly by design.** Per `CLAUDE.md`, "ViewComponents only when reused across unrelated views" and "partials with strict locals for simple wrappers." A small component set plus many app-specific partials is the project's deliberate stance — so the question is not "componentize everything," it is "where is there genuine inconsistency or duplication worth closing."

## Three buckets

| Bucket | Examples | Verdict |
|---|---|---|
| **`UI::*` component** | input, textarea, file_input, button, avatar, dialog | The primitives |
| **Abstracted as partial/helper** | toast (pill + card), flash, header nav, user menu, settings/workspace sidebars, pagination, cards (`_section`/`_feature_card`/`_preferences_card`), empty-state, activity feed, `icon` helper, identity picker, theme toggle | **Fine as-is** — not gaps; componentizing would fight the "partials for app-specific UI" guideline |
| **Genuine gap** | form controls (select, checkbox, radio, submit), badge/status pill, raw tables, alert banners | **Worth closing** |

## Genuine gaps, prioritized

1. **Form-control suite completion (highest value).** `TailwindFormBuilder` routes `text_field`/`text_area`/`file_field` to `UI::*` components, but renders **select, checkbox, radio, and submit as raw HTML / class strings** (`CHECKBOX_CLASSES`, `SUBMIT_CLASSES`). A developer building a form gets a component for the text field and bare markup for the dropdown beside it. Add `UI::SelectComponent`, `UI::CheckboxComponent`, `UI::RadioButtonComponent`, and route `f.submit` → `UI::ButtonComponent`. This makes the builder's promise (every field accessible + on-brand by construction) true for *all* field types, not 3 of 7.
2. **`UI::BadgeComponent` (highest ad-hoc duplication).** Role/status badges in the members table, the header notification count, severity colors in toasts — all inline Tailwind, repeated, no abstraction. High-frequency, high-duplication; a badge component unifies status display and cuts Tailwind coupling.
3. **`UI::TableComponent` (secondary).** The members list is raw `<table>` + a `_row` partial; the pattern will repeat for projects/admin lists. A table component enables consistent sorting/pagination/empty-state.
4. **`UI::AlertComponent` (secondary).** Persistent notification/banner UI (settings, account, migration banner) is distinct from the toast system and currently ad-hoc; componentize before it duplicates further.

## Sequencing

New components belong in the `modelrails_ui` gem (the two-layer model — gem source, app consumer). Therefore:

- **Finish the current pipeline first** — merge the copyable-artifact PRs (#219, #220) and port them into the gem templates — before adding new components, so you are not porting a moving target.
- **Recommended next milestone (after the port):** complete the **form-control suite** (select → checkbox → radio → submit-delegation), then **badge**. Each new component follows the established pattern: harden the API (fail-loud on bad input), ship a template-backed Lookbook teaching scenario, bake a11y + i18n in.

## Caveat

The audit was a read-only exploration pass (excerpts, not exhaustive), so pattern counts are approximate. The load-bearing claim — that select/checkbox/radio/submit have no `UI::*` component — is verified by their absence in `app/components/ui/`.
