# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the static rating component.
# A role=img with an accessible value name; stars use the semantic warning-icon token.
RSpec.describe "Rating component accessibility", type: :system do
  it "default renders a labelled rating and passes AAA in both themes" do
    visit "/rails/view_components/ui/rating_component/default"

    expect(page).to have_css("[role='img']")

    scope = [ "[role='img']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
