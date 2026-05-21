# frozen_string_literal: true

require "rails_helper"

# Path Z: the shared header's mobile-menu panel auto-dismisses when an
# anchor inside the expanded panel is clicked. The Stimulus action and
# the data-action wiring on the menu element ship together as part of
# the header-accordion pattern. The accordion specs
# (spec/system/settings/mobile_accordion_spec.rb and
# spec/system/workspaces/mobile_accordion_spec.rb) exercise the wired
# end-to-end behavior under the real accordion content; this spec
# documents the auto-close intent on the bare header alone.
RSpec.describe "Shared header — mobile menu auto-close", type: :system, js: true do
  let(:user) { create(:user) }

  before do
    sign_in_via_form(user)
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
  end

  it "wires closeOnLinkClick on the menu panel and dismisses on link tap" do
    visit root_path

    # The menu element should declare the auto-close action so any anchor
    # inside it dismisses the panel via event bubbling — no per-link wiring.
    expect(page).to have_css(
      "[data-mobile-menu-target='menu'][data-action*='mobile-menu#closeOnLinkClick']",
      visible: :all
    )

    # Open the panel, then dispatch a click on an anchor inside it.
    find("[data-mobile-menu-target='button']").click
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")

    page.execute_script(<<~JS)
      const link = document.querySelector("[data-mobile-menu-target='menu'] a")
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
    JS

    # The closeOnLinkClick handler runs synchronously on bubble; before any
    # Turbo navigation completes, the menu should already carry .hidden.
    final_classes = page.evaluate_script(
      "document.querySelector(\"[data-mobile-menu-target='menu']\").className"
    )
    expect(final_classes).to include("hidden")
  end
end
