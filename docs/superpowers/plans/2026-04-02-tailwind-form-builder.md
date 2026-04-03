# TailwindFormBuilder Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a custom TailwindFormBuilder with semantic token styling, WCAG AAA accessibility, inline errors, error summary, and migrate all 21 existing forms to use it.

**Architecture:** `TailwindFormBuilder` subclasses `ActionView::Helpers::FormBuilder`, overriding field methods to wrap inputs in consistent HTML with labels, help text, and inline errors. CSS classes use semantic design tokens (not hardcoded colors). State-dependent classes (normal vs error) are separate constants to avoid Tailwind conflicts. Registered as the default form builder via initializer.

**Tech Stack:** Rails 8.1, TailwindCSS 4 with semantic tokens, RSpec, IconHelper

**Spec:** `docs/superpowers/specs/2026-04-02-tailwind-form-builder-design.md`

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `app/form_builders/tailwind_form_builder.rb` | Create | Form builder class with all field methods |
| `config/initializers/form_builder.rb` | Create | Register as default builder |
| `spec/form_builders/tailwind_form_builder_spec.rb` | Create | Field type and wrapper specs |
| `spec/form_builders/tailwind_form_builder_accessibility_spec.rb` | Create | ARIA and accessibility specs |
| 21 form view files | Modify | Migrate to builder conventions |

---

### Task 1: Create Form Builder with Text Field (TDD)

**Files:**

- Create: `app/form_builders/tailwind_form_builder.rb`
- Create: `spec/form_builders/tailwind_form_builder_spec.rb`

- [ ] **Step 1: Write the failing specs**

Create `spec/form_builders/tailwind_form_builder_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TailwindFormBuilder do
  let(:user) { User.new }
  let(:builder) { described_class.new(:user, user, template, {}) }
  let(:template) { ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil) }

  before do
    template.class.include ActionView::Helpers::FormHelper
    template.class.include ActionView::Helpers::TagHelper
    template.class.include ActionView::Context
    template.class.include IconHelper
  end

  describe "#text_field" do
    it "renders an input with base classes" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("input[type='text'].rounded-md")
      expect(result).to have_css("input.min-h-\\[44px\\]")
    end

    it "wraps in a div with space-y-2" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("div.space-y-2")
    end

    it "generates a label from the method name" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("label[for='user_first_name']", text: "First name")
    end

    it "uses custom label text when provided" do
      result = builder.text_field(:first_name, label: "Your Name")
      expect(result).to have_css("label", text: "Your Name")
    end

    it "renders help text when provided" do
      result = builder.text_field(:first_name, help: "Enter your first name")
      expect(result).to have_css("p#user_first_name-help", text: "Enter your first name")
    end

    it "merges custom classes" do
      result = builder.text_field(:first_name, class: "w-1/2")
      expect(result).to have_css("input.w-1\\/2")
    end

    it "passes through HTML attributes" do
      result = builder.text_field(:first_name, autofocus: true, autocomplete: "given-name")
      expect(result).to have_css("input[autofocus][autocomplete='given-name']")
    end
  end

  describe "#text_field with errors" do
    before { user.errors.add(:first_name, "can't be blank") }

    it "applies error classes to the input" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("input.ring-danger")
    end

    it "renders an inline error message" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("p#user_first_name-error[role='alert']", text: "can't be blank")
    end

    it "applies error styling to the label" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("label.text-danger")
    end
  end

  describe "#error_summary" do
    it "renders nothing when no errors" do
      result = builder.error_summary
      expect(result).to be_nil
    end

    it "renders error banner when errors exist" do
      user.errors.add(:first_name, "can't be blank")
      user.errors.add(:email_address, "is invalid")
      result = builder.error_summary
      expect(result).to have_css("div[role='alert']")
      expect(result).to have_css("li", count: 2)
    end
  end

  describe "#submit" do
    it "renders a submit button with correct classes" do
      result = builder.submit("Save")
      expect(result).to have_css("input[type='submit'][value='Save']")
      expect(result).to have_css("input.min-h-\\[44px\\]")
      expect(result).to have_css("input.bg-interactive")
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/form_builders/tailwind_form_builder_spec.rb`
Expected: FAIL — `uninitialized constant TailwindFormBuilder`

