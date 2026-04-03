# TailwindFormBuilder Phase 1 — Design Spec

## Problem

All 21 forms in the app use Rails default `form_with` with manually applied Tailwind classes. This creates inconsistency: 12 forms have error handling, 9 don't. No forms have `aria-describedby`, `aria-invalid`, or `aria-required`. Labels, help text, and error messages are manually wired. Every new form requires copying the same CSS classes and error-handling boilerplate.

## Solution

A custom `TailwindFormBuilder` that wraps every field with consistent styling, labels, help text, inline errors, and WCAG AAA accessibility attributes. Drop-in replacement — add `builder: TailwindFormBuilder` to `form_with`.

## Design Decisions

### Why a form builder subclass?

Rails form builders are the standard extension point for this. The builder intercepts every field method (`text_field`, `email_field`, etc.), wraps it with consistent HTML structure, and returns the complete markup. No view-level boilerplate needed. This is the same pattern used by Simple Form, Formtastic, and the agent_os project.

### Why semantic tokens in frozen constants?

The form builder uses frozen string constants for CSS classes (`TEXT_FIELD_CLASSES`, `LABEL_CLASSES`, etc.) that reference semantic design tokens (`text-text-body`, `bg-surface-raised`, `focus:ring-interactive-focus`). When a downstream project changes the token values in `_semantic.css` or `_primitives.css`, all form styling updates automatically. No form-specific configuration layer needed — the token system handles theming.

### Why both error summary and inline errors?

Error summary gives users an overview ("3 errors with your submission") and serves as a landmark for screen readers. Inline errors show exactly what's wrong next to each field. Both together follow the RE:FORM methodology and WCAG guidance. The builder provides both — developers include `error_summary` at the top and inline errors render automatically.

## Architecture

### TailwindFormBuilder (`app/form_builders/tailwind_form_builder.rb`)

Subclass of `ActionView::Helpers::FormBuilder`.

**CSS class constants:**

```ruby
TEXT_FIELD_CLASSES = "block w-full rounded-md border border-border-strong bg-surface-raised px-3 py-2 text-text-heading placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-interactive-focus min-h-[44px]"

ERROR_FIELD_CLASSES = "ring-2 ring-danger bg-danger-surface text-danger"

LABEL_CLASSES = "block text-sm font-medium text-text-body"

ERROR_LABEL_CLASSES = "text-danger"

HELP_TEXT_CLASSES = "text-sm text-text-muted"

ERROR_MESSAGE_CLASSES = "text-sm text-danger"

SUBMIT_CLASSES = "min-h-[44px] inline-flex items-center justify-center px-4 rounded-md bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus cursor-pointer"

CHECKBOX_CLASSES = "size-5 rounded border-border-strong text-interactive focus:ring-2 focus:ring-interactive-focus"

FILE_FIELD_CLASSES = "block w-full text-sm text-text-body file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-interactive file:text-text-on-interactive hover:file:bg-interactive-hover file:cursor-pointer file:min-h-[44px]"
```

**Field methods (all override parent):**

| Method | Custom behavior |
| ------ | --------------- |
| `text_field` | Wraps in field_wrapper with label, help, error |
| `email_field` | Same wrapper |
| `password_field` | Same wrapper, default `autocomplete: "new-password"` |
| `url_field` | Same wrapper |
| `tel_field` | Same wrapper |
| `number_field` | Same wrapper |
| `date_field` | Same wrapper |
| `search_field` | Same wrapper |
| `text_area` | Same wrapper, default `rows: 4` |
| `select` | Same wrapper, select-specific styling |
| `check_box` | Checkbox wrapper (label to the right) |
| `collection_check_boxes` | Fieldset wrapper with legend |
| `collection_radio_buttons` | Fieldset wrapper with legend |
| `file_field` | Same wrapper, file-specific styling |
| `submit` | Button with submit styling, no wrapper |
| `error_summary` | Top-of-form error banner |

**Private helper methods:**

| Method | Purpose |
| ------ | ------- |
| `field_wrapper(method, options, &block)` | Renders div > label > help > field > error |
| `checkbox_wrapper(method, options, &block)` | Renders div > (checkbox + label side by side) > error |
| `collection_wrapper(method, options, &block)` | Renders fieldset > legend > items > error |
| `field_label(method, options)` | Label with `for`, required indicator |
| `field_help(method, options)` | Help text paragraph with ID |
| `field_error(method)` | Error message with `role="alert"` and ID |
| `has_errors?(method)` | Checks `object.errors[method].any?` |
| `field_classes(method, base)` | Merges base classes with error classes when applicable |
| `aria_attributes(method, options)` | Builds `aria-required`, `aria-invalid`, `aria-describedby` |

### Field wrapper HTML structure

Standard field (text, email, password, etc.):

```html
<div class="space-y-2">
  <label for="user_email" class="block text-sm font-medium text-text-body">
    Email <span class="text-danger">*</span>
  </label>
  <p id="user_email-help" class="text-sm text-text-muted">We'll never share your email.</p>
  <input id="user_email" name="user[email]" type="email"
         class="block w-full rounded-md border border-border-strong bg-surface-raised px-3 py-2 text-text-heading placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-interactive-focus min-h-[44px]"
         aria-describedby="user_email-help"
         aria-required="true" />
</div>
```

Field with error:

```html
<div class="space-y-2">
  <label for="user_email" class="block text-sm font-medium text-danger">
    Email <span class="text-danger">*</span>
  </label>
  <input id="user_email" name="user[email]" type="email"
         class="block w-full rounded-md border border-border-strong bg-surface-raised px-3 py-2 text-text-heading placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-interactive-focus min-h-[44px] ring-2 ring-danger bg-danger-surface text-danger"
         aria-describedby="user_email-error"
         aria-required="true"
         aria-invalid="true" />
  <p id="user_email-error" role="alert" class="text-sm text-danger">has already been taken</p>
</div>
```

