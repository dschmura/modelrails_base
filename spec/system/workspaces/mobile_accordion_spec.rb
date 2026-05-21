# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport behavior for the workspace-scoped (application layout)
# header accordion (below md). Path Z drawer replacement: the header
# expands downward to reveal the _workspace_sidebar partial inline via
# content_for(:mobile_menu_sidebar). Mirrors the settings accordion spec.
RSpec.describe "Workspace pages — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
  end

  it "shows the hamburger and reveals the workspace sidebar on tap" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      expect(page).to have_link(I18n.t("workspaces.sidebar.overview"))
      expect(page).to have_link(I18n.t("workspaces.sidebar.settings"))
    end
  end

  it "auto-closes on link tap inside the panel" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      click_link I18n.t("workspaces.sidebar.settings")
    end
    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden", visible: :all)
  end

  it "passes axe AAA both themes both states" do
    visit workspace_path(workspace)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (collapsed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("navigation.mobile_menu.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (expanded):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
