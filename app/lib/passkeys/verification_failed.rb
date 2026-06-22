# frozen_string_literal: true

module Passkeys
  # Raised when the webauthn gem rejects the attestation or assertion
  # (signature mismatch, origin mismatch, etc.).
  class VerificationFailed < Error; end
end
