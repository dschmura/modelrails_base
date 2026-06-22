# frozen_string_literal: true

module Passkeys
  # Raised when the stored challenge is missing, expired, or has already been
  # consumed (replay attack).
  class ChallengeExpired < Error; end
end
