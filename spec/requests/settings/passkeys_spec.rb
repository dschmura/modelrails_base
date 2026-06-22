require "rails_helper"

RSpec.describe "Settings::Passkeys", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "lists the user's kept passkeys" do
    create(:webauthn_credential, user: user, nickname: "My Laptop")
    get settings_passkeys_path
    expect(response.body).to include("My Laptop")
  end

  it "soft-discards a passkey on destroy (magic-link remains the floor)" do
    cred = create(:webauthn_credential, user: user)
    delete settings_passkey_path(cred)
    expect(cred.reload).to be_discarded
  end

  it "renders the Add a passkey control" do
    get settings_passkeys_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[data-controller~="webauthn"]')).to be_present
    expect(doc.at_css('[data-action~="webauthn#register"]')).to be_present
  end

  it "renders remove aria-label for each credential" do
    create(:webauthn_credential, user: user, nickname: "Touch ID")
    get settings_passkeys_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[aria-label="Remove passkey: Touch ID"]')).to be_present
  end
end
