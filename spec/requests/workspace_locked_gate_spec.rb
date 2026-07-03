require "rails_helper"

RSpec.describe "Locked workspace gate", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }

  before do
    create(:membership, :owner, user: user, workspace: workspace)
    sign_in(user)
    workspace.suspend!
  end

  it "redirects workspace pages to the index with the locked notice" do
    get workspace_path(workspace)
    expect(response).to redirect_to(workspaces_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.locked_notice"))
  end

  it "gates nested workspace-scoped controllers too" do
    get workspace_projects_path(workspace)
    expect(response).to redirect_to(workspaces_path)
  end

  it "renders the index fine with a locked workspace present (nil-gate regression)" do
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "blocks the archive action (gate runs before the action)" do
    patch archive_workspace_path(workspace)
    expect(response).to redirect_to(workspaces_path)
    expect(workspace.reload).not_to be_archived
  end
end
