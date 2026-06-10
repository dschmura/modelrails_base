# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the accordion component.
#
# Accordion is native <details>/<summary> — the summary is the focusable disclosure
# control carrying the AAA `focus-ring`. We scope the audit to the <details> subtree
# (the summaries are always visible; open rows also expose their content) so we audit
# the COMPONENT, not the preview-host chrome (which emits non-WCAG landmark/heading
# advisories). No color-contrast exclude is added: a real contrast failure on a
# summary or visible content would still fail this spec.
RSpec.describe "Accordion component accessibility", type: :system do
  %w[default exclusive rich_content].each do |scenario|
    it "#{scenario} renders disclosure rows and passes AAA in both themes" do
      visit "/rails/view_components/ui/accordion_component/#{scenario}"

      expect(page).to have_css("details summary")

      # Scope to the disclosure rows, NOT the host chrome. No color-contrast exclude.
      scope = [ "details" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
