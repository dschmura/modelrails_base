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

  describe "audit trail" do
    let(:credential) { create(:webauthn_credential) }

    it "writes user.passkey_added on create, in-transaction" do
      expect { create(:webauthn_credential) }
        .to change { ActivityLog.where(action: "user.passkey_added", visibility: "personal").count }.by(1)
    end

    it "writes user.passkey_removed on discard" do
      credential
      expect { credential.discard! }
        .to change { ActivityLog.where(action: "user.passkey_removed", trackable: credential.user).count }.by(1)
    end

    it "does not write a row when undiscarding a passkey" do
      credential.discard!
      expect { credential.undiscard! }.not_to change { ActivityLog.count }
    end

    it "does not write a row when advancing sign_count" do
      cred = create(:webauthn_credential, sign_count: 5)
      expect { cred.advance_sign_count!(6) }.not_to change { ActivityLog.count }
    end

    it "rolls back the credential when the audit write fails" do
      # Ruling R7 (spec/models/user_spec.rb carries the same precedent):
      # materialize the user BEFORE installing the stub. Creating a
      # WebauthnCredential via the factory also creates a User, whose
      # onboarding drives audit writes through other paths — stub first and
      # this example could pass for an incidental reason instead of proving
      # the credential's own rollback.
      user = create(:user)
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect { create(:webauthn_credential, user: user) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(WebauthnCredential.count).to eq(0)
    end
  end
end
