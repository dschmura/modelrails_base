# frozen_string_literal: true

module UI
  # A server-rendered data table: caption, header, body and footer slots around a plain <table>; sorting, filtering and paging are the caller's (a GET form, pagy).
  # Usage, options and the accessibility contract: docs/components/table.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class TableComponent < ApplicationComponent
    WRAPPER = "rounded-lg border border-border bg-surface-raised overflow-hidden"
    TABLE   = "w-full text-sm"
    THEAD   = "bg-surface-sunken/40"
    # h-11 keeps a header row (and any sort link filling it) at the AAA 44px target floor.
    TH      = "h-11 px-4 text-left align-middle text-sm font-medium text-text-muted whitespace-nowrap"
    # No border-t: the pagination partial that lives here draws its own.
    FOOTER  = "text-sm text-text-muted"
    SIZES   = { default: "default", compact: "compact" }.freeze

    renders_one :header
    renders_one :body
    renders_one :footer

    def initialize(caption:, caption_visible: false, size: :default, **html_attrs)
      raise ArgumentError, "UI::TableComponent needs a caption — it is the table's accessible name" if caption.blank?
      raise ArgumentError, "UI::TableComponent size: must be one of #{SIZES.keys.inspect}" unless SIZES.key?(size.to_sym)

      @caption = caption
      @caption_visible = caption_visible
      @size = size.to_sym
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn(WRAPPER, @extra_class), data: { size: SIZES[@size] }, **@html_attrs) do
        concat table
        concat content_tag(:div, footer, class: FOOTER, data: { slot: "footer" }) if footer?
      end
    end

    private

    def table
      content_tag(:table, class: TABLE) do
        concat content_tag(:caption, @caption, class: (@caption_visible ? "px-4 py-2 text-left text-sm text-text-muted" : "sr-only"))
        concat content_tag(:thead, content_tag(:tr, header), class: THEAD) if header?
        concat content_tag(:tbody, body) if body?
      end
    end
  end
end
