# frozen_string_literal: true

module Passkeys
  # Raised during assertion when the credential id is unknown or has been
  # discarded (Discard-soft-deleted).
  class CredentialNotFound < Error; end
end
