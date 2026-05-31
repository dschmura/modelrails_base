# frozen_string_literal: true

module UI
  # Buttons — the app's `.btn-*` system as a component.
  class ButtonComponentPreview < ViewComponent::Preview
    def primary
      render UI::ButtonComponent.new("Save changes", variant: :primary)
    end

    def secondary
      render UI::ButtonComponent.new("Cancel", variant: :secondary)
    end

    def danger
      render UI::ButtonComponent.new("Delete account", variant: :danger)
    end

    def text_interactive
      render UI::ButtonComponent.new("Learn more", variant: :text_interactive)
    end

    def link
      render UI::ButtonComponent.new("Go home", href: "/", variant: :primary)
    end

    # @param label text
    # @param variant select [primary, secondary, danger, text, text_interactive, text_danger]
    def playground(label: "Button", variant: :primary)
      render UI::ButtonComponent.new(label, variant: variant.to_sym)
    end
  end
end
