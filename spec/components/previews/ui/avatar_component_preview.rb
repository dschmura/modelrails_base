# frozen_string_literal: true

module UI
  class AvatarComponentPreview < ViewComponent::Preview
    def initials
      render UI::AvatarComponent.new(fallback: "JD", size: :lg)
    end

    def image
      render UI::AvatarComponent.new(src: "https://i.pravatar.cc/128?img=12", alt: "User", size: :lg)
    end

    def custom_hue
      render UI::AvatarComponent.new(fallback: "AB", size: :lg, hue: 280)
    end

    # @param size select [xs, sm, md, lg, xl]
    def playground(size: :lg)
      render UI::AvatarComponent.new(fallback: "VP", size: size.to_sym)
    end
  end
end
