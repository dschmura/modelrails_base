# A registered passkey. Unlike Authentication (one row per OAuth/email provider),
# this is a *capability*: register once, authenticate many. A user may have many.
# verified_at is set once at registration and never cleared; to revoke, discard.
class WebauthnCredential < ApplicationRecord
  include Discardable

  belongs_to :user
  validates :external_id, presence: true, uniqueness: true
  validates :public_key, :sign_count, presence: true

  # Strict tier (notifications lifecycle arc): enrollment/removal are
  # credential mutations — the audit row commits with them or not at all.
  # Removal hooks the Discardable update the same way rather than
  # after_discard, so the row and the discard share one transaction.
  after_create :audit_added
  after_update :audit_removed, if: :newly_discarded?

  # Atomic advance with clone detection: a single UPDATE guarded by the current
  # count, so concurrent assertions can't both "advance" past the same value.
  # Per WebAuthn §7.2 the signature counter is only meaningful when nonzero —
  # platform passkeys (Apple/Google) always report 0, which means "no counter
  # support", not a clone. So accept when new_count is 0 OR strictly greater than
  # the stored count; flag a clone only on a nonzero, non-advancing count. MAX()
  # keeps the stored value monotonic so a stray 0 never lowers a real counter.
  def advance_sign_count!(new_count)
    rows = self.class.where(id: id)
             .where("? = 0 OR sign_count < ?", new_count, new_count)
             .update_all([ "sign_count = MAX(sign_count, ?), last_used_at = ?", new_count, Time.current ])
    raise Passkeys::ClonedAuthenticator, "sign_count regressed (#{new_count} <= #{sign_count})" if rows.zero?
    reload
  end

  private

  # The kept -> discarded EDGE, not merely "discarded_at changed and is set".
  # Discardable#discard! is an unconditional update!, so a repeat call restamps
  # discarded_at and would write a second removal row — and this row is the only
  # record that a passkey was removed, so a duplicate misreports one removal as
  # two. undiscard! followed by discard! is a genuine second removal and still
  # writes, because discarded_at was nil before that save.
  def newly_discarded?
    saved_change_to_discarded_at? && discarded_at.present? && discarded_at_before_last_save.nil?
  end

  def audit_added = audit!("user.passkey_added")
  def audit_removed = audit!("user.passkey_removed")

  def audit!(action)
    ActivityLog.record_security_event!(action: action, user: user, metadata: { nickname: nickname })
  end
end
