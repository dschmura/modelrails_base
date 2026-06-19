require "rails_helper"

RSpec.describe "Onboarding · tools step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let!(:project) { create(:project, workspace: workspace) }

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    project.project_memberships.create!(user: user, role: "creator")
    sign_in(user)
  end

  # A second toggleable tool so the registry offers a real choice. Restored by
  # the registry's own save/restore pattern is not active here, so undo it.
  def with_two_tools
    extra = ProjectTools::Registry.register(key: :extra, path_helper: :workspace_project_resources_path)
    yield
  ensure
    ProjectTools::Registry.all.delete(extra)
  end

  it "renders the tools step when the registry offers more than one tool" do
    with_two_tools do
      get new_onboarding_tools_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "saves the selected tools and advances to the team step" do
    with_two_tools do
      post onboarding_tools_path, params: { project: { enabled_tools: [ "docs" ] } }
      expect(project.reload.enabled_tools).to eq([ "docs" ])
      expect(response).to redirect_to(new_onboarding_team_path)
    end
  end

  it "project create skips the tools step when only one tool is toggleable" do
    # Default registry (docs only) → project#create goes straight to team.
    get new_onboarding_project_path
    post onboarding_project_path, params: { project: { name: "Acme Website" } }
    expect(response).to redirect_to(new_onboarding_team_path)
  end

  it "project create routes through the tools step when >1 tool is toggleable" do
    with_two_tools do
      get new_onboarding_project_path
      post onboarding_project_path, params: { project: { name: "Acme Two" } }
      expect(response).to redirect_to(new_onboarding_tools_path)
    end
  end
end