- [ ] **Step 3: Create the form builder**

Create `app/form_builders/tailwind_form_builder.rb`:

```ruby
class TailwindFormBuilder < ActionView::Helpers::FormBuilder
  # State-independent base classes (layout, spacing, shape)
  FIELD_BASE = "block w-full rounded-md border px-3 py-2 placeholder:text-text-muted focus:outline-none focus:ring-2 min-h-[44px]"

  # State-dependent classes — applied exclusively (normal OR error, never both)
  FIELD_NORMAL = "border-border-strong bg-surface-raised text-text-heading focus:ring-interactive-focus"
  FIELD_ERROR = "border-danger ring-2 ring-danger bg-danger-surface text-danger focus:ring-danger"

  LABEL_CLASSES = "block text-sm font-medium text-text-body"
  ERROR_LABEL_CLASSES = "block text-sm font-medium text-danger"
  HELP_TEXT_CLASSES = "text-sm text-text-muted"
  ERROR_MESSAGE_CLASSES = "text-sm text-danger"

  SUBMIT_CLASSES = "min-h-[44px] inline-flex items-center justify-center px-4 rounded-md bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus cursor-pointer"

  CHECKBOX_CLASSES = "size-5 rounded border-border-strong text-interactive focus:ring-2 focus:ring-interactive-focus mt-0.5"

  FILE_FIELD_CLASSES = "block w-full text-sm text-text-body file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-interactive file:text-text-on-interactive hover:file:bg-interactive-hover file:cursor-pointer file:min-h-[44px]"

  def text_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def email_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def password_field(method, options = {})
    options[:autocomplete] ||= "new-password"
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def url_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def tel_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def number_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def date_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def search_field(method, options = {})
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def text_area(method, options = {})
    options[:rows] ||= 4
    field_wrapper(method, options) do
      super(method, field_options(method, options))
    end
  end

  def select(method, choices = nil, options = {}, html_options = {}, &block)
    label_opts = options.extract!(:label, :required, :help)
    field_wrapper(method, label_opts) do
      super(method, choices, options, html_options.merge(field_html_options(method, label_opts)), &block)
    end
  end

  def check_box(method, options = {}, checked_value = "1", unchecked_value = "0")
    label_text = options.delete(:label) || method.to_s.humanize
    @template.content_tag(:div, class: "flex items-start gap-3") do
      super(method, options.merge(class: merge_classes(CHECKBOX_CLASSES, options[:class])), checked_value, unchecked_value) +
        @template.label_tag(field_id(method), label_text, class: "text-sm text-text-body")
    end
  end

  def collection_check_boxes(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
    label_text = options.delete(:label) || method.to_s.humanize
    @template.content_tag(:fieldset, class: "space-y-2") do
      @template.content_tag(:legend, label_text, class: LABEL_CLASSES) +
        @template.content_tag(:div, class: "space-y-2") do
          super(method, collection, value_method, text_method, options, html_options.merge(class: CHECKBOX_CLASSES)) { |b|
            @template.content_tag(:div, class: "flex items-center gap-3") do
              b.check_box + b.label(class: "text-sm text-text-body")
            end
          }
        end +
        field_error(method)
    end
  end

  def collection_radio_buttons(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
    label_text = options.delete(:label) || method.to_s.humanize
    @template.content_tag(:fieldset, class: "space-y-2") do
      @template.content_tag(:legend, label_text, class: LABEL_CLASSES) +
        @template.content_tag(:div, class: "space-y-2") do
          super(method, collection, value_method, text_method, options, html_options) { |b|
            @template.content_tag(:div, class: "flex items-center gap-3") do
              b.radio_button(class: CHECKBOX_CLASSES) + b.label(class: "text-sm text-text-body")
            end
          }
        end +
        field_error(method)
    end
  end

  def file_field(method, options = {})
    field_wrapper(method, options) do
      super(method, options.merge(class: merge_classes(FILE_FIELD_CLASSES, options[:class])))
    end
  end

  def submit(value = nil, options = {})
    super(value, options.merge(class: merge_classes(SUBMIT_CLASSES, options[:class])))
  end

  def error_summary(options = {})
    return nil unless object&.errors&.any?

    count = object.errors.count
    @template.content_tag(:div, role: "alert",
                          class: "rounded-lg border border-danger-border bg-danger-surface p-4") do
      @template.content_tag(:div, class: "flex items-start gap-3") do
        @template.icon(:exclamation_circle, size: :md, class: "text-danger-icon shrink-0 mt-0.5") +
          @template.content_tag(:div) do
            @template.content_tag(:h2, I18n.t("errors.form_errors", count: count),
                                  class: "text-sm font-semibold text-danger") +
              @template.content_tag(:ul, class: "mt-2 list-disc list-inside text-sm text-danger") do
                object.errors.full_messages.map { |msg|
                  @template.content_tag(:li, msg)
                }.join.html_safe
              end
          end
      end
    end
  end

  private

  def field_wrapper(method, options, &block)
    label_text = options.delete(:label)
    required = options.delete(:required)
    help = options.delete(:help)

    @template.content_tag(:div, class: "space-y-2") do
      field_label(method, label_text, required: required) +
        (help ? field_help(method, help) : "".html_safe) +
        yield +
        field_error(method)
    end
  end

  def field_label(method, label_text, required: false)
    text = label_text || method.to_s.humanize
    css = has_errors?(method) ? ERROR_LABEL_CLASSES : LABEL_CLASSES

    content = if required
                "#{text} #{@template.content_tag(:span, "*", class: "text-danger")}".html_safe
              else
                text
              end

    @template.label_tag(field_id(method), content, class: css, for: field_id(method))
  end

  def field_help(method, text)
    @template.content_tag(:p, text, id: "#{field_id(method)}-help", class: HELP_TEXT_CLASSES)
  end

  def field_error(method)
    return "".html_safe unless has_errors?(method)

    message = object.errors[method].first
    @template.content_tag(:p, message, id: "#{field_id(method)}-error",
                          role: "alert", class: ERROR_MESSAGE_CLASSES)
  end

  def field_options(method, options)
    custom_class = options.delete(:class)
    options.delete(:label)
    options.delete(:required) # consumed by wrapper, re-add as aria
    options.delete(:help)

    base = "#{FIELD_BASE} #{has_errors?(method) ? FIELD_ERROR : FIELD_NORMAL}"
    options[:class] = merge_classes(base, custom_class)
    options[:id] ||= field_id(method)
    options.merge!(aria_attributes(method, options))
    options
  end

  def field_html_options(method, options)
    base = "#{FIELD_BASE} #{has_errors?(method) ? FIELD_ERROR : FIELD_NORMAL}"
    {
      class: merge_classes(base, nil),
      id: field_id(method)
    }.merge(aria_attributes(method, options))
  end

  def aria_attributes(method, options)
    attrs = {}
    attrs[:"aria-required"] = "true" if options[:required]
    attrs[:"aria-invalid"] = "true" if has_errors?(method)

    describedby = []
    describedby << "#{field_id(method)}-help" if options[:help]
    describedby << "#{field_id(method)}-error" if has_errors?(method)
    attrs[:"aria-describedby"] = describedby.join(" ") if describedby.any?

    attrs
  end

  def has_errors?(method)
    object&.errors&.[](method)&.any? || false
  end

  def field_id(method)
    "#{@object_name}_#{method}"
  end

  def merge_classes(*classes)
    classes.compact.join(" ").squish
  end
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/form_builders/tailwind_form_builder_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/form_builders/tailwind_form_builder.rb spec/form_builders/tailwind_form_builder_spec.rb
git commit -m "feat: add TailwindFormBuilder with semantic token styling

Custom form builder wrapping fields with labels, help text, inline
errors, and WCAG AAA accessibility attributes. Uses separate normal
and error class constants to avoid Tailwind CSS conflicts."
```

