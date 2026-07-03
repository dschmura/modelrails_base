require "rails_helper"

RSpec.describe "Projects index archived section", type: :system do
  let(:creator) { create(:user) }
  let(:workspace) { create(:workspace) }
  let(:active_project) { create(:project, workspace: workspace, created_by: creator, name: "Live Project") }
  let(:archived_project) { create(:project, workspace: workspace, created_by: creator, name: "Old Project") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:membership, :owner, user: creator, workspace: workspace)
    create(:project_membership, :creator, project: active_project, user: creator)
    create(:project_membership, :creator, project: archived_project, user: creator)
    archived_project.archive!
    sign_in_via_form(creator)
  end

  it "moves archived projects out of the main list into the Archived section" do
    visit workspace_projects_path(workspace)
    within("[data-test='archived-projects']") do
      expect(page).to have_text("Old Project")
    end
    expect(page).to have_no_link("Old Project", href: workspace_project_path(workspace, archived_project))
  end

  it "restores from the Archived section" do
    visit workspace_projects_path(workspace)
    within("[data-test='archived-projects']") { click_button I18n.t("lifecycle.restore") }
    expect(page).to have_text(I18n.t("workspaces.projects.unarchive.success"))
    expect(archived_project.reload).not_to be_archived
  end

  it "keeps the archived project's own page reachable, with a Restore banner" do
    visit workspace_project_path(workspace, archived_project)
    within("[data-test='archived-banner']") do
      expect(page).to have_text(I18n.t("workspaces.projects.archived_banner"))
      click_button I18n.t("lifecycle.restore")
    end
    expect(page).to have_text(I18n.t("workspaces.projects.unarchive.success"))
    expect(archived_project.reload).not_to be_archived
  end

  it "passes axe AAA in both themes with an archived project present" do
    visit workspace_projects_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
