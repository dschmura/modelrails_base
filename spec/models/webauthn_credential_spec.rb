require "rails_helper"

RSpec.describe WebauthnCredential do
  let(:credential) { create(:webauthn_credential, sign_count: 5) }

  it "advances sign_count and records last_used_at" do
    credential.advance_sign_count!(6)
    expect(credential.reload.sign_count).to eq(6)
    expect(credential.last_used_at).to be_present
  end

  it "raises ClonedAuthenticator when the count does not advance" do
    expect { credential.advance_sign_count!(5) }.to raise_error(Passkeys::ClonedAuthenticator)
    expect(credential.reload.sign_count).to eq(5)
  end

  it "is discardable (kept scope excludes discarded)" do
    credential.discard!
    expect(WebauthnCredential.kept).not_to include(credential)
  end
end
