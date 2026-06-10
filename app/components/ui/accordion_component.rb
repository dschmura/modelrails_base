# frozen_string_literal: true

module UI
  # A stack of native <details> disclosure rows.
  #
  # Two APIs: an `items:` array shorthand (each `{ title:, content:, open? }`) and a
  # `with_item` slot for block content. `exclusive: true` makes opening one row close
  # the rest via the `accordion` Stimulus controller — progressive enhancement, so
  # without JS every row still opens and closes independently.
  class AccordionComponent < ApplicationComponent
    renders_many :items, "UI::AccordionItemComponent"

    def initialize(items: nil, exclusive: false, **html_attrs)
      @items_data = Array(items)
      @exclusive = exclusive
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn("w-full", @extra_class), **wrapper_attrs) do
        safe_join([
          safe_join(@items_data.map { |item| render_shorthand_item(item) }),
          safe_join(items)
        ])
      end
    end

    private

    def render_shorthand_item(item)
      render(UI::AccordionItemComponent.new(title: item[:title], open: item.fetch(:open, false))) { item[:content] }
    end

    def wrapper_attrs
      attrs = @html_attrs.dup
      if @exclusive
        attrs[:data] = (attrs[:data] || {}).merge(controller: "accordion", action: "click->accordion#toggle")
      end
      attrs
    end
  end
end
