require "rails_helper"

RSpec.describe "Passwords", type: :request do
  let(:user) { create(:user) }

  describe "POST /passwords" do
    it "sends a reset email for valid email" do
      expect {
        post password_path, params: { email_address: user.email_address }
      }.to have_enqueued_mail(AuthenticationMailer, :password_reset_email)
    end

    it "does not reveal whether email exists" do
      post password_path, params: { email_address: "nonexistent@example.com" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /password" do
    before do
      user.generate_reset_password_token!
    end

    context "with valid token and password" do
      it "resets the password" do
        patch password_path, params: {
          token: user.reset_password_token,
          user: {
            password: "NewSecureP@ss123!",
            password_confirmation: "NewSecureP@ss123!"
          }
        }
        expect(response).to redirect_to(new_session_path)
      end

      it "invalidates the token after use" do
        patch password_path, params: {
          token: user.reset_password_token,
          user: {
            password: "NewSecureP@ss123!",
            password_confirmation: "NewSecureP@ss123!"
          }
        }
        expect(user.reload.reset_password_token).to be_nil
      end
    end

    context "with expired token" do
      before { user.update_column(:reset_password_sent_at, 3.hours.ago) }

      it "rejects the reset" do
        patch password_path, params: {
          token: user.reset_password_token,
          user: {
            password: "NewSecureP@ss123!",
            password_confirmation: "NewSecureP@ss123!"
          }
        }
        expect(response).to redirect_to(new_password_path)
      end
    end
  end
end
