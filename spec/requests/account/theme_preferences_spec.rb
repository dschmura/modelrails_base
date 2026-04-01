require "rails_helper"

RSpec.describe "Account Theme Preferences", type: :request do
  describe "unauthenticated access" do
    it "redirects PATCH /account/theme_preference to sign in" do
      patch account_theme_preference_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before do
      sign_in(user)
      user.create_preferences!(theme: "system")
    end

    describe "PATCH /account/theme_preference" do
      it "updates the theme" do
        patch account_theme_preference_path, params: { user_preferences: { theme: "dark" } }
        expect(user.preferences.reload.theme).to eq("dark")
      end

      it "responds with turbo stream" do
        patch account_theme_preference_path,
          params: { user_preferences: { theme: "dark" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    describe "PATCH with invalid theme" do
      it "redirects with alert for invalid theme" do
        patch account_theme_preference_path, params: { user_preferences: { theme: "neon" } }
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end
end
