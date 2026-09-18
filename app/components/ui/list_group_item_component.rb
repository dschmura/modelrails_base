# frozen_string_literal: true

module UI
  # A single row inside a `list_group`.
  # Usage, options and the accessibility contract: docs/components/list_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ListGroupItemComponent < ApplicationComponent
    BASE = "flex items-center justify-between px-4 py-3 text-sm"

    # Interactive (link) rows get the shared focus-ring utility (AAA offset outline)
    # plus token-based hover/active — never focus:ring-* and never raw colors.
    LINK = "focus-ring transition-colors"

    VARIANTS = {
      default: "text-text-heading hover:bg-surface-sunken",
      active:  "bg-interactive text-text-on-interactive",
      muted:   "text-text-muted hover:bg-surface-sunken"
    }.freeze

    def initialize(label = nil, href: nil, active: false, variant: :default, **html_attrs)
      @label = label || html_attrs.delete(:label)
      @href = href
      @active = active
      @variant = coerce_variant(active ? :active : variant.to_sym)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      @href ? link_row : static_row
    end

    private

    # A navigable row: <a> inside its <li>. The link carries the row styling, the
    # focus-ring, and aria-current="page" when it is the active page.
    def link_row
      content_tag(:li) do
        content_tag(:a, body,
          href: @href,
          class: cn(BASE, LINK, VARIANTS.fetch(@variant), @extra_class),
          "aria-current": (@active ? "page" : nil),
          **@html_attrs)
      end
    end

    # A static row: a plain, non-interactive <li>. Never focusable.
    def static_row
      content_tag(:li, body,
        class: cn(BASE, VARIANTS.fetch(@variant), @extra_class),
        **@html_attrs)
    end

    def body
      content.presence || @label
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :default in production so a bad variant never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the
    # Rails module is defined but Rails.env isn't booted (the gem's Rails-less
    # render tests load rails/generators, which defines Rails without Rails.env).
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ListGroupItemComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :default
    end
  end
end
