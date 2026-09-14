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
      # Scoped to the suspended row (fix round 1, finding 6): have_text alone
      # passes wherever "Locked" appears on the page, so this proves the
      # label belongs to Frozen Co specifically, not merely to the page.
      frozen_row = html.find("tr", text: "Frozen Co")
      expect(frozen_row).to have_text(I18n.t("lifecycle_status.suspended"))
      acme_row = html.find("tr", text: "Acme")
      expect(acme_row).not_to have_text(I18n.t("lifecycle_status.suspended"))
    end

    it "never establishes a workspace context" do
      # A spy on the setter, not a post-hoc read (fix round 1, finding 1):
      # ActiveSupport::CurrentAttributes is reset by the executor at the end
      # of every request, so Current.workspace already reads nil after ANY
      # request whether or not this controller ever assigned it — a probe
      # against a workspace-scoped route proved that read passes vacuously.
      # Observing the request in flight is the only way this assertion can
      # fail on a direct assignment.
      allow(Current).to receive(:workspace=).and_call_original
      get operations_workspaces_path
      expect(Current).not_to have_received(:workspace=)
      expect(session[:current_workspace_id]).to be_nil
    end

    it "reaches the area with onboarding incomplete rather than being funneled into the wizard" do
      # RequiresOnboarding#require_onboarding only funnels under the :none
      # preset (config/initializers/tenancy.rb) — the default :personal
      # preset makes this guard inert regardless of skip_onboarding_requirement,
      # so exercising it here means the example proves the class method is
      # doing real work, not asserting an already-inert path (fix round 1,
      # finding 7).
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      operator.update!(onboarded_at: nil)
      get operations_workspaces_path
      expect(response).to have_http_status(:ok)
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
