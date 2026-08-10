class WorkspaceJoinLink < ApplicationRecord
  # Bearer token stored only as a SHA256 digest (mirrors MagicLinkToken). The
  # plaintext lives in the shared URL and is surfaced once, on create/rotate,
  # via #plaintext_token — never re-read from the database. Revocability is why
  # this is a stored record (vs. a signed-stateless token): `revoked_at` makes
  # individual links killable and the partial unique index keeps one active per
  # workspace. Rotation is revoke-then-create in JoinLinksController.
  attr_reader :plaintext_token

  validates :token_digest, presence: true, uniqueness: true

  belongs_to :workspace
  belongs_to :created_by, class_name: "User"

  scope :active, -> { where(revoked_at: nil) }

  before_validation :generate_token, on: :create

  # One formula, so lookup and insert can never disagree (see MagicLinkToken).
  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_active(token)
    active.find_by(token_digest: digest(token))
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  # Non-secret display stub for settings once the plaintext is gone. Uses the
  # digest tail (public) so admins can tell one link from another; never the
  # plaintext, which no longer exists at rest.
  def masked_token
    "…#{token_digest.to_s.last(6)}"
  end

  private

  def generate_token
    return if token_digest.present?

    @plaintext_token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@plaintext_token)
  end
end
