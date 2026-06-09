# frozen_string_literal: true

module UI
  class CardHeaderComponent < ApplicationComponent
    BASE = "@container/card-header grid auto-rows-min grid-rows-[auto_auto] items-start gap-2 px-6 " \
           "has-data-[slot=card-action]:grid-cols-[1fr_auto] [.border-b]:pb-6"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, content, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
