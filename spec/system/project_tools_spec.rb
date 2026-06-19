# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project tools", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before do
    create(:project_membership, :creator, project: project, user: user)
    sign_in_via_form(user)
  end

  it "shows the Docs & Files tab and toggling it in settings hides it (AAA)" do
    # Project home — Docs tab should be present by default
    visit workspace_project_path(workspace, project)
    expect(page).to have_link("Docs & Files")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      axe_violations_in_both_themes(axe_options).join("\n")

    # Tools settings page — AAA-clean, then disable Docs
    visit edit_workspace_project_tools_path(workspace, project)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      axe_violations_in_both_themes(axe_options).join("\n")
    uncheck "tool_docs"
    click_button "Save tools"

    # Project home — Docs tab should no longer appear
    visit workspace_project_path(workspace, project)
    expect(page).to have_no_link("Docs & Files")
  end
end
