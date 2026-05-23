require "rails_helper"

# Concern-isolation spec for PersonalWorkspaceContext.
#
# Uses the anonymous-controller pattern (mirroring Toastable spec) rather than
# a full request spec because the concern's job is one line: set
# Current.workspace from Current.user&.personal_workspace. Wiring it into real
# account controllers happens in Task 9 of the Settings hub Phase 2 plan;
# integration coverage will live in those controllers' own request specs.
#
# To exercise the before_action through a real request cycle while bypassing
# cookie-based session lookup (which controller specs make awkward), the
# anonymous controller stubs find_session_by_cookie to return a pre-built
# Session record. That is the same surface Authenticatable#resume_session
# uses, so we exercise the genuine before_action chain.
RSpec.describe PersonalWorkspaceContext, type: :controller do
  controller(ApplicationController) do
    include PersonalWorkspaceContext

    def index
      render plain: "workspace_id=#{Current.workspace&.id.inspect}"
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  context "when a user is signed in" do
    let(:user) { create(:user) }
    let(:session_record) do
      user.sessions.create!(user_agent: "RSpec", ip_address: "127.0.0.1")
    end

    before do
      allow_any_instance_of(ApplicationController)
        .to receive(:find_session_by_cookie)
        .and_return(session_record)
    end

    it "sets Current.workspace to the user's personal workspace" do
      get :index

      expect(response.body).to eq("workspace_id=#{user.personal_workspace.id.inspect}")
    end

    context "when the personal workspace has been discarded" do
      before { user.personal_workspace.discard! }

      it "sets Current.workspace to nil (kept scope filters discarded)" do
        get :index

        expect(response.body).to eq("workspace_id=nil")
      end
    end
  end

  context "when no user is signed in" do
    before do
      controller.class.allow_unauthenticated_access
    end

    it "sets Current.workspace to nil without raising" do
      get :index

      expect(response.body).to eq("workspace_id=nil")
    end
  end
end
