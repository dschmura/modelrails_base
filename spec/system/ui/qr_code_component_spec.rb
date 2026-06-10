# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the qr_code component.
# A role=img container with an accessible name describing the encoded payload.
RSpec.describe "QR code component accessibility", type: :system do
  it "default renders a labelled QR graphic and passes AAA in both themes" do
    visit "/rails/view_components/ui/qr_code_component/default"

    expect(page).to have_css("[role='img']")

    scope = [ "[role='img']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
