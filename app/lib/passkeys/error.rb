# frozen_string_literal: true

module Passkeys
  # Base class for all Passkeys errors. Rescue this to catch any ceremony failure.
  class Error < StandardError; end
end
