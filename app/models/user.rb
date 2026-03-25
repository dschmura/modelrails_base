class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, if: -> { password_digest_changed? || new_record? }
  validate :password_not_pwned, if: -> { password_digest_changed? || new_record? }

  def full_name
    "#{first_name} #{last_name}"
  end

  def generate_reset_password_token!
    update!(
      reset_password_token: SecureRandom.urlsafe_base64(32),
      reset_password_sent_at: Time.current
    )
  end

  def clear_reset_password_token!
    update!(
      reset_password_token: nil,
      reset_password_sent_at: nil
    )
  end

  def reset_password_token_expired?
    return true if reset_password_sent_at.nil?
    reset_password_sent_at < 2.hours.ago
  end

  private

  def password_not_pwned
    return if password.blank?
    if Pwned::Password.new(password).pwned?
      errors.add(:password, :pwned)
    end
  rescue Pwned::Error
    # Network error — allow password (don't block registration on external service failure)
  end
end
