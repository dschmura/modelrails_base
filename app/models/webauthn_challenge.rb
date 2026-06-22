class WebauthnChallenge < ApplicationRecord
  belongs_to :user, optional: true
  validates :challenge, presence: true, uniqueness: true
  validates :purpose, inclusion: { in: %w[registration authentication] }

  def self.store(challenge:, purpose:, user: nil)
    create!(challenge: challenge, purpose: purpose, user: user, expires_at: 5.minutes.from_now)
  end

  # Atomic compare-and-swap (the MagicLinkToken pattern): one UPDATE guarded by
  # consumed_at IS NULL + expiry + purpose, so concurrent consumers are
  # serialized by the database and only one sees affected_rows == 1.
  def self.consume!(challenge, purpose:)
    rows = where(challenge: challenge, purpose: purpose, consumed_at: nil)
             .where("expires_at > ?", Time.current)
             .update_all(consumed_at: Time.current)
    return nil unless rows > 0
    find_by(challenge: challenge)
  end
end
