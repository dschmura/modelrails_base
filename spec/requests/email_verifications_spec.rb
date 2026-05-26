require "rails_helper"

RSpec.describe "Email Verifications", type: :request do
  let(:user) { create(:user) }
  let(:authentication) { create(:authentication, user: user) }

  describe "GET /email_verification" do
    context "with valid token" do
      it "verifies the email" do
        get email_verification_path(token: authentication.generate_token_for(:email_verification))
        expect(authentication.reload.verified_at).to be_present
      end

      it "redirects with success message" do
        get email_verification_path(token: authentication.generate_token_for(:email_verification))
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(I18n.t("email_verifications.show.success"))
      end
    end

    context "with expired token" do
      it "rejects the verification" do
        token = authentication.generate_token_for(:email_verification)
        travel(Authentication::TOKEN_LIFETIME + 1.minute) do
          get email_verification_path(token: token)
        end
        expect(authentication.reload.verified_at).to be_nil
      end
    end

    context "with invalid token" do
      it "rejects the verification" do
        get email_verification_path(token: "invalid")
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end
  end
end
