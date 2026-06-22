# frozen_string_literal: true

module Passkeys
  module AuthenticateCeremony
    module_function

    # Returns WebAuthn get-options and stores the challenge for later verification.
    # Empty allow list → discoverable / usernameless assertion.
    def options
      opts = WebAuthn::Credential.options_for_get(user_verification: "preferred")
      WebauthnChallenge.store(challenge: opts.challenge, purpose: "authentication")
      opts
    end

    # Verifies the assertion response, advances sign_count (clone detection),
    # and returns the authenticated User.
    #
    # Raises:
    #   Passkeys::CredentialNotFound  – external_id not in the registry
    #   Passkeys::ChallengeExpired    – challenge missing, expired, or replayed
    #   Passkeys::ClonedAuthenticator – sign_count did not advance (possible clone)
    #   Passkeys::VerificationFailed  – gem rejected the assertion
    def verify(credential_params:)
      webauthn_credential = WebAuthn::Credential.from_get(credential_params)
      stored = WebauthnCredential.kept.find_by(external_id: webauthn_credential.id)
      raise CredentialNotFound unless stored

      ApplicationRecord.transaction do
        # client_data.challenge returns raw ASCII-8BIT bytes — re-encode to
        # the base64url string that WebauthnChallenge.store persisted.
        raw_challenge = webauthn_credential.response.client_data.challenge
        stored_challenge = WebAuthn.standard_encoder.encode(raw_challenge)
        challenge = WebauthnChallenge.consume!(stored_challenge, purpose: "authentication")
        raise ChallengeExpired unless challenge

        webauthn_credential.verify(challenge.challenge, public_key: stored.public_key, sign_count: stored.sign_count)
        stored.advance_sign_count!(webauthn_credential.sign_count.to_i) # raises ClonedAuthenticator on regression
        stored.user
      end
    rescue WebAuthn::Error => e
      raise VerificationFailed, e.message
    end
  end
end
