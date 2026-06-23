# frozen_string_literal: true

# Dismisses the one-time passkey enrollment banner by stamping
# passkey_prompt_seen_at, so it never reappears. The banner's dismiss (×) hits
# this endpoint; registering a passkey (via Settings) makes the user ineligible too.
class PasskeyPromptsController < ApplicationController
  def update
    Current.user.update!(passkey_prompt_seen_at: Time.current)
    redirect_back(fallback_location: root_path)
  end
end
