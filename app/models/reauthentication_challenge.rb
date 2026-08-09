# A short-lived, single-use, user-bound email code for re-authentication.
#
# Deliberately not MagicLinkToken: no code path here starts a session, so an
# emailed code can never be replayed into a sign-in, and the per-user active
# index means it can't collide with an in-flight sign-in link. Only the digest
# is stored; the plaintext code lives only in the email.
class ReauthenticationChallenge < ApplicationRecord
  belongs_to :user

  EXPIRY = 10.minutes
  CODE_LENGTH = 6

  # Issue a fresh code, superseding any prior unconsumed one for the user.
  # Returns the plaintext code to email.
  def self.issue_for(user)
    code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0")
    transaction do
      where(user_id: user.id, consumed_at: nil).update_all(consumed_at: Time.current)
      create!(user: user, code_digest: digest(code), expires_at: EXPIRY.from_now)
    end
    code
  end

  # Atomic, single-use, user-bound. The guard lives in the WHERE (mirroring
  # MagicLinkToken.consume!) so concurrent verifies serialize to one winner and
  # a wrong guess never consumes the challenge.
  def self.consume(user:, code:)
    return false if code.blank?

    rows = where(user_id: user.id, code_digest: digest(code.to_s.strip), consumed_at: nil)
             .where("expires_at > ?", Time.current)
             .update_all(consumed_at: Time.current)
    rows.positive?
  end

  # SHA256 peppered with secret_key_base: a leaked table can't be brute-forced
  # offline without the app secret, and the 6-digit online space is covered by
  # the reauthentication endpoint's rate limit.
  def self.digest(code)
    Digest::SHA256.hexdigest("#{code}#{Rails.application.secret_key_base}")
  end
end
