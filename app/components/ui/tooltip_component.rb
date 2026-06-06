# frozen_string_literal: true

module UI
  # # Tooltip
  #
  # A small text bubble describing the element it wraps. Shows on hover **and**
  # keyboard focus; the wrapper is focusable and `aria-describedby` wires the bubble
  # to it. Escape dismisses (WCAG 1.4.13) via the shared `floating` controller.
  #
  # Placement uses CSS anchor positioning: the bubble is `position: fixed` (so its
  # containing block is the viewport, letting it float free of the wrapper) and tethered
  # to the wrapper via `anchor-name`/`position-anchor`; `position-area` places it and
  # `position-try-fallbacks` auto-flips it on viewport overflow — no JS. On browsers
  # without anchor positioning (pre-Baseline 2026) it falls back to `absolute` offsets.
  #
  # ## Use when
  # - You need a short, non-interactive hint describing a single focusable trigger
  #   (an icon button, a truncated label).
  #
  # ## Don't use when
  # - The content is interactive or rich — use `hover_card`.
  # - You wrap an already-interactive control — put `aria-describedby` on that control
  #   instead (this component makes its own wrapper the focusable trigger).
  #
  # ## Accessibility contract
  # - **Guarantees:** shows on hover AND focus; `role="tooltip"` bubble wired via
  #   `aria-describedby`; Escape dismisses without moving focus; `pointer-events-none`
  #   so the bubble never traps the pointer.
  # - **You supply:** `text:` (the hint) and the trigger content (icon/word).
  class TooltipComponent < ApplicationComponent
    BUBBLE_BASE = "z-50 w-max max-w-xs rounded-md px-3 py-1.5 text-xs text-balance " \
                  "bg-text-heading text-surface-raised whitespace-normal " \
                  "pointer-events-none opacity-0 transition-opacity duration-200 " \
                  "group-hover:opacity-100 group-focus-within:opacity-100 " \
                  "group-data-[dismissed]:opacity-0!"

    # Each side carries: an always-on gap margin; the modern anchor-positioning path
    # (gated behind `supports-[position-area]`) — `fixed` so the viewport is the containing
    # block, `position-area` to place it, `position-try-fallbacks` to auto-flip on overflow;
    # and the pre-Baseline fallback (`not-supports-`) — `absolute` offsets vs the wrapper.
    POSITIONS = {
      top:    "mb-2 " \
              "supports-[position-area:bottom]:fixed " \
              "supports-[position-area:bottom]:[position-area:top_center] " \
              "supports-[position-area:bottom]:[position-try-fallbacks:flip-block] " \
              "not-supports-[position-area:bottom]:absolute " \
              "not-supports-[position-area:bottom]:bottom-full " \
              "not-supports-[position-area:bottom]:left-1/2 " \
              "not-supports-[position-area:bottom]:-translate-x-1/2",
      bottom: "mt-2 " \
              "supports-[position-area:bottom]:fixed " \
              "supports-[position-area:bottom]:[position-area:bottom_center] " \
              "supports-[position-area:bottom]:[position-try-fallbacks:flip-block] " \
              "not-supports-[position-area:bottom]:absolute " \
              "not-supports-[position-area:bottom]:top-full " \
              "not-supports-[position-area:bottom]:left-1/2 " \
              "not-supports-[position-area:bottom]:-translate-x-1/2",
      left:   "mr-2 " \
              "supports-[position-area:bottom]:fixed " \
              "supports-[position-area:bottom]:[position-area:center_left] " \
              "supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] " \
              "not-supports-[position-area:bottom]:absolute " \
              "not-supports-[position-area:bottom]:right-full " \
              "not-supports-[position-area:bottom]:top-1/2 " \
              "not-supports-[position-area:bottom]:-translate-y-1/2",
      right:  "ml-2 " \
              "supports-[position-area:bottom]:fixed " \
              "supports-[position-area:bottom]:[position-area:center_right] " \
              "supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] " \
              "not-supports-[position-area:bottom]:absolute " \
              "not-supports-[position-area:bottom]:left-full " \
              "not-supports-[position-area:bottom]:top-1/2 " \
              "not-supports-[position-area:bottom]:-translate-y-1/2"
    }.freeze

    # text: the hint (the bubble's content); id: bubble id (→ aria-describedby + anchor);
    # side: :top | :bottom | :left | :right
    def initialize(text:, id: nil, side: :top, **html_attrs)
      @text        = text
      @id          = id || "tooltip-#{SecureRandom.hex(4)}"
      @side        = coerce_enum(:side, side, POSITIONS)
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:span, **wrapper_attrs) do
        safe_join([ content, bubble ])
      end
    end

    private

    def wrapper_attrs
      {
        class: cn("group relative inline-flex", @extra_class),
        style: "anchor-name: --#{@id}",
        tabindex: "0",
        "aria-describedby": @id,
        data: {
          controller: "floating",
          action: "keydown.esc->floating#dismiss mouseleave->floating#clearDismissed focusout->floating#clearDismissed"
        }
      }.merge(@html_attrs)
    end

    def bubble
      content_tag(:span, @text,
        id: @id,
        role: "tooltip",
        style: "position-anchor: --#{@id}",
        class: cn(BUBBLE_BASE, POSITIONS.fetch(@side)))
    end

    def coerce_enum(name, value, map)
      key = value.to_sym
      return key if map.key?(key)

      raise ArgumentError, "UI::Tooltip unknown #{name}: #{value.inspect} (allowed: #{map.keys.join(", ")})"
    end
  end
end
