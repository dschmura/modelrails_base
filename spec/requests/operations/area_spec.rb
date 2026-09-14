require "rails_helper"

RSpec.describe "Operations area", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:member) { create(:user) }
  let!(:workspace) { create(:workspace, name: "Acme") }
  let!(:suspended) { create(:workspace, name: "Frozen Co").tap(&:suspend!) }

  it "redirects anonymous visitors to sign in" do
    get operations_root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "answers 404 to a signed-in non-operator on every operations route" do
    sign_in(member)
    get operations_root_path
    expect(response).to have_http_status(:not_found)
    get operations_workspaces_path
    expect(response).to have_http_status(:not_found)
  end

  context "as an operator" do
    before { sign_in(operator) }

    it "lists every kept workspace, suspended ones included and labelled" do
      get operations_workspaces_path
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_text("Acme")
      expect(html).to have_text("Frozen Co")
      # R3: the brief's key (lifecycle.status.suspended) does not exist.
      # config/locales/en/lifecycle.en.yml roots this under lifecycle_status.
      expect(html).to have_text(I18n.t("lifecycle_status.suspended"))
    end

    it "never establishes a workspace context" do
      get operations_workspaces_path
      expect(Current.workspace).to be_nil
      expect(session[:current_workspace_id]).to be_nil
    end

    it "requires a fresh reauthentication" do
      operator.sessions.update_all(reauthenticated_at: nil)
      get operations_workspaces_path
      expect(response).to redirect_to(new_settings_reauthentication_path)
    end

    it "renders the operations banner so the area is unmistakable" do
      get operations_workspaces_path
      expect(Capybara.string(response.body)).to have_text(I18n.t("operations.area.banner"))
    end
  end
end
