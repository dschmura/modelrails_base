# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey enrollment prompt", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "shows the interstitial on first authenticated page load, then never again" do
    # The factory default sets passkey_prompt_seen_at to suppress the
    # interstitial. Reset to nil to make this user interstitial-eligible.
    user.update!(passkey_prompt_seen_at: nil)
    get root_path
    expect(response.body).to include(I18n.t("passkeys.interstitial.title"))
    patch passkey_prompt_path # dismiss / add
    get root_path
    expect(response.body).not_to include(I18n.t("passkeys.interstitial.title"))
  end

  it "does not show it once the user has a passkey" do
    create(:webauthn_credential, user: user)
    get root_path
    expect(response.body).not_to include(I18n.t("passkeys.interstitial.title"))
  end
end
