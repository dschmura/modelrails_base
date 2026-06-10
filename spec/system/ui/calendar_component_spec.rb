# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the calendar component (scoped to its visible root;
# axe skips any hidden popover by design). No color-contrast exclude.
RSpec.describe "Calendar component accessibility", type: :system do
  it "default passes AAA in both themes" do
    visit "/rails/view_components/ui/calendar_component/default"

    expect(page).to have_css("[role='grid']")

    scope = [ "[role='grid']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
