# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + BEHAVIOR proof for the gallery (lightbox) component.
#
# The lightbox is the shared native <dialog> driven by the reused `modal`
# controller: a trigger click runs `gallery#open` (swaps the dialog image to the
# clicked thumbnail) then `modal#open` (showModal() — moves focus into the dialog).
# Escape fires the native cancel event, which closes and restores focus to the
# trigger. We OPEN it via the real trigger and audit the LIVE dialog, mirroring the
# dialog 0b idiom (spec/system/ui/dialog_component_spec.rb).
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Gallery component accessibility", type: :system do
  let(:scope) { [ "[data-test='gallery']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: three focusable button triggers + the shared dialog; AAA in both themes" do
    visit "/rails/view_components/ui/gallery_component/default"

    expect(page).to have_css("[data-test='gallery'] button[aria-label]", count: 3)
    expect(page).to have_css("dialog[data-modal-target='dialog']", visible: :all)
    expect_aaa_in_both_themes
  end

  it "opens the lightbox via keyboard and moves focus into the dialog (2.1.1)" do
    visit "/rails/view_components/ui/gallery_component/default"

    # Keyboard-operability: the <button> opens the dialog on Return.
    first_trigger = find("[data-test='gallery'] button", match: :first)
    first_trigger.send_keys(:return)

    expect(page).to have_css("dialog[open]")

    # showModal() moved focus inside the dialog.
    in_dialog = page.evaluate_script("document.activeElement.closest('dialog') !== null")
    expect(in_dialog).to be(true)

    # gallery#open swapped the shared dialog image to the clicked thumbnail.
    expect(page).to have_css("dialog[open] img[alt='Forest canopy']")
  end

  it "closes on Escape and restores focus to the trigger" do
    visit "/rails/view_components/ui/gallery_component/default"

    first_trigger = find("[data-test='gallery'] button", match: :first)
    first_trigger.click
    expect(page).to have_css("dialog[open]")

    page.send_keys(:escape)

    expect(page).to have_no_css("dialog[open]")

    # The modal controller restored focus to the opening trigger.
    restored_label = page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    expect(restored_label).to eq(first_trigger["aria-label"])
  end
end
