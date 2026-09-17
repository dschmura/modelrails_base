# frozen_string_literal: true

module UI
  # A styled vertical list of rows — static items, navigation links, or actions.
  # Usage, options and the accessibility contract: docs/components/list_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
