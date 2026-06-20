require "rails_helper"

RSpec.describe "Client invitations (team side)", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user, clientside_enabled: true).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders the invite form when Clientside is on" do
    get new_workspace_project_client_invitation_path(workspace, project)
    expect(response).to have_http_status(:ok)
  end

  it "redirects to settings when Clientside is off" do
    project.update!(clientside_enabled: false)
    get new_workspace_project_client_invitation_path(workspace, project)
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))
  end

  it "sends a client invitation" do
    expect {
      post workspace_project_client_invitations_path(workspace, project),
        params: { client_invitation: { email: "dana@bigco.com", company_name: "BigCo" } }
    }.to change { project.invitations.where.not(company_name: nil).count }.by(1)
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))
  end

  it "re-renders on an invalid email" do
    post workspace_project_client_invitations_path(workspace, project),
      params: { client_invitation: { email: "", company_name: "BigCo" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 422 and does not create a second invitation when email already has a pending invite" do
    post workspace_project_client_invitations_path(workspace, project),
      params: { client_invitation: { email: "dana@bigco.com", company_name: "BigCo" } }
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))

    expect {
      post workspace_project_client_invitations_path(workspace, project),
        params: { client_invitation: { email: "dana@bigco.com", company_name: "BigCo" } }
    }.not_to change { project.invitations.where.not(company_name: nil).count }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context "as a viewer (no manage_members permission)" do
    let(:viewer) { create(:user) }
    let!(:viewer_role) do
      Role.find_or_create_by!(slug: "viewer", workspace_id: nil) do |r|
        r.name = "Viewer"
        r.permissions = {}
      end
    end

    before do
      workspace.memberships.create!(user: viewer, role: viewer_role)
      project.project_memberships.create!(user: viewer, role: "viewer")
      sign_in(viewer)
    end

    it "denies new (redirect)" do
      get new_workspace_project_client_invitation_path(workspace, project)
      expect(response).to have_http_status(:redirect)
    end

    it "denies create (redirect) and creates no invitation" do
      expect {
        post workspace_project_client_invitations_path(workspace, project),
          params: { client_invitation: { email: "attacker@example.com", company_name: "Evil Corp" } }
      }.not_to change { Invitation.count }
      expect(response).to have_http_status(:redirect)
    end
  end
end
