# frozen_string_literal: true

module UI
  # The caption for a form control — renders a `<label>` and, via `for:`, binds it to an input's `id` so clicking the caption focuses the control and a screen reader announces the control's name.
  # Usage, options and the accessibility contract: docs/components/label.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class LabelComponent < ApplicationComponent
    # text-text-body is the AAA (7:1) body token — the caption must stay legible on
    # any surface, so the color is explicit here rather than inherited.
    BASE = "flex items-center gap-2 text-sm leading-none font-medium text-text-body select-none " \
           "group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:opacity-50 " \
           "peer-disabled:cursor-not-allowed peer-disabled:opacity-50"

    # The required marker is purely decorative — aria-hidden so it's never read out;
    # the requirement is conveyed on the control (aria-required), not the caption.
    REQUIRED_MARK = "text-danger"

    def initialize(text = nil, for: nil, required: false, **html_attrs)
      @text = text || html_attrs.delete(:label)
      @for = binding.local_variable_get(:for)
      @required = required
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:label,
        class: cn(BASE, @extra_class),
        for: @for,
        **@html_attrs) do
        safe_join([ content.presence || @text, required_mark ].compact)
      end
    end

    private

    def required_mark
      return unless @required

      content_tag(:span, "*", class: REQUIRED_MARK, aria: { hidden: true })
    end
  end
end
