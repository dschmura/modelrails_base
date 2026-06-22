# A registered passkey. Unlike Authentication (one row per OAuth/email provider),
# this is a *capability*: register once, authenticate many. A user may have many.
# verified_at is set once at registration and never cleared; to revoke, discard.
class WebauthnCredential < ApplicationRecord
  include Discardable

  belongs_to :user
  validates :external_id, presence: true, uniqueness: true
  validates :public_key, :sign_count, presence: true

  # Atomic advance with clone detection: a single UPDATE guarded by the current
  # count, so concurrent assertions can't both "advance" past the same value. A
  # non-advance means the authenticator's counter regressed (possible clone) —
  # reject; do not auto-delete.
  def advance_sign_count!(new_count)
    rows = self.class.where(id: id).where("sign_count < ?", new_count)
             .update_all(sign_count: new_count, last_used_at: Time.current)
    raise Passkeys::ClonedAuthenticator, "sign_count did not advance (#{new_count} <= #{sign_count})" if rows.zero?
    reload
  end
end
