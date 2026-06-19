require "rails_helper"

RSpec.describe "Personal workspace Customize", type: :system do
  # The Customize button on the personal-workspace Overview opens a modal
  # where the owner can rename the workspace (and change the logo). This
  # replaces the old "Settings" sidebar entry for personal workspaces
  # (workspace-settings IA Phase 1 Task 2).

  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  it "renames the workspace in-context from the Overview" do
    visit workspace_path(user.workspaces.kept.sole)

    click_on I18n.t("workspaces.overview.customize.open")
    fill_in I18n.t("workspaces.overview.customize.name_label"), with: "My Stuff"
    click_on I18n.t("workspaces.overview.customize.save")

    expect(page).to have_css("h1", text: "My Stuff")
  end

  it "exposes the logo-picker trigger inside the Customize modal" do
    visit workspace_path(user.workspaces.kept.sole)

    click_on I18n.t("workspaces.overview.customize.open")

    expect(page).to have_css("dialog[open]")
    # The logo-trigger button (aria-label, no visible text) is inside the open dialog
    within("dialog[open]") do
      expect(page).to have_css("button[aria-label='#{I18n.t("workspaces.brandings.edit.change_logo")}']")
    end
  end
end
