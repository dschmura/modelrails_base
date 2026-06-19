require "rails_helper"

RSpec.describe "Project tools settings", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders the toggle form" do
    get edit_workspace_project_tools_path(workspace, project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Docs &amp; Files")
  end

  it "updates enabled_tools, intersected with toggleable keys" do
    patch workspace_project_tools_path(workspace, project),
      params: { project: { enabled_tools: [ "docs", "bogus" ] } }
    expect(project.reload.enabled_tools).to eq([ "docs" ])
    expect(response).to redirect_to(edit_workspace_project_tools_path(workspace, project))
  end

  it "treats an absent checkbox group as all-off" do
    patch workspace_project_tools_path(workspace, project), params: { project: {} }
    expect(project.reload.enabled_tools).to eq([])
  end
end
