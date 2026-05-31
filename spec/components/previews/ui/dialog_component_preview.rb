# frozen_string_literal: true

module UI
  # Native-<dialog> modal (focus-trapped). Click the trigger to open.
  class DialogComponentPreview < ViewComponent::Preview
    def default
      render(UI::DialogComponent.new(title: "Confirm action", description: "This cannot be undone.")) do |d|
        d.with_trigger { '<button type="button" class="btn-primary">Open dialog</button>'.html_safe }
        "Modal body content.".html_safe
      end
    end

    def large
      render(UI::DialogComponent.new(title: "Large dialog", size: :lg)) do |d|
        d.with_trigger { '<button type="button" class="btn-secondary">Open large</button>'.html_safe }
        "A wider modal.".html_safe
      end
    end
  end
end
