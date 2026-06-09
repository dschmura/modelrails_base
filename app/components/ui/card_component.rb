# frozen_string_literal: true

module UI
  # # Card
  #
  # A presentational content container, optionally composed of header / content /
  # footer regions via the sibling sub-components. The card itself is a plain
  # `<div>` — it carries NO document structure. Any heading lives inside, supplied
  # by `card_title` (or your own markup), so the card never hijacks the outline.
  #
  # ## Use when
  # - Grouping related content into a bordered, raised surface (a settings panel,
  #   a summary tile, a media object).
  #
  # ## Don't use when
  # - The whole card should be a link/button — a card is a static container by
  #   contract. Put a real focusable `link`/`button` inside it instead of making
  #   the `<div>` interactive (a clickable `<div>` is not keyboard-reachable).
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast `text-text-body` on `bg-surface-raised`, a
  #   semantic `border-border` rule, and a system `shadow-sm` (no raw color/shadow).
  #   The container is non-interactive and adds no ARIA role — it is a neutral box.
  # - **You supply:** the heading (via `card_title`, whose level you set with
  #   `level:`) and any focusable controls inside `card_content` / `card_footer`.
  class CardComponent < ApplicationComponent
    BASE = "bg-surface-raised text-text-body flex flex-col gap-6 rounded-xl border border-border py-6 shadow-sm"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, content, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
