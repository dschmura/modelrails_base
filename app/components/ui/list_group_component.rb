# frozen_string_literal: true

module UI
  # # ListGroup
  #
  # A styled vertical list of rows — static items, navigation links, or actions.
  # Renders a real `<ul>`; each child is a `list_group_item` (`<li>`, or an `<a>`
  # wrapped in `<li>` when navigable). Accessibility hinges on this semantics: a
  # static list is a `<ul>`/`<li>`, a list of links is a `<ul>` of `<a>`, and
  # interactive rows are real focusable elements — never `<div>` rows.
  #
  # ## Accessibility contract
  # - **Guarantees:** a semantic `<ul>` on a token surface (`bg-surface`,
  #   `border-border`, `divide-border` between rows). Row semantics and focus
  #   handling live in `list_group_item`.
  # - **You supply:** the rows, via `list_group_item` (slot/block content).
  class ListGroupComponent < ApplicationComponent
    BASE = "divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:ul, content, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
