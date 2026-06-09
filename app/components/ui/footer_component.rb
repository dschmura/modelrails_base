# frozen_string_literal: true

module UI
  # # Footer
  #
  # A page/site footer — the `<footer>` contentinfo landmark with optional link
  # columns (each a heading + a real `<ul>` of `<a>`), an optional block-content
  # area, and an optional copyright row below a divider.
  #
  # ## Use when
  # - Closing a page with site-wide navigation (product / company / legal columns),
  #   social/legal links, and a copyright line.
  #
  # ## Don't use when
  # - You only need an inline list of links inside an article — that isn't the
  #   page's contentinfo landmark. Use a plain `<ul>`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `<footer>` (contentinfo landmark); each column is a real
  #   heading + `<ul>`/`<li>`/`<a>`; links carry the `focus-ring` utility (a visible
  #   AAA focus outline); AAA-contrast text on `bg-surface-raised`. Pass `label:`
  #   (i18n) to name the landmark when a page has more than one footer.
  # - **You supply:** `columns:` (`[{ title:, links: [{ label:, href: }] }]`) and/or
  #   block content and/or `copyright:`. Every link needs a human-readable `label:`
  #   (its accessible name) and an `href:`.
  class FooterComponent < ApplicationComponent
    BASE = "border-t bg-surface-raised"
    LINK = "rounded-sm text-sm text-text-muted transition-colors " \
           "hover:text-text-heading " \
           "focus-ring focus-visible:text-text-heading"

    # Literal grid-cols classes per column count — Tailwind only sees statically
    # present class strings, so an interpolated `md:grid-cols-#{n}` would be a
    # phantom class that never compiles. Caps at 4 columns wide.
    COLS = {
      1 => "md:grid-cols-1", 2 => "md:grid-cols-2",
      3 => "md:grid-cols-3", 4 => "md:grid-cols-4"
    }.freeze

    # columns: [{ title:, links: [{ label:, href: }] }]. copyright: bottom-row text.
    # label: the <footer> accessible name (i18n; only needed when a page has 2+ footers).
    def initialize(copyright: nil, columns: [], label: nil, **html_attrs)
      @copyright = copyright
      @columns   = columns
      @label     = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:footer, class: cn(BASE, @extra_class), "aria-label": @label, **@html_attrs) do
        content_tag(:div, class: "container mx-auto px-6 py-10") do
          concat columns_grid if @columns.any?
          concat content if content?
          concat copyright_row if @copyright
        end
      end
    end

    private

    def columns_grid
      content_tag(:div, class: cn("mb-10 grid gap-8 sm:grid-cols-2", COLS[[ @columns.size, 4 ].min])) do
        safe_join(@columns.map { |col| column(col) })
      end
    end

    def column(col)
      content_tag(:div) do
        concat content_tag(:h3, col[:title], class: "mb-3 text-sm font-semibold text-text-heading")
        concat content_tag(:ul, class: "space-y-2") {
          safe_join((col[:links] || []).map { |link|
            content_tag(:li) { content_tag(:a, link[:label], href: link[:href], class: LINK) }
          })
        }
      end
    end

    def copyright_row
      content_tag(:div, class: "mt-8 border-t pt-8 text-center") do
        content_tag(:p, @copyright, class: "text-sm text-text-muted")
      end
    end
  end
end
