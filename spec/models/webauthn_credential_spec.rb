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

  # Platform passkeys (Apple/Google) always report sign_count 0 — per WebAuthn
  # §7.2 that means "counter unsupported", NOT a clone. Must accept it on every
  # sign-in, or counter-less authenticators can never sign in twice.
  it "accepts a zero sign_count without flagging a clone (counter-less passkey)" do
    zero = create(:webauthn_credential, sign_count: 0)
    expect { zero.advance_sign_count!(0) }.not_to raise_error
    expect(zero.reload.last_used_at).to be_present
    expect(zero.sign_count).to eq(0)
  end

  it "does not lower a stored counter when the authenticator reports zero" do
    credential.advance_sign_count!(0)
    expect(credential.reload.sign_count).to eq(5)
    expect(credential.last_used_at).to be_present
  end

  it "is discardable (kept scope excludes discarded)" do
    credential.discard!
    expect(WebauthnCredential.kept).not_to include(credential)
  end
end
