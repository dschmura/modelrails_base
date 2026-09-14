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
    it "shows members with roles" do
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

    it "redirects to root with a not-found alert for a discarded workspace" do
      # record_not_found (ApplicationController) redirects HTML requests to
      # the referer or root; a request spec sends no referer, so root is the
      # one real outcome here (fix round 1, finding 4).
      workspace.discard!
      get operations_workspace_path(workspace)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
    end
  end
end
