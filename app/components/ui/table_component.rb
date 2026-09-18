# frozen_string_literal: true

module UI
  # A server-rendered data table: caption, header, body and footer slots around a plain <table>; sorting, filtering and paging are the caller's (a GET form, pagy).
  # Usage, options and the accessibility contract: docs/components/table.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class TableComponent < ApplicationComponent
    # bg-surface, the list_group's card colour: the operations pages sit on a
    # bg-surface-raised body, where a raised wrapper is border-only and reads
    # as a different chrome from the filled list beside it.
    WRAPPER = "rounded-lg border border-border bg-surface overflow-hidden"
    TABLE   = "w-full text-sm"
    THEAD   = "bg-surface-sunken/40"
    # h-11 keeps a header row (and any sort link filling it) at the AAA 44px target floor.
    TH      = "h-11 px-4 text-left align-middle text-sm font-medium text-text-muted whitespace-nowrap"
    # No border-t: the pagination partial that lives here draws its own.
    FOOTER  = "text-sm text-text-muted"
    # The card's own top band — summary, filters-applied state, a Clear link —
    # so the table's context sits inside the border instead of floating above it.
    TOOLBAR = "flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3"
    SIZES   = { default: "default", compact: "compact" }.freeze

    renders_one :toolbar
    renders_one :header
    renders_one :body
    renders_one :footer

    # scroll: nil | :horizontal — wraps ONLY the <table> in a named, focusable
    # scroll region (the ScrollArea contract), so a wide table scrolls under a
    # toolbar and footer that stay put. Wrapping the whole component in a
    # scroll_area instead carried Clear, Rows and the pager off-screen with
    # the columns at phone width.
    def initialize(caption:, caption_visible: false, size: :default, scroll: nil, **html_attrs)
      raise ArgumentError, "UI::TableComponent needs a caption — it is the table's accessible name" if caption.blank?
      raise ArgumentError, "UI::TableComponent size: must be one of #{SIZES.keys.inspect}" unless SIZES.key?(size.to_sym)
      raise ArgumentError, "UI::TableComponent scroll: must be nil or :horizontal" unless scroll.nil? || scroll.to_sym == :horizontal

      @caption = caption
      @caption_visible = caption_visible
      @size = size.to_sym
      @scroll = scroll&.to_sym
      @extra_class = html_attrs.delete(:class)
      # Merge the size attribute into any caller `data:` so a passed-through
      # `data:` attr can't clobber `data-size` and silently break row partials
      # that key off it.
      @data = { size: SIZES[@size] }.merge(html_attrs.delete(:data) || {})
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn(WRAPPER, @extra_class), data: @data, **@html_attrs) do
        concat content_tag(:div, toolbar, class: TOOLBAR, data: { slot: "toolbar" }) if toolbar?
        concat(@scroll ? scroll_region { table } : table)
        concat content_tag(:div, footer, class: FOOTER, data: { slot: "footer" }) if footer?
      end
    end

    private

    def scroll_region(&)
      render(UI::ScrollAreaComponent.new(orientation: @scroll, max_h: nil,
        aria_label: I18n.t("modelrails_ui.table.scroll_region", name: @caption, default: "%{name}, scrolls sideways")), &)
    end

    def table
      content_tag(:table, class: TABLE) do
        concat content_tag(:caption, @caption, class: (@caption_visible ? "px-4 py-2 text-left text-sm text-text-muted" : "sr-only"))
        concat content_tag(:thead, content_tag(:tr, header), class: THEAD) if header?
        concat content_tag(:tbody, body) if body?
      end
    end
  end
end
