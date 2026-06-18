require "rails_helper"

RSpec.describe "Me (identity home)", type: :request do
  it "redirects unauthenticated visitors to sign in" do
    get me_path
    expect(response).to redirect_to(new_session_path)
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    it "renders the identity home" do
      get me_path
      expect(response).to have_http_status(:ok)
    end

    it "renders for a workspaceless user (:none safety)" do
      get me_path
      sign_in(create(:user, :with_zero_workspaces))
      get me_path
      expect(response).to have_http_status(:ok)
    end
  end
end
