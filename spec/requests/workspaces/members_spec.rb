require "rails_helper"

RSpec.describe "Workspace Members", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  describe "GET /workspaces/:workspace_slug/members" do
    it "lists workspace members" do
      get workspace_members_path(workspace)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.full_name)
    end

    it "shows member roles" do
      get workspace_members_path(workspace)
      expect(response.body).to include("Owner")
    end
  end
end
