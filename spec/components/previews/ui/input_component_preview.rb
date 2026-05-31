# frozen_string_literal: true

module UI
  # Text inputs (dual-mode: standalone or form-builder-driven).
  class InputComponentPreview < ViewComponent::Preview
    def default
      render UI::InputComponent.new(type: "email", name: "email", placeholder: "you@example.com")
    end

    def required
      render UI::InputComponent.new(name: "email", required: true, placeholder: "Required field")
    end

    def invalid
      render UI::InputComponent.new(name: "email", invalid: true, describedby: "email-error", value: "not-an-email")
    end

    # @param type text
    # @param invalid toggle
    def playground(type: "text", invalid: false)
      render UI::InputComponent.new(type: type, name: "field", invalid: invalid, placeholder: "Type here")
    end
  end
end
