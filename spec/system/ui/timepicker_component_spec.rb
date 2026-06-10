# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the timepicker component (scoped to its visible root;
# axe skips any hidden popover by design). No color-contrast exclude.
RSpec.describe "Timepicker component accessibility", type: :system do
  it "default passes AAA in both themes" do
    visit "/rails/view_components/ui/timepicker_component/default"

    expect(page).to have_css("[data-controller='timepicker']")

    scope = [ "[data-controller='timepicker']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
