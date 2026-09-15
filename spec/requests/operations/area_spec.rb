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

  # Item 7a (fix round 1): titled "EVERY operations route" but exercised two
  # GETs; Tasks 13-14 added four mutating routes and none was in it — the
  # behaviour was already correct (require_operator gates before any action
  # logic runs), only the claim was false.
  it "answers 404 to a signed-in non-operator on every operations route" do
    other_operatorship = Operatorship.grant!(user: create(:user))
    sign_in(member)

    get operations_root_path
    expect(response).to have_http_status(:not_found)
    get operations_workspaces_path
    expect(response).to have_http_status(:not_found)

    post operations_operatorships_path, params: { email: member.email_address }
    expect(response).to have_http_status(:not_found)
    delete operations_operatorship_path(other_operatorship)
    expect(response).to have_http_status(:not_found)
    delete operations_user_lock_path(member)
    expect(response).to have_http_status(:not_found)
    post operations_user_suspension_path(member)
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

    it "lets an un-onboarded operator finish reauthentication and land back on /operations" do
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      operator.update!(onboarded_at: nil)
      operator.sessions.update_all(reauthenticated_at: nil)

      get operations_workspaces_path
      expect(response).to redirect_to(new_settings_reauthentication_path)

      get new_settings_reauthentication_path
      expect(response).to have_http_status(:ok)

      post settings_reauthentication_path, params: { password: "SecureP@ssw0rd123!" }
      expect(response).to redirect_to(operations_workspaces_path)
    end

    it "requires a fresh reauthentication" do
      operator.sessions.update_all(reauthenticated_at: nil)
      get operations_workspaces_path
      expect(response).to redirect_to(new_settings_reauthentication_path)
      expect(session[:return_to_after_reauthentication]).to eq(operations_workspaces_path)
    end

    # Rails routes HEAD to the GET action, but request.get? is false for HEAD
    # — so the GET-correct return-to branch (R17) silently took the referer
    # path instead. Brakeman's VerbConfusion check caught this on pre-push,
    # after the suite had run clean all arc: it is not an rspec-visible bug.
    it "treats a HEAD request like the GET it is routed as" do
      operator.sessions.update_all(reauthenticated_at: nil)
      head operations_workspaces_path
      expect(session[:return_to_after_reauthentication]).to eq(operations_workspaces_path)
    end

    it "renders the operations banner so the area is unmistakable" do
      get operations_workspaces_path
      expect(Capybara.string(response.body)).to have_text(I18n.t("operations.area.banner"))
    end

    # Fix round 2, item 2 (R24): the same preflight list-style:none trap as
    # the activity feed's <ol> — this <ul> is the area's other raw list.
    it "restores list semantics on the nav's raw <ul>" do
      get operations_workspaces_path
      expect(Capybara.string(response.body)).to have_css('nav ul[role="list"]')
    end

    # WCAG 2.4.8 Location (AAA, outside the axe tag set). The cue matches
    # shared/_settings_sidebar_item — a filled surface, a weight bump and a
    # heading-colour shift together — rather than weight alone: this app's
    # other horizontal navs all use that treatment, and one step of weight at
    # 14px is a weak signal on its own. text-text-heading on bg-surface-sunken
    # is a proven AAA pairing (tokens/_semantic.css, ~21:1).
    it "marks the current page in the nav with aria-current and the house visible cue" do
      get operations_workspaces_path
      html = Capybara.string(response.body)

      current_link = html.find("nav a", text: I18n.t("operations.nav.workspaces"))
      expect(current_link["aria-current"]).to eq("page")
      expect(current_link[:class]).to include("bg-surface-sunken", "font-semibold", "text-text-heading")

      other_link = html.find("nav a", text: I18n.t("operations.nav.users"))
      expect(other_link["aria-current"]).to be_nil
      expect(other_link[:class]).not_to include("bg-surface-sunken")
    end
  end
end
