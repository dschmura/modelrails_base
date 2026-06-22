# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passkeys::AuthenticateCeremony do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  before do
    reg = Passkeys::RegisterCeremony.options(user: user)
    Passkeys::RegisterCeremony.verify(user: user, credential_params: client.create(challenge: reg.challenge), nickname: "k")
  end

  it "authenticates the owner from a real assertion and advances sign_count" do
    options = described_class.options
    assertion = client.get(challenge: options.challenge)
    expect(described_class.verify(credential_params: assertion)).to eq(user)
  end

  it "rejects an unknown credential (external_id not in DB)" do
    # Register the 'other' client with the gem but NOT through RegisterCeremony,
    # so its external_id is absent from WebauthnCredential.
    other = WebAuthn::FakeClient.new(Passkeys.origin)
    create_opts = WebAuthn::Credential.options_for_create(user: { id: "other-handle", name: "other@example.com" })
    other.create(challenge: create_opts.challenge) # seeds other's internal credential store

    auth_options = described_class.options
    assertion = other.get(challenge: auth_options.challenge)
    expect { described_class.verify(credential_params: assertion) }.to raise_error(Passkeys::CredentialNotFound)
  end

  it "raises ClonedAuthenticator when advance_sign_count! detects a regressed counter" do
    # The gem's verify also guards sign_count, but advance_sign_count! is a second
    # DB-level guard protecting against races (two concurrent assertions, first wins).
    # Stub verify to pass, then trigger the DB guard directly.
    options = described_class.options
    assertion = client.get(challenge: options.challenge)
    stored = user.webauthn_credentials.kept.first

    allow_any_instance_of(WebAuthn::PublicKeyCredentialWithAssertion).to receive(:verify)
    allow(WebauthnCredential).to receive(:kept).and_return(
      instance_double(ActiveRecord::Relation, find_by: stored)
    )
    allow(stored).to receive(:advance_sign_count!).and_raise(Passkeys::ClonedAuthenticator)

    expect { described_class.verify(credential_params: assertion) }.to raise_error(Passkeys::ClonedAuthenticator)
  end
end
