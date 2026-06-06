# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the hover_card component.
#
# JS hover-intent: the card opens on hover/focus and closes on leave/blur after a
# short delay (so the pointer can cross to the card and click it). Opening sets
# `data-state="open"` on the wrapper; Escape closes and returns focus to the trigger.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative AAA
# 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Hover card component accessibility", type: :system do
  it "basic: keyboard focus opens a reachable card that passes AAA in both themes" do
    visit "/rails/view_components/ui/hover_card_component/basic"

    # Opens on keyboard focus of the trigger link.
    page.execute_script("document.querySelector('[data-controller=\"floating\"] a').focus()")
    expect(page).to have_css("[data-controller='floating'][data-state='open']")

    # The card's interactive content is present and reachable while open.
    expect(page).to have_css("[data-floating-target='panel']")
    expect(page).to have_link("View profile")

    scope = [ "[data-floating-target='panel']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "closes on Escape and returns focus to the trigger" do
    visit "/rails/view_components/ui/hover_card_component/basic"

    page.execute_script("document.querySelector('[data-controller=\"floating\"] a').focus()")
    expect(page).to have_css("[data-controller='floating'][data-state='open']")

    page.send_keys(:escape)

    expect(page).to have_css("[data-controller='floating'][data-state='closed']")
    expect(page.evaluate_script("document.activeElement.tagName")).to eq("A")
  end
end
