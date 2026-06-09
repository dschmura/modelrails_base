# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + BEHAVIOR proof for the carousel component.
#
# We assert OUTCOMES, not wiring: Next actually translates the track and moves
# aria-current; the 2.2.2 pause mechanism flips the live region to polite.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Carousel component accessibility", type: :system do
  let(:scope) { [ "[data-test='carousel']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: carousel group + slide labels; AAA in both themes" do
    visit "/rails/view_components/ui/carousel_component/default"

    expect(page).to have_css("[role='group'][aria-roledescription='carousel'][aria-label='Featured photos']")
    expect(page).to have_css("[aria-roledescription='slide']", count: 3)
    expect_aaa_in_both_themes
  end

  it "Next actually translates the track and moves aria-current (outcome, not wiring)" do
    visit "/rails/view_components/ui/carousel_component/default"

    expect(page).to have_css("[data-carousel-target='dots'] button[aria-current='true']:first-child")

    find("button[aria-label='Next slide']").click

    transform = page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-carousel-target=track]')).transform"
    )
    expect(transform).not_to eq("none") # the track moved

    expect(page).to have_css("[data-carousel-target='dots'] button:nth-child(2)[aria-current='true']")
  end

  it "autoplay: pause flips the live region to polite (WCAG 2.2.2 mechanism)" do
    visit "/rails/view_components/ui/carousel_component/autoplay"

    find("button[data-carousel-target='pause']").click

    expect(page).to have_css(
      "[data-carousel-target='status'][aria-live='polite']", visible: :all
    )
  end

  it "autoplay: passes AAA in both themes" do
    visit "/rails/view_components/ui/carousel_component/autoplay"

    expect(page).to have_css("[role='group'][aria-roledescription='carousel'][aria-label='Auto gallery']")
    expect_aaa_in_both_themes
  end
end
