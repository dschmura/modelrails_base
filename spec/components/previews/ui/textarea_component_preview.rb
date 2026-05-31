# frozen_string_literal: true

module UI
  class TextareaComponentPreview < ViewComponent::Preview
    def default
      render UI::TextareaComponent.new(name: "body", value: "Hello there.", rows: 4)
    end

    def invalid
      render UI::TextareaComponent.new(name: "body", invalid: true, describedby: "body-error", value: "bad")
    end
  end
end
