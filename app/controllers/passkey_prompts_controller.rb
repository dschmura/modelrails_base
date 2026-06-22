# frozen_string_literal: true

# Dismisses the one-time passkey enrollment interstitial by stamping
# passkey_prompt_seen_at. Both "Add a passkey" (after registration) and
# "Not now" paths hit this endpoint so the dialog never reappears.
class PasskeyPromptsController < ApplicationController
  def update
    Current.user.update!(passkey_prompt_seen_at: Time.current)
    redirect_back(fallback_location: root_path)
  end
end
