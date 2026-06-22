# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passkeys::RegisterCeremony do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  it "registers a credential from a real attestation" do
    options = described_class.options(user: user)
    attestation = client.create(challenge: options.challenge)

    credential = described_class.verify(user: user, credential_params: attestation, nickname: "Laptop")

    expect(credential).to be_persisted
    expect(user.webauthn_credentials.kept.count).to eq(1)
    expect(credential.nickname).to eq("Laptop")
  end

  it "rejects a replayed challenge" do
    options = described_class.options(user: user)
    attestation = client.create(challenge: options.challenge)
    described_class.verify(user: user, credential_params: attestation, nickname: "x")

    expect {
      described_class.verify(user: user, credential_params: attestation, nickname: "y")
    }.to raise_error(Passkeys::ChallengeExpired)
  end
end
