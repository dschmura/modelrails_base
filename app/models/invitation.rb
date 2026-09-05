class Invitation < ApplicationRecord
  class NotAcceptable < StandardError; end
  # Subclasses NotAcceptable so boundary rescues keep working; callers that care can still tell a wrong address apart.
  class EmailMismatch < NotAcceptable; end

  belongs_to :invitable, polymorphic: true
  belongs_to :role, optional: true
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  include Trackable
  include Broadcastable
  include Invitation::Suppression
  include Invitation::Sending

  enum :status, { pending: "pending", accepted: "accepted", declined: "declined", revoked: "revoked" }, default: "pending"

  validates :role, presence: true, unless: :client_invite?
  validate :client_invite_targets_a_project
  validates :invited_by, presence: true
  validates :expires_at, presence: true
  validates :project_role, inclusion: { in: %w[editor viewer] }, allow_nil: true
  # `|| e`: a blank string must fail the format check, never become nil — nil means a bearer magic-link invitation.
  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) || e }
  # Encrypted at rest (#902); deterministic because the pending-live unique index and bulk_invite! look up by email.
  encrypts :email, deterministic: true, downcase: true
  encrypts :company_name
  # Rebuilt into URLs later (reminder, notification mailer), so it can't be a
  # digest; deterministic keeps find_by/the index working (#953). No downcase: base64.
  encrypts :token, deterministic: true
  validates :email, format: { with: User::EMAIL_FORMAT }, allow_nil: true

  before_create :generate_token

  # `_previously_changed?` is true only in the writing update's commit phase — one notification per transition.
  after_update_commit :notify_accepted, if: :just_accepted?
  after_update_commit :notify_declined, if: :just_declined?

  # Not named `pending` (#452): overriding the enum's scope desyncs it from the `pending?` predicate.
  scope :acceptable, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "pending").where("expires_at <= ?", Time.current) }

  # Mirror of Membership.for_members_index; the two split one status filter — keep them in sync.
  scope :for_members_index, ->(role:, status:) {
    return none if %w[active deactivated].include?(status)

    scope = acceptable.includes(:role)
    scope = scope.joins(:role).where(roles: { slug: role }) if role.present?
    scope
  }

  def client_invite? = company_name.present?

  # Both signup acceptance paths (PendingClaims#claim!, Authentication#claim_pending!) funnel here so their
  # semantics can't diverge: nil when the token matches nothing, NotAcceptable when it does but can't be accepted.
  def self.consume!(token:, user:, expected_email: nil)
    return if token.blank?

    invitation = find_by(token: token)
    return if invitation.nil?

    # Address-bound redemption: a leaked link can't be claimed from a different proven address;
    # nil-email magic links stay bearer by design. See /docs/developer/security.
    if invitation.email.present? && expected_email.present? &&
        !EmailNormalizer.equivalent?(invitation.email, expected_email)
      raise EmailMismatch
    end

    invitation.accept!(user)
    invitation
  end

  def accept!(user)
    transaction do
      lock!
      guard_acceptable!
      if client_invite?
        accept_client_invitation!(user)
      elsif invitable_type == "Project"
        accept_project_invitation!(user)
      else
        accept_workspace_invitation!(user)
      end

      update!(
        status: "accepted",
        accepted_by: user,
        accepted_at: Time.current
      )
    end
  end

  # lock! reloads inside BEGIN IMMEDIATE, so a stale pending? can't overwrite a committed acceptance (#675).
  # See /docs/developer/architecture (Concurrency).
  def decline!
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid.new(self), "Invitation already processed" unless pending?
      update!(status: "declined", declined_at: Time.current)
    end
  end

  def revoke!
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid.new(self), "Invitation already processed" unless pending?
      update!(status: "revoked", revoked_at: Time.current)
    end
  end

  def resend!
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid.new(self), "Invitation already processed" unless pending?
      update!(
        token: SecureRandom.urlsafe_base64(32),
        expires_at: 7.days.from_now
      )
    end
  end

  def acceptable? = pending? && !expired?

  def expired? = expires_at <= Time.current

  def magic_link? = email.nil?

  # Nothing to deliver to on a magic link — a false here is NOT a block, so a
  # future magic-link mailer must not read it as one (PR 4 spec §2).
  def has_invitee? = !magic_link?

  # Ceil, not round: T-30min must read "1 hour". Single source for the notifier and its mailer.
  def expires_in_hours
    return 0 if expires_at <= Time.current
    ((expires_at - Time.current) / 1.hour).ceil
  end

  def resolved_workspace
    case invitable
    when Workspace then invitable
    when Project   then invitable.workspace
    end
  end

  private

  # One choke point, one generic message on all three refusals — an invitee must not learn a workspace is locked.
  def guard_acceptable!
    raise NotAcceptable, "Invitation no longer acceptable" unless pending?
    raise NotAcceptable, "Invitation no longer acceptable" if expired?
    raise NotAcceptable, "Invitation no longer acceptable" unless resolved_workspace&.admittable?
  end

  def broadcast_target
    resolved_workspace
  end

  def accept_client_invitation!(user)
    raise NotAcceptable, "Invitation no longer acceptable" unless invitable.kept?
    raise NotAcceptable, "Clientside is disabled for this project" unless invitable.clientside_enabled?

    access = invitable.client_accesses.find_by(user: user)
    if access&.discarded?
      access.undiscard!
    elsif access.nil?
      invitable.client_accesses.create!(user: user, company_name: company_name)
    end
    user.update!(onboarded_at: Time.current) unless user.onboarded?
  end

  def client_invite_targets_a_project
    return unless client_invite?
    errors.add(:base, :client_requires_project) if invitable_type != "Project"
  end

  def accept_workspace_invitation!(user)
    invitable.admit(user, role: role, granted_by: invited_by)
  end

  def accept_project_invitation!(user)
    # Checked first so a dead project never grants a workspace membership as a side effect.
    raise NotAcceptable, "Invitation no longer acceptable" unless invitable.kept?

    # :adopt — a project invite must tolerate an existing workspace member (see the "already a project member" spec).
    invitable.workspace.admit(user, role: role, granted_by: invited_by, on_existing: :adopt)

    raise ActiveRecord::RecordInvalid.new(self), "User is already a project member" if invitable.project_memberships.exists?(user: user)
    invitable.project_memberships.create!(user: user, role: project_role || "editor")
  end

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  # Never the ambient Current.workspace — acceptance can happen from another workspace's page.
  def activity_workspace
    resolved_workspace
  end

  def just_accepted?
    accepted_at_previously_changed? && accepted_at.present?
  end

  def just_declined?
    declined_at_previously_changed? && declined_at.present?
  end

  def notify_accepted
    return if invited_by.blank?
    return if invited_by == accepted_by
    WorkspaceInvitationAcceptedNotifier.with(record: self).deliver(invited_by)
  end

  # Decline has no accepted_by; compare addresses with EmailNormalizer.equivalent? to absorb case/NFC/punycode variation.
  def notify_declined
    return if invited_by.blank?
    return if EmailNormalizer.equivalent?(email, invited_by.email_address)
    WorkspaceInvitationDeclinedNotifier.with(record: self).deliver(invited_by)
  end
end
