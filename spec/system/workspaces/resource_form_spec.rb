# frozen_string_literal: true

require "rails_helper"

# W1-6 (#729, PR-B): the resource forms bypassed UI::FormBuilder — native
# `required` let the browser block an empty submit with a transient bubble,
# so the server-rendered error path (error summary + inline errors) every
# sibling form uses could never render. These examples exercise that path
# end-to-end; they FAIL on the pre-migration markup because the bubble
# blocks the submit and no request reaches the server.
RSpec.describe "Resource forms", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before do
    sign_in_via_form(user)
  end

  it "renders the error summary when a new document is submitted without a title" do
    visit new_workspace_project_resource_path(workspace, project)

    click_button I18n.t("workspaces.projects.resources.new.submit")

    within("[role='alert']") do
      expect(page).to have_link("Title can't be blank", href: "#resource_title")
    end
  end

  # #753: the 422 error state is where AT users get stuck, and it was the one
  # new surface never contrast-checked — axe both themes on the live render.
  it "passes axe in both themes on the 422 error render" do
    visit new_workspace_project_resource_path(workspace, project)
    click_button I18n.t("workspaces.projects.resources.new.submit")
    expect(page).to have_css("[role='alert']")

    scope = [ "#main-content" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "creates a document from a valid title-only submit" do
    visit new_workspace_project_resource_path(workspace, project)

    fill_in I18n.t("workspaces.projects.resources.new.title_label"), with: "Kickoff notes"
    click_button I18n.t("workspaces.projects.resources.new.submit")

    expect(page).to have_text(I18n.t("workspaces.projects.resources.create.success"))
    expect(page).to have_text("Kickoff notes")
  end

  describe "editing" do
    let!(:resource) do
      create(:resource, project: project, created_by: user, title: "Original title")
    end

    it "renders the error summary when the title is cleared" do
      visit edit_workspace_project_resource_path(workspace, project, resource)

      fill_in I18n.t("workspaces.projects.resources.edit.title_label"), with: ""
      click_button I18n.t("workspaces.projects.resources.edit.submit")

      within("[role='alert']") do
        expect(page).to have_link("Title can't be blank", href: "#resource_title")
      end
    end
  end
end