---

### Task 2: Add Accessibility Specs (TDD)

**Files:**

- Create: `spec/form_builders/tailwind_form_builder_accessibility_spec.rb`

- [ ] **Step 1: Write the accessibility specs**

Create `spec/form_builders/tailwind_form_builder_accessibility_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TailwindFormBuilder, "accessibility" do
  let(:user) { User.new }
  let(:builder) { described_class.new(:user, user, template, {}) }
  let(:template) { ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil) }

  before do
    template.class.include ActionView::Helpers::FormHelper
    template.class.include ActionView::Helpers::TagHelper
    template.class.include ActionView::Context
    template.class.include IconHelper
  end

  describe "aria-required" do
    it "is set when field is required" do
      result = builder.text_field(:first_name, required: true)
      expect(result).to have_css("input[aria-required='true']")
    end

    it "is not set when field is not required" do
      result = builder.text_field(:first_name)
      expect(result).not_to have_css("input[aria-required]")
    end
  end

  describe "aria-invalid" do
    it "is set when field has errors" do
      user.errors.add(:first_name, "can't be blank")
      result = builder.text_field(:first_name)
      expect(result).to have_css("input[aria-invalid='true']")
    end

    it "is not set when field has no errors" do
      result = builder.text_field(:first_name)
      expect(result).not_to have_css("input[aria-invalid]")
    end
  end

  describe "aria-describedby" do
    it "links to help text when help is provided" do
      result = builder.text_field(:first_name, help: "Your given name")
      expect(result).to have_css("input[aria-describedby='user_first_name-help']")
      expect(result).to have_css("p#user_first_name-help")
    end

    it "links to error message when errors exist" do
      user.errors.add(:first_name, "can't be blank")
      result = builder.text_field(:first_name)
      expect(result).to have_css("input[aria-describedby='user_first_name-error']")
      expect(result).to have_css("p#user_first_name-error[role='alert']")
    end

    it "links to both help and error when both exist" do
      user.errors.add(:first_name, "can't be blank")
      result = builder.text_field(:first_name, help: "Your given name")
      expect(result).to have_css("input[aria-describedby='user_first_name-help user_first_name-error']")
    end

    it "is not set when neither help nor error exist" do
      result = builder.text_field(:first_name)
      expect(result).not_to have_css("input[aria-describedby]")
    end
  end

  describe "labels" do
    it "has for attribute matching input id" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("label[for='user_first_name']")
      expect(result).to have_css("input#user_first_name")
    end

    it "shows required indicator when required" do
      result = builder.text_field(:first_name, required: true)
      expect(result).to have_css("label span.text-danger", text: "*")
    end

    it "does not show required indicator when not required" do
      result = builder.text_field(:first_name)
      expect(result).not_to have_css("label span.text-danger")
    end
  end

  describe "error messages" do
    it "has role=alert" do
      user.errors.add(:first_name, "can't be blank")
      result = builder.text_field(:first_name)
      expect(result).to have_css("p[role='alert']")
    end

    it "has unique id for aria-describedby linkage" do
      user.errors.add(:first_name, "can't be blank")
      result = builder.text_field(:first_name)
      expect(result).to have_css("p#user_first_name-error")
    end
  end

  describe "error indication is not color-only" do
    before { user.errors.add(:first_name, "can't be blank") }

    it "uses ring border on input" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("input.ring-danger")
    end

    it "uses background tint on input" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("input.bg-danger-surface")
    end

    it "renders text error message" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("p", text: "can't be blank")
    end

    it "changes label color" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("label.text-danger")
    end
  end

  describe "touch targets" do
    it "text fields meet 44px minimum" do
      result = builder.text_field(:first_name)
      expect(result).to have_css("input.min-h-\\[44px\\]")
    end

    it "submit buttons meet 44px minimum" do
      result = builder.submit("Save")
      expect(result).to have_css("input.min-h-\\[44px\\]")
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they pass**

Run: `bundle exec rspec spec/form_builders/tailwind_form_builder_accessibility_spec.rb`
Expected: All pass (the builder already implements these features)

- [ ] **Step 3: Commit**

```bash
git add spec/form_builders/tailwind_form_builder_accessibility_spec.rb
git commit -m "test: add WCAG AAA accessibility specs for TailwindFormBuilder

