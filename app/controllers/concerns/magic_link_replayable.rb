# A spent magic-link token plus a live session for the same address is a replay.
# "Spent" means redeemed OR superseded (#1083), so every answer must hold for both.
# Predicate only; each caller decides what a replay says.
module MagicLinkReplayable
  extend ActiveSupport::Concern

  private

  # Takes the token as an argument: the two controllers name the param differently.
  def replayed_by_owner(token)
    return nil unless authenticated?

    spent = MagicLinkToken.find_spent(token)
    return nil if spent.nil?

    spent if spent.email == Current.user.email_address
  end
end