Checkbox:

```html
<div class="flex items-start gap-3">
  <input id="invitation_magic_link" name="invitation[magic_link]" type="checkbox"
         class="size-5 rounded border-border-strong text-interactive focus:ring-2 focus:ring-interactive-focus mt-0.5" />
  <label for="invitation_magic_link" class="text-sm text-text-body">
    Send magic link instead of email invitation
  </label>
</div>
```

Collection (radio/checkbox group):

```html
<fieldset class="space-y-2">
  <legend class="block text-sm font-medium text-text-body">Role</legend>
  <div class="space-y-2">
    <div class="flex items-center gap-3">
      <input type="radio" ... />
      <label ...>Admin</label>
    </div>
    <div class="flex items-center gap-3">
      <input type="radio" ... />
      <label ...>Member</label>
    </div>
  </div>
</fieldset>
```

### Error summary

```html
<div role="alert" class="rounded-lg border border-danger-border bg-danger-surface p-4">
  <div class="flex items-start gap-3">
    <svg class="size-5 text-danger-icon shrink-0 mt-0.5" ...><!-- exclamation circle --></svg>
    <div>
      <h2 class="text-sm font-semibold text-danger">2 errors prevented this form from being saved</h2>
      <ul class="mt-2 list-disc list-inside text-sm text-danger">
        <li>Email has already been taken</li>
        <li>Password is too short (minimum is 12 characters)</li>
      </ul>
    </div>
  </div>
</div>
```

Uses the `icon()` helper for the error icon.

### Usage in views

```erb
<%= form_with model: @user, builder: TailwindFormBuilder, class: "space-y-6" do |f| %>
  <%= f.error_summary %>

  <%= f.text_field :first_name, label: t(".first_name"), required: true %>
  <%= f.text_field :last_name, label: t(".last_name"), required: true %>
  <%= f.email_field :email_address, label: t(".email"), required: true,
                    help: t(".email_help") %>
  <%= f.password_field :password, label: t(".password"), required: true %>

  <%= f.submit t(".save") %>
<% end %>
```

**Options accepted by all field methods:**

| Option | Type | Purpose |
| ------ | ---- | ------- |
| `label:` | String | Custom label text (defaults to humanized method name) |
| `required:` | Boolean | Adds `aria-required`, required indicator on label |
| `help:` | String | Help text below label, linked via `aria-describedby` |
| `class:` | String | Additional CSS classes merged with defaults |

### Default form builder registration

Set `TailwindFormBuilder` as the default so existing `form_with` calls use it without adding `builder:` explicitly:

```ruby
# config/initializers/form_builder.rb
ActionView::Base.default_form_builder = TailwindFormBuilder
```

This means all 21 existing forms get the new builder automatically. Forms that pass custom classes to fields will need those classes removed since the builder provides them.

### Form migration

After the builder is registered as default, existing forms need cleanup:

- Remove manually applied CSS classes from field helpers (the builder provides them)
- Remove manual error handling blocks (`if @object.errors.any?`) — replace with `f.error_summary`
- Add `label:` and `required:` options where needed
- Add `help:` text where appropriate
- Remove manual `<label>` tags (builder generates them)

## Accessibility (WCAG AAA)

- `aria-required="true"` on all required fields
- `aria-invalid="true"` on fields with validation errors
- `aria-describedby` links fields to help text IDs and error message IDs (space-separated when both present)
- Labels use `for` attribute matching field `id`
- Required indicator: red `*` (visual) plus `aria-required` (semantic)
- Error messages use `role="alert"` for immediate screen reader announcement
- Error indication is not color-only: ring border + background tint + text color + icon in summary
- 44px minimum touch targets on all inputs, checkboxes, and submit buttons
- Contrast ratios met via semantic tokens (7:1 AAA)
- Error summary provides error count for screen readers before individual fields

## Files

| File | Action | Purpose |
| ---- | ------ | ------- |
| `app/form_builders/tailwind_form_builder.rb` | Create | The form builder class |
| `config/initializers/form_builder.rb` | Create | Register as default builder |
| `spec/form_builders/tailwind_form_builder_spec.rb` | Create | Field type and wrapper specs |
| `spec/form_builders/tailwind_form_builder_accessibility_spec.rb` | Create | ARIA and accessibility specs |
| All 21 form views | Modify | Migrate to use builder conventions |

## Testing Strategy

**Unit specs (form builder):**

- Every field type renders correct input element with correct classes
- Label renders with `for` attribute and correct text
- Required indicator appears when `required: true`
- Help text renders with correct ID, linked via `aria-describedby`
- Error state: inline error with `role="alert"`, `aria-invalid`, error classes
- Error summary renders with count, icon, bulleted list
- Custom `class:` option merges with defaults
- Checkbox/radio use correct wrapper structure
- Submit button has correct classes

**Accessibility specs:**

- `aria-required` present when required
- `aria-invalid` present when errors exist
- `aria-describedby` links to help text ID when help present
- `aria-describedby` links to error ID when error present
- `aria-describedby` links to both when both present
- Labels have `for` matching input `id`
- Error messages have `role="alert"`
- Required indicator text present in label

**System specs:**

- Existing form flows still work after migration (login, registration, profile edit, workspace create)
- Error display works end-to-end (submit invalid form, see inline errors + summary)

## Out of Scope (Phase 2)

- Password field with show/hide toggle
- Form validation Stimulus controller (HTML5 + server-side)
- Form change tracking controller (dirty state, unsaved changes warning)
- Rich text area integration
- Inline form close controller
