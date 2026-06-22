# frozen_string_literal: true

module Passkeys
  module RegisterCeremony
    module_function

    # Returns WebAuthn creation options and stores the challenge for later
    # verification. Excludes credentials the user has already registered so
    # the authenticator won't offer to re-register a known passkey.
    def options(user:)
      opts = WebAuthn::Credential.options_for_create(
        user: { id: user.webauthn_handle!, name: user.email_address },
        exclude: user.webauthn_credentials.kept.pluck(:external_id),
        authenticator_selection: { resident_key: "required", user_verification: "preferred" }
      )
      WebauthnChallenge.store(challenge: opts.challenge, purpose: "registration", user: user)
      opts
    end

    # Verifies the attestation response and persists the new WebauthnCredential.
    #
    # Raises:
    #   Passkeys::ChallengeExpired           – challenge missing, expired, or replayed
    #   Passkeys::VerificationFailed         – gem rejected the attestation
    #   Passkeys::CredentialAlreadyRegistered – duplicate external_id
    def verify(user:, credential_params:, nickname:)
      webauthn_credential = WebAuthn::Credential.from_create(credential_params)

      # client_data.challenge returns the raw binary (ASCII-8BIT) decoded from
      # clientDataJSON — confirmed against webauthn 3.4.3 source. Re-encode to
      # the base64url string that WebauthnChallenge.store persisted.
      raw_challenge = webauthn_credential.response.client_data.challenge
      stored_challenge = WebAuthn.standard_encoder.encode(raw_challenge)
      challenge = WebauthnChallenge.consume!(stored_challenge, purpose: "registration")
      raise ChallengeExpired unless challenge

      # challenge.challenge is the stored base64url string; the gem's verify
      # method decodes it internally via WebAuthn.standard_encoder.
      webauthn_credential.verify(challenge.challenge)

      user.webauthn_credentials.create!(
        external_id: webauthn_credential.id,
        public_key:  webauthn_credential.public_key,
        sign_count:  webauthn_credential.sign_count,
        nickname:    nickname.presence || "Passkey",
        verified_at: Time.current
      )
    rescue WebAuthn::Error => e
      raise VerificationFailed, e.message
    rescue ActiveRecord::RecordNotUnique
      raise CredentialAlreadyRegistered
    end
  end
end
