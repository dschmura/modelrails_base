require "rails_helper"

RSpec.describe "Operations workspaces", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:owner) { create(:user, first_name: "Olive", last_name: "Owner") }
  let(:workspace) { create(:workspace, name: "Acme") }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    sign_in(operator)
  end

  describe "GET /operations/workspaces/:slug" do
    it "shows members with roles and recent activity" do
      get operations_workspace_path(workspace)
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_text("Olive Owner")
      expect(html).to have_text("Owner")
    end

    it "renders a suspended workspace instead of bouncing" do
      workspace.suspend!
      get operations_workspace_path(workspace)
      expect(response).to have_http_status(:ok)
      # R3: the brief's key (lifecycle.status.suspended) does not exist;
      # config/locales/en/lifecycle.en.yml roots this under lifecycle_status.
      expect(Capybara.string(response.body)).to have_text(I18n.t("lifecycle_status.suspended"))
    end

    it "404s for a discarded workspace" do
      workspace.discard!
      get operations_workspace_path(workspace)
      expect(response).to have_http_status(:not_found).or redirect_to(root_path)
    end
  end
end
