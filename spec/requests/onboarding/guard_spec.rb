require "rails_helper"

RSpec.describe "Onboarding guard", type: :request do
  context "under :none posture with a not-onboarded user" do
    before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

    it "redirects app pages into onboarding" do
      user = create(:user, :with_zero_workspaces)
      sign_in(user)
      get workspaces_path
      expect(response).to redirect_to(onboarding_path)
    end

    it "does not redirect the email-verification screen (escape hatch)" do
      user = create(:user, :with_zero_workspaces, :with_email_auth)
      sign_in(user)
      get new_email_verification_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "never redirects under non-:none postures" do
    allow(TenancyConfig).to receive(:onboarding).and_return(:personal)
    user = create(:user, :with_zero_workspaces)
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "does not redirect an already-onboarded :none user" do
    allow(TenancyConfig).to receive(:onboarding).and_return(:none)
    user = create(:user, :with_zero_workspaces, onboarded_at: Time.current)
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end
end
