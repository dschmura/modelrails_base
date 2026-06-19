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

  # Pundit wiring: a workspace member who does not hold the :creator
  # project-membership role has no update? permission. Proves authorize is
  # actually invoked — removing authorize from the controller would let
  # these requests succeed.
  describe "authorization: non-managing member is denied" do
    let(:viewer) { create(:user) }

    before do
      # Give the viewer a workspace membership (member role — no manage_projects).
      workspace.memberships.create!(
        user: viewer,
        role: Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member"; r.permissions = {} }
      )
      # Give the viewer a project membership as a viewer, not a creator.
      project.project_memberships.create!(user: viewer, role: "viewer")
      sign_in(viewer)
    end

    it "GET edit redirects with not_authorized flash" do
      get edit_workspace_project_tools_path(workspace, project)
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end

    it "PATCH update redirects and leaves enabled_tools unchanged" do
      original_tools = project.reload.enabled_tools.dup
      patch workspace_project_tools_path(workspace, project),
        params: { project: { enabled_tools: [] } }
      expect(response).to have_http_status(:redirect)
      expect(project.reload.enabled_tools).to eq(original_tools)
    end
  end
end
