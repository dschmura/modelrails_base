# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport behavior for the Settings hub off-canvas drawer (below md).
# SUPERSEDED by Path Z header-accordion pattern; see
# spec/system/settings/mobile_accordion_spec.rb. This file is pended and
# scheduled for deletion in Path Z Task 6 once the locale-key cleanup
# and final cleanup pass complete.
RSpec.describe "Settings hub — mobile drawer", type: :system, js: true do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    skip "superseded by Path Z mobile_accordion_spec — deleted in Task 6"

    sign_in_via_form(user)
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
  end

  it "shows the hamburger toggle below md" do
    visit edit_account_profile_path
    expect(page).to have_button(I18n.t("settings.mobile_drawer.open"))
  end

  it "opens the drawer when the toggle is clicked" do
    visit edit_account_profile_path
    click_button I18n.t("settings.mobile_drawer.open")
    expect(page).to have_css("[data-drawer-state='open']")
  end

  it "closes the drawer when a sidebar link is clicked (auto-dismiss on nav)" do
    visit edit_account_profile_path
    click_button I18n.t("settings.mobile_drawer.open")

    within("[data-settings-drawer-target='panel']") do
      click_link I18n.t("settings.sidebar.items.notifications")
    end

    expect(page).to have_current_path(edit_account_notification_preferences_path)
    expect(page).to have_css("[data-drawer-state='closed']")
  end

  it "passes axe-core at WCAG 2.2 AAA both states (closed + open)" do
    visit edit_account_profile_path

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations (closed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("settings.mobile_drawer.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations (open):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
