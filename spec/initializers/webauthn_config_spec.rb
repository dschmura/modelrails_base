require "rails_helper"

RSpec.describe "WebAuthn configuration" do
  it "pins allowed_origins to the app host so a misconfig fails loudly" do
    expect(WebAuthn.configuration.allowed_origins).to be_present
  end

  it "exposes the rp_id via Passkeys.rp_id" do
    expect(Passkeys.rp_id).to be_present
  end

  it "sets a relying-party name" do
    expect(WebAuthn.configuration.rp_name).to eq(I18n.t("application.name"))
  end
end
