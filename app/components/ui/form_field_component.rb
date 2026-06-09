# frozen_string_literal: true

module UI
  # # Form Field
  #
  # Wraps a caption + control + optional hint and error into one AAA-correct field:
  # it binds the `<label for>` to the control, gives the hint/error real ids that the
  # control references via `aria-describedby`, and injects `invalid`/`required` into
  # the control. The control arrives as a block, so the component yields its field
  # context (`input_attrs`) and the caller spreads it onto any control:
  #
  #   <%= ui :form_field, label: "Email", hint: "We'll never share it.",
  #         error: @user.errors[:email].first, required: true do |f| %>
  #     <%= ui :input, type: "email", name: "user[email]", **f.input_attrs %>
  #   <% end %>
  #
  # ## Use when
  # - You're composing a single labelled field by hand (a one-off form, or a control
  #   the `TailwindFormBuilder` doesn't cover). For model-backed forms, prefer the
  #   builder — it already does this wiring.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `<label for=id>` bound to the control; hint/error rendered with
  #   ids `#{id}-hint`/`#{id}-error`; and `input_attrs` carrying `id` +
  #   `describedby` (the hint/error ids → the control's `aria-describedby`) +
  #   `invalid` (on error) + `required`. The required marker is a decorative
  #   aria-hidden `*` on the Label — the caption never carries the requirement.
  # - **You supply:** the control inside the block, spread with `**f.input_attrs` so it
  #   adopts the field's id and aria wiring.
  class FormFieldComponent < ApplicationComponent
    # data-slot adjacency rhythm (the Catalyst model): label→control 12px,
    # control→description 8px, description→description 4px. Self-contained Tailwind
    # arbitrary variants keyed on the children's data-slot — no host CSS needed.
    WRAPPER = "[&>[data-slot=label]+[data-slot=control]]:mt-3 " \
              "[&>[data-slot=control]+[data-slot=description]]:mt-2 " \
              "[&>[data-slot=description]+[data-slot=description]]:mt-1"

    def initialize(label: nil, hint: nil, error: nil, required: false, **html_attrs)
      @label = label
      @hint = hint
      @error = error
      @required = required
      @id = html_attrs.delete(:id) || "form_field_#{object_id}"
      @describedby = [ ("#{@id}-hint" if @hint.present?), ("#{@id}-error" if @error.present?) ].compact.join(" ").presence
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    # The wiring the slotted control must spread (`**f.input_attrs`): id +
    # aria-describedby (hint/error ids) + invalid + required. Mirrors exactly what
    # TailwindFormBuilder injects into the controls it renders itself.
    def input_attrs
      { id: @id, describedby: @describedby, invalid: @error.present?, required: @required }
    end

    def call
      content_tag(:div, class: cn(WRAPPER, @extra_class), **@html_attrs) do
        safe_join([
          field_label,
          content_tag(:div, content, data: { slot: "control" }),
          hint_tag,
          error_tag
        ].compact)
      end
    end

    private

    # The caption, via the Label primitive: a real `for=` association + the decorative
    # aria-hidden `*` required mark. data-slot=label drives the adjacency spacing.
    def field_label
      return unless @label

      render(UI::LabelComponent.new(@label, for: @id, required: @required, data: { slot: "label" }))
    end

    def hint_tag
      return unless @hint.present?

      content_tag(:p, @hint, id: "#{@id}-hint", class: "text-sm text-text-muted", data: { slot: "description" })
    end

    def error_tag
      return unless @error.present?

      content_tag(:p, @error, id: "#{@id}-error", role: "alert", class: "text-sm text-danger", data: { slot: "description" })
    end
  end
end
