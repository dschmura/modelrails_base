# frozen_string_literal: true

module Passkeys
  # Raised when a credential with the same external_id is already persisted
  # (duplicate registration attempt).
  class CredentialAlreadyRegistered < Error; end
end
