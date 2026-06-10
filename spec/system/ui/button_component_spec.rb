# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the button showcase (all proven variant × tone cells).
RSpec.describe "Button component accessibility", type: :system do
  it "showcase renders every proven cell and passes AAA in both themes" do
    visit "/rails/view_components/ui/button_component/showcase"

    expect(page).to have_css("[data-showcase=button] button", minimum: 5)
    scope = [ "[data-showcase=button]" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
