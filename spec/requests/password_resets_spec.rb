require "rails_helper"

RSpec.describe "PasswordResets", type: :request do
  let(:user) { create(:user) }

  it "issues a set_password magic link and shows the check-email screen" do
    expect {
      post password_reset_path, params: { email_address: user.email_address }
    }.to change { MagicLinkToken.where(email: user.email_address, intent: "set_password").count }.by(1)
    expect(response.body).to include(I18n.t("sessions.check_email.title")).or include("Check your email")
  end
end
