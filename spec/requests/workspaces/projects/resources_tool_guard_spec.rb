require "rails_helper"

RSpec.describe "Docs tool enablement guard", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "allows the resources index when docs is enabled" do
    get workspace_project_resources_path(workspace, project)
    expect(response).to have_http_status(:ok)
  end

  it "redirects to the project when docs is disabled" do
    project.update!(enabled_tools: [])
    get workspace_project_resources_path(workspace, project)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end
end
