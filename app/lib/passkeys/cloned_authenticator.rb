# frozen_string_literal: true

module Passkeys
  # Raised when advance_sign_count! detects the authenticator counter did not
  # advance — indicating a possible cloned authenticator. Do not auto-discard;
  # surface to the caller for policy-level handling.
  class ClonedAuthenticator < Error; end
end