Covers aria-required, aria-invalid, aria-describedby linkage,
label-input association, required indicators, error role=alert,
non-color-only error indication, and 44px touch targets."
```

---

### Task 3: Register as Default Form Builder

**Files:**

- Create: `config/initializers/form_builder.rb`

- [ ] **Step 1: Create the initializer**

Create `config/initializers/form_builder.rb`:

```ruby
ActionView::Base.default_form_builder = TailwindFormBuilder
```

- [ ] **Step 2: Verify it loads**

Run: `bundle exec rails runner "puts ActionView::Base.default_form_builder"`
Expected: `TailwindFormBuilder`

- [ ] **Step 3: Run the full test suite to check for breakage**

Run: `bundle exec rspec`
Expected: Some failures are likely — existing forms pass `class:` to fields which will now conflict with the builder's auto-generated classes. This is expected and will be fixed in the migration tasks.

Note the failures and proceed — the migration tasks will fix them.

- [ ] **Step 4: Commit**

```bash
git add config/initializers/form_builder.rb
git commit -m "feat: register TailwindFormBuilder as default form builder

All form_with calls now use TailwindFormBuilder automatically.
Existing forms need migration to remove manual class attributes."
```

---

### Task 4: Migrate Authentication Forms

**Files:**

- Modify: `app/views/sessions/new.html.erb`
- Modify: `app/views/sessions/password_form.html.erb`
- Modify: `app/views/registrations/new.html.erb`
- Modify: `app/views/passwords/new.html.erb`
- Modify: `app/views/passwords/edit.html.erb`
- Modify: `app/views/magic_link_registrations/show.html.erb`

- [ ] **Step 1: Migrate sessions/new.html.erb**

Replace the full contents of `app/views/sessions/new.html.erb`:

```erb
<% content_for(:title) { t("sessions.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("sessions.new.title") %>
  </h1>

  <%= render "shared/oauth_buttons" %>

  <%= turbo_frame_tag "sign_in_form" do %>
    <%= form_with url: main_app.session_lookup_path, class: "mt-8 space-y-6" do |form| %>
      <%= form.email_field :email_address,
            label: t("sessions.new.email_label"),
            required: true,
            autofocus: true,
            autocomplete: "email" %>

      <%= form.submit t("sessions.new.continue"), class: "w-full" %>
    <% end %>
  <% end %>

  <div class="mt-6 text-center">
    <p class="text-sm text-text-muted">
      <%= t("sessions.new.no_account") %>
      <%= link_to t("sessions.new.sign_up"), main_app.new_registration_path,
            class: "text-interactive underline hover:no-underline
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
    </p>
  </div>
</div>
```

- [ ] **Step 2: Migrate sessions/password_form.html.erb**

Replace the full contents of `app/views/sessions/password_form.html.erb`:

```erb
<%= turbo_frame_tag "sign_in_form" do %>
  <p class="mt-4 text-sm text-text-muted"><%= t("sessions.lookup.password_prompt") %></p>

  <%= form_with url: main_app.session_path, class: "mt-6 space-y-6", data: { turbo_frame: "_top" } do |form| %>
    <%= form.email_field :email_address,
          label: t("sessions.new.email_label"),
          value: @email_address,
          readonly: true,
          autocomplete: "username",
          tabindex: -1 %>

    <%= form.password_field :password,
          label: t("sessions.password_form.password_label"),
          required: true,
          autofocus: true,
          autocomplete: "current-password",
          maxlength: 72 %>

    <%= form.submit t("sessions.password_form.submit"), class: "w-full" %>
  <% end %>

  <div class="mt-4 flex flex-col gap-2 text-sm text-center">
    <%= button_to t("sessions.password_form.use_magic_link"),
          main_app.magic_link_path,
          params: { email_address: @email_address },
          method: :post,
          form: { data: { turbo_frame: "_top" } },
          class: "text-interactive underline hover:no-underline
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded cursor-pointer" %>
    <%= link_to t("sessions.new.forgot_password"), main_app.new_password_path,
          class: "text-interactive underline hover:no-underline
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded",
          data: { turbo_frame: "_top" } %>
  </div>
<% end %>
```

- [ ] **Step 3: Migrate registrations/new.html.erb**

Replace the full contents of `app/views/registrations/new.html.erb`:

```erb
<% content_for(:title) { t("registrations.new.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("registrations.new.title") %>
  </h1>

  <%= render "shared/oauth_buttons" %>

  <%= form_with(model: @user, url: registration_path, class: "mt-8 space-y-6") do |form| %>
    <%= form.error_summary %>

    <%= form.email_field :email_address,
          label: t("registrations.new.email_label"),
          required: true,
          autocomplete: "email" %>

    <%= form.text_field :first_name,
          label: t("registrations.new.first_name_label"),
          required: true,
          autocomplete: "given-name" %>

    <%= form.text_field :last_name,
          label: t("registrations.new.last_name_label"),
          required: true,
          autocomplete: "family-name" %>

    <%= form.password_field :password,
          label: t("registrations.new.password_label"),
          required: true,
          help: t("registrations.new.password_hint") %>

    <%= form.password_field :password_confirmation,
          label: t("registrations.new.password_confirmation_label"),
          required: true %>

    <%= form.submit t("registrations.new.submit"), class: "w-full" %>
  <% end %>

  <p class="mt-6 text-center text-text-muted">
    <%= t("registrations.new.already_have_account") %>
    <%= link_to t("registrations.new.sign_in"), new_session_path,
          class: "text-interactive underline hover:no-underline
                  focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
  </p>
</div>
```

- [ ] **Step 4: Migrate passwords/new.html.erb**

Read the current file first, then replace. The pattern is the same — remove manual label/class/error blocks, use builder options.

Read: `app/views/passwords/new.html.erb`

Replace with the same pattern: `form.email_field :email_address, label: ..., required: true, autocomplete: "email"` plus `form.submit`.

- [ ] **Step 5: Migrate passwords/edit.html.erb**

Read: `app/views/passwords/edit.html.erb`

Replace error block with `form.error_summary`. Replace manual label/field pairs with `form.password_field :password, label: ..., required: true, help: ...` and `form.password_field :password_confirmation, ...`.

- [ ] **Step 6: Migrate magic_link_registrations/show.html.erb**

Read: `app/views/magic_link_registrations/show.html.erb`

Replace with `form.error_summary` + `form.text_field :first_name` + `form.text_field :last_name` + `form.submit`.

- [ ] **Step 7: Run auth-related specs**

Run: `bundle exec rspec spec/system/ spec/requests/ -e "sign\|session\|registr\|password\|magic"`
Expected: All pass. If any fail due to changed HTML structure, investigate — the builder generates different HTML than the manual markup, so CSS selectors in specs may need updating.

- [ ] **Step 8: Commit**

```bash
git add app/views/sessions/ app/views/registrations/ app/views/passwords/ app/views/magic_link_registrations/
git commit -m "refactor: migrate authentication forms to TailwindFormBuilder

Sessions, registration, password reset, and magic link forms now
use the builder for consistent styling, labels, help text, inline
errors, and WCAG AAA accessibility attributes."
```

---

### Task 5: Migrate Workspace Forms

**Files:**

- Modify: `app/views/workspaces/new.html.erb`
- Modify: `app/views/workspaces/edit.html.erb`
- Modify: `app/views/workspaces/settings/edit.html.erb`
- Modify: `app/views/workspaces/invitations/new.html.erb`
- Modify: `app/views/workspaces/members/edit.html.erb`
- Modify: `app/views/workspaces/members/index.html.erb`
- Modify: `app/views/workspaces/brandings/edit.html.erb`
- Modify: `app/views/workspaces/projects/new.html.erb`
- Modify: `app/views/workspaces/projects/edit.html.erb`
- Modify: `app/views/workspaces/projects/memberships/new.html.erb`
- Modify: `app/views/workspaces/projects/invitations/new.html.erb`
- Modify: `app/views/workspaces/projects/resources/new.html.erb`
- Modify: `app/views/workspaces/projects/resources/edit.html.erb`

- [ ] **Step 1: Read and migrate each workspace form**

For each file, the pattern is:
1. Read the current file
2. Remove manual `<label>` tags, `class:` on fields, manual error blocks
3. Use builder options: `label:`, `required:`, `help:`
4. Replace error blocks with `form.error_summary`
5. For `select`, pass options as builder `label:` option
6. For `check_box`, pass `label:` option
7. For `text_area`, pass `label:`, `help:`, `rows:` options

**Key patterns for workspace forms:**

Workspace new/edit (simple text_field + submit):
```erb
<%= form.text_field :name, label: t("..."), required: true, autofocus: true %>
```

Settings (number fields):
```erb
<%= form.number_field :max_members, label: t("...") %>
```

Invitations (text_area + select + check_box):
```erb
<%= form.text_area :emails, label: t("..."), help: t("..."), rows: 4 %>
<%= form.select :role_id, @roles.map { |r| [r.name, r.id] }, label: t("...") %>
<%= form.check_box :magic_link, label: t("...") %>
```

Members search form — this is a GET filter form, not a model form. The search_field should keep working but may need the builder to pass through the search controller data attributes.

Branding form — has a file_field and a custom color input. The file_field should work with the builder. The color input may need to remain custom.

Resource forms — use `text_field_tag` and `select_tag` (not form builder methods). These may need to stay as-is or be converted to model-backed fields.

- [ ] **Step 2: Run workspace specs**

Run: `bundle exec rspec spec/system/ spec/requests/ -e "workspace\|project\|member\|invitation\|branding\|resource"`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/views/workspaces/
git commit -m "refactor: migrate workspace forms to TailwindFormBuilder

Workspace CRUD, settings, invitations, members, branding, projects,
and resources forms now use the builder for consistent styling and
accessibility."
```

---

### Task 6: Migrate Account Forms

**Files:**

- Modify: `app/views/account/profiles/edit.html.erb`
- Modify: `app/views/account/passwords/new.html.erb`

- [ ] **Step 1: Migrate account/profiles/edit.html.erb**

Replace the full contents of `app/views/account/profiles/edit.html.erb`:

```erb
<% content_for(:title) { t("account.profiles.edit.title") } %>
<div class="max-w-md mx-auto px-4 py-16">
  <h1 class="text-2xl font-bold text-text-heading">
    <%= t("account.profiles.edit.title") %>
  </h1>

  <%= form_with model: @user, url: account_profile_path, method: :patch, class: "mt-8 space-y-6" do |form| %>
    <%= form.error_summary %>

    <%= form.text_field :first_name,
          label: t("account.profiles.edit.first_name_label"),
          required: true,
          autocomplete: "given-name" %>

    <%= form.text_field :last_name,
          label: t("account.profiles.edit.last_name_label"),
          required: true,
          autocomplete: "family-name" %>

    <%= form.email_field :email_address,
          label: t("account.profiles.edit.email_label"),
          required: true,
          autocomplete: "email" %>

    <%= form.submit t("account.profiles.edit.submit"), class: "w-full" %>
  <% end %>
</div>
```

- [ ] **Step 2: Migrate account/passwords/new.html.erb**

Read the current file, then replace with builder pattern: `form.error_summary` + `form.password_field` fields + `form.submit`.

- [ ] **Step 3: Run account specs**

Run: `bundle exec rspec spec/system/ spec/requests/ -e "profile\|account"`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add app/views/account/
git commit -m "refactor: migrate account forms to TailwindFormBuilder

Profile edit and password set forms now use the builder."
```

---

### Task 7: Run Full Test Suite and Fix Remaining Issues

**Files:** Various (fix any breakage)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All 698+ specs pass. If any fail, investigate:
- Changed HTML structure may break CSS selector expectations in specs
- Forms that use `text_field_tag` (not `form.text_field`) won't be affected by the builder
- Search/filter forms may have different behavior

- [ ] **Step 2: Fix any failures**

Common fixes:
- Update spec selectors that look for specific CSS classes on inputs
- Ensure forms that pass custom `class:` to submit merge correctly
- Check that readonly fields (like the email in password_form) still look correct

- [ ] **Step 3: Run full suite again to verify**

Run: `bundle exec rspec`
Expected: All pass, 0 failures

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve form builder migration spec failures

Update spec selectors and fix edge cases from TailwindFormBuilder
migration."
```

---

## Verification

After all tasks are complete:

1. **Full suite:** `bundle exec rspec` — all specs green
2. **Registration form:** Visit `/registration/new`, submit empty — see error summary + inline errors with red styling
3. **Login form:** Visit `/session/new` — clean single-field form with proper label
4. **Profile form:** Visit `/account/profile/edit` — fields have labels, proper focus rings
5. **Workspace form:** Create a workspace — form uses builder styling
6. **Accessibility:** Tab through any form — focus rings visible, labels linked to inputs
7. **Screen reader:** Error messages announced via `role="alert"`
8. **Dark mode:** Toggle dark mode — forms adapt via semantic tokens
