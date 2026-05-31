# frozen_string_literal: true

module UI
  class FileInputComponentPreview < ViewComponent::Preview
    def default
      render UI::FileInputComponent.new(name: "attachment")
    end

    def images_only
      render UI::FileInputComponent.new(name: "avatar", accept: "image/*")
    end

    def multiple
      render UI::FileInputComponent.new(name: "docs", multiple: true)
    end
  end
end
