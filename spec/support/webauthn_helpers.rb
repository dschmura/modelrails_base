# frozen_string_literal: true

# Load the webauthn gem's test-support double (real crypto, no network).
# Used by passkeys ceremony specs; imported automatically via rails_helper's
# Dir[spec/support/**/*.rb] glob.
require "webauthn/fake_client"
