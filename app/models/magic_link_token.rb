class MagicLinkToken < ApplicationRecord
  validates :token, presence: true, uniqueness: true
  validates :email, presence: true, format: { with: User::EMAIL_FORMAT }
  validates :expires_at, presence: true

  def self.create_for_email(email)
    token = SecureRandom.urlsafe_base64(32)
    create!(token: token, email: email.downcase, expires_at: 15.minutes.from_now)
    token
  end

  def self.find_valid(token)
    find_by(token: token)
      &.then { |record| record.expires_at > Time.current && record.consumed_at.nil? ? record : nil }
  end

  def consume!
    update!(consumed_at: Time.current)
  end
end
