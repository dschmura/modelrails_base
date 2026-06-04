# frozen_string_literal: true

module UI
  # # Range
  #
  # A styled native `input[type="range"]` slider over the standard min/max/step/value
  # attributes, with AAA accent and focus-ring tokens. The slider has no built-in
  # visible label, so you supply one externally (an `id` is always emitted so the
  # `<label for>` can target it), and on error `invalid: true` + `describedby:`.
  #
  # ## Use when
  # - The user picks a value from a continuous, bounded numeric range and an
  #   approximate position is acceptable (volume, brightness, zoom).
  #
  # ## Don't use when
  # - An exact value matters or the range is unbounded — use a number input.
  # - The choice is a small set of discrete options — use a select or radio_group.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA accent/focus-ring tokens, an `id` ALWAYS emitted on the
  #   `<input>`, `aria-invalid="true"` when `invalid: true`, and `aria-describedby`
  #   wired when `describedby:` is supplied. The thumb target size is UA-controlled
  #   (native range), so the app's axe gate is the AAA target-size authority here.
  # - **You supply:** the visible label as an EXTERNAL `<label for="<id>">` — a native
  #   slider is conventionally labeled by a separate form label. On error, pass
  #   `invalid: true` and point `describedby:` at the error element's id.
  #
  # No fail-loud guard — there's no enum axis to validate.
  class RangeComponent < ApplicationComponent
    BASE = "w-full cursor-pointer appearance-none rounded-full bg-surface-sunken outline-none " \
           "h-2 accent-interactive " \
           "focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-interactive-focus " \
           "disabled:pointer-events-none disabled:opacity-50 " \
           "[&::-webkit-slider-thumb]:size-4 [&::-webkit-slider-thumb]:appearance-none " \
           "[&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-interactive " \
           "[&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-surface-raised " \
           "[&::-webkit-slider-thumb]:shadow-xs [&::-webkit-slider-thumb]:transition-[color,box-shadow] " \
           "[&::-moz-range-thumb]:size-4 [&::-moz-range-thumb]:appearance-none " \
           "[&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-interactive " \
           "[&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-surface-raised " \
           "[&::-moz-range-thumb]:border-solid [&::-moz-range-thumb]:shadow-xs"

    # min / max / step / value: native range attributes
    #   invalid:     sets `aria-invalid="true"` (absent when false)
    #   describedby: sets `aria-describedby` (link to the error/hint element id)
    def initialize(min: 0, max: 100, step: 1, value: nil, invalid: false, describedby: nil, **html_attrs)
      @min   = min
      @max   = max
      @step  = step
      @value = value
      @invalid = invalid
      @describedby = describedby
      # External-label association: an id is ALWAYS emitted so a sibling
      # `<label for>` can target this control. Prefer an explicit id, fall back to a
      # sanitized name, then a stable per-instance id.
      @id = html_attrs[:id] || html_attrs[:name]&.gsub(/\W/, "_") || "range_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:input, nil, **range_attrs)
    end

    private

    def range_attrs
      attrs = @html_attrs.merge(
        type: "range",
        min: @min,
        max: @max,
        step: @step,
        id: @id,
        class: cn(BASE, @extra_class)
      )
      attrs[:value] = @value unless @value.nil?
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end
  end
end
