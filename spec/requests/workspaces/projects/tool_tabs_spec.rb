require "rails_helper"

RSpec.describe "Project tool tabs", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/projects/:project_slug to sign in" do
      get workspace_project_path(workspace_slug: "any-slug", slug: "any-project")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }
    let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
    let(:project) { create(:project, workspace: workspace, created_by: user) }
    let!(:creator_pm) { create(:project_membership, :creator, project: project, user: user) }

    before do
      Current.workspace = workspace
      sign_in(user)
    end

    it "renders a Docs tab linking to the project's resources" do
      get workspace_project_path(workspace, project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(workspace_project_resources_path(workspace, project))
      expect(response.body).to include("Docs &amp; Files")
    end

    it "omits a tool's tab when it is disabled" do
      project.update!(enabled_tools: [])
      get workspace_project_path(workspace, project)
      expect(response.body).not_to include(workspace_project_resources_path(workspace, project))
    end
  end
end
