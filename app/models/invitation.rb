class Invitation < ApplicationRecord
  class NotAcceptable < StandardError; end
  # Raised when an invitation addressed to a specific email is consumed by a
  # caller whose proven email differs. Subclasses NotAcceptable so existing
  # boundary rescues keep working, while callers that care can distinguish a
  # wrong-address attempt from a stale/used invitation for messaging.
  class EmailMismatch < NotAcceptable; end

  belongs_to :invitable, polymorphic: true
  belongs_to :role, optional: true
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  include Trackable
  include Broadcastable
  include Invitation::Suppression

  enum :status, { pending: "pending", accepted: "accepted", declined: "declined", revoked: "revoked" }, default: "pending"

  validates :role, presence: true, unless: :client_invite?
  validate :client_invite_targets_a_project
  validates :invited_by, presence: true
  validates :expires_at, presence: true
  validates :project_role, inclusion: { in: %w[editor viewer] }, allow_nil: true
  # A blank string stays blank (and fails the format check) rather than
  # becoming nil: nil means a bearer magic-link invitation, and normalization
  # must never turn a user's empty field into one.
  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) || e }
  # Encrypted at rest (#902): email deterministic for the pending-invite
  # unique index that bulk_invite! leans on; company_name takes the stronger
  # cipher.
  encrypts :email, deterministic: true, downcase: true
  encrypts :company_name
  # Rebuilt into URLs later (reminder, notification mailer), so it can't be a
  # digest; deterministic keeps find_by/the index working (#953). No downcase: base64.
  encrypts :token, deterministic: true
  validates :email, format: { with: User::EMAIL_FORMAT }, allow_nil: true

  before_create :generate_token

  # Notifier triggers: fire on the accepted/declined transitions only.
  # `<attr>_previously_changed?` is true exclusively in the after_update_commit
  # phase of the update that wrote the new value, so we get one notification
  # per state transition (never on subsequent unrelated updates).
  after_update_commit :notify_accepted, if: :just_accepted?
  after_update_commit :notify_declined, if: :just_declined?

  # Named for the `acceptable?` predicate it mirrors, NOT `pending`. The enum
  # generates both a `pending` scope and a `pending?` predicate; overriding only
  # the scope to also require an unexpired `expires_at` made the pair disagree —
  # an expired invitation was `pending?` yet absent from `Invitation.pending`,
  # a trap for anyone reasoning "in the scope iff the predicate" (#452). The
  # enum's `pending` is left alone; the extra constraint lives under its own name.
  scope :acceptable, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "pending").where("expires_at <= ?", Time.current) }

  # The SQL half of the members page (WorkspaceRoster does search and sort in
  # Ruby). Pending invitations are excluded entirely when the status filter
  # selects a membership-only state (active or deactivated).
  scope :for_members_index, ->(role:, status:) {
    return none if %w[active deactivated].include?(status)

    scope = acceptable.includes(:role)
    scope = scope.joins(:role).where(roles: { slug: role }) if role.present?
    scope
  }

  def client_invite? = company_name.present?

  # The single-create paths' duplicate rule. A live pending row from ANY inviter
  # refuses a second invite — exactly `index_invitations_pending_live`'s
  # predicate; so does THIS inviter's own row, live or ghost. The ghost half is
  # invariant I3: a stamped row vacates the live slot, so without it a blocked
  # re-invite quietly succeeds where an unblocked one is refused, and that
  # difference is readable as a block. A *different* inviter's ghost still
  # doesn't refuse (T16).
  #
  # `pending`, NOT `acceptable`: that index is expiry-blind, so a still-pending
  # expired row goes on holding the live slot. Narrowing this to `acceptable`
  # reopens the same oracle about seven days after any blocked invite, and
  # nothing re-statuses an expired pending row, so it never heals.
  def self.already_invited?(invitable:, email:, invited_by:)
    existing = invitable.invitations.pending.where(email: normalize_value_for(:email, email))
    existing.unsuppressed.exists? || existing.where(invited_by: invited_by).exists?
  end

  def self.invite_client!(project:, email:, company_name:, invited_by:)
    # The same signal the `pending_live` index raises, so the pre-check and a
    # lost race land on the controller's one rescue and one flash.
    raise ActiveRecord::RecordNotUnique, "pending invitation already exists" if
      already_invited?(invitable: project, email: email, invited_by: invited_by)

    invitation = create!(
      invitable: project,
      email: email,
      company_name: company_name,
      invited_by: invited_by,
      expires_at: 7.days.from_now
    )
    InvitationMailer.with(invitation: invitation).invite_client.deliver_later
    invitation
  end

  # One invite submission fans out to N emails at addresses the sender chose,
  # so the list is bounded per submission (D13). The controller's rate_limit
  # bounds how often someone may submit; this bounds how much one submission
  # can do. Both layers, because either alone leaves the other's gap open.
  MAX_EMAILS_PER_SUBMISSION = 20

  # Returned rather than a bare Array so the cap cannot be applied silently:
  # a caller that ignores over_limit? truncates the sender's list without
  # telling them, which in onboarding means teammates that were typed in
  # simply never get invited and nobody finds out.
  ParsedEmailList = Data.define(:emails, :over_limit) do
    def over_limit? = over_limit
    def empty? = emails.empty?
  end

  # Parse a raw invite-form string ("a@x.com, b@y.com\nc@z.com") into a clean,
  # capped address list. bulk_invite! applies it to whatever it's given, so the
  # invite forms hand the textarea value over verbatim instead of each
  # duplicating the split/strip.
  def self.parse_email_list(emails)
    all = Array(emails).flat_map { |chunk| chunk.to_s.split(/[\n,]/) }.map(&:strip).reject(&:blank?)

    ParsedEmailList.new(
      emails: all.first(MAX_EMAILS_PER_SUBMISSION),
      over_limit: all.size > MAX_EMAILS_PER_SUBMISSION
    )
  end

  # `sent` means records created — delivery is asynchronous and may be
  # suppressed; this method has never known whether mail arrived, on the
  # blocked path or any other (PR 4 spec §6.4).
  def self.bulk_invite!(workspace:, emails:, role:, invited_by:)
    parsed = parse_email_list(emails)
    emails = parsed.emails
    sent = 0
    skipped = 0

    existing_members = workspace.memberships.kept.joins(:user).pluck(:email_address).to_set
    # unsuppressed: a ghost must not make an unblocked admin skip the address.
    existing_invites = workspace.invitations.acceptable.unsuppressed.where.not(email: nil).pluck(:email).to_set
    # Bounded to this submission (≤ MAX_EMAILS_PER_SUBMISSION); `normalizes`
    # applies to the finder values, so raw input matches stored rows.
    blocked = InvitationBlock.where(inviter: invited_by, email: emails).pluck(:email).to_set

    emails.each do |email|
      normalized = normalize_value_for(:email, email)

      unless normalized.to_s.match?(User::EMAIL_FORMAT)
        skipped += 1
        next
      end

      if existing_members.include?(normalized) || existing_invites.include?(normalized)
        skipped += 1
        next
      end

      begin
        invitation = workspace.invitations.create!(
          email: normalized,
          role: role,
          invited_by: invited_by,
          expires_at: 7.days.from_now,
          suppressed_at: (Time.current if blocked.include?(normalized))
        )
      rescue ActiveRecord::RecordNotUnique
        # Two ways here — a collision into this inviter's existing ghost, and a
        # concurrent request that won the live slot — and both count `skipped`,
        # because neither created a record and "sent" means created (see above).
        # For the ghost that is also the deliberate call on invariant I3: now
        # that `existing_invites` excludes ghosts via `.unsuppressed` (T16),
        # counting it `sent` would make "pending in the members index, yet
        # sent:1" an oracle that fires only for a blocked address. Controller-
        # ruled override of PR 4 spec §6.4's "collision counts sent" text
        # (task-6 fix round 1).
        skipped += 1
        next
      end
      existing_invites.add(normalized)
      InvitationMailer.with(invitation: invitation).invite.deliver_later
      sent += 1
    end

    { sent: sent, skipped: skipped, over_limit: parsed.over_limit? }
  end

  # Shared consumption core for both signup acceptance paths: the session-based
  # one (PendingClaims#claim!, signup-time) and the column-based one
  # (Authentication#claim_pending!, verification-time). Centralizing it keeps both flows
  # on identical acceptance semantics. Returns the invitation on success, or nil
  # when the token is blank or matches nothing. Propagates Invitation::NotAcceptable
  # when the invitation exists but is no longer acceptable, so callers can surface
  # the race; #accept! still owns the pessimistic lock and state transition.
  def self.consume!(token:, user:, expected_email: nil)
    return if token.blank?

    invitation = find_by(token: token)
    return if invitation.nil?

    # Email-match guard: when an invitation is addressed to a specific email,
    # only consume it for a caller whose proven email matches. This is what
    # closes bearer-token redemption — combined with deferring consumption to
    # email verification, a leaked link can't be claimed from a different
    # (even verified) address. Magic-link invitations (nil email) stay bearer
    # by design; direct callers that pass no expected_email skip the check.
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

  # decline!/revoke!/resend! share accept!'s transaction + lock! shape (#675):
  # lock! reloads the row inside BEGIN IMMEDIATE (the FOR UPDATE clause is a
  # SQLite no-op, but the immediate transaction serializes writers and the
  # reload is the real re-check), so a stale in-memory pending? can never
  # overwrite a committed acceptance — and resend! can no longer rotate the
  # token on an accepted/revoked row, which would destroy audit correlation.
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

  def decline_and_block!
    # ArgumentError, deliberately never rescued: the controller pre-checks
    # has_invitee?; reaching this raise is a programmer error (PR 4 spec §6.2).
    raise ArgumentError, "magic-link invitations have no invitee to block for" unless has_invitee?
    # Block commits first, so a lost decline race still records the block —
    # true when called outside a caller transaction (the controller's case).
    # Nested, `block!` joins that transaction and both roll back together.
    InvitationBlock.block!(inviter: invited_by, email: email)
    decline!
  end

  def acceptable? = pending? && !expired?

  def expired? = expires_at <= Time.current

  def magic_link? = email.nil?

  # Nothing to deliver to on a magic link — a false here is NOT a block, so a
  # future magic-link mailer must not read it as one (PR 4 spec §2).
  def has_invitee? = !magic_link?

  # Hours remaining until expiry, ceiled to the next whole hour. Single source
  # of truth for the user-facing "expires in N hours" copy in both the
  # WorkspaceInvitationExpiringSoonNotifier message and the matching mailer.
  # Ceil (not round/floor) so T-30min reads as "1 hour" not "0 hours" — the
  # message is hours-remaining, and rounding down to zero is misleading UX.
  def expires_in_hours
    return 0 if expires_at <= Time.current
    ((expires_at - Time.current) / 1.hour).ceil
  end

  # Resolves the workspace context for a polymorphic invitation. An invitation
  # may target a Workspace directly or a Project — in the latter case the
  # workspace context comes from the project. Single source of truth shared by
  # the notifiers (Accepted / Declined / ExpiringSoon) and NotificationMailer.
  def resolved_workspace
    case invitable
    when Workspace then invitable
    when Project   then invitable.workspace
    end
  end

  private

  # Single choke point: every acceptance path funnels through accept!, so the
  # workspace-admittability gate here closes them all at once — with the same
  # generic copy as invalid/expired, so an invitee never learns a workspace is locked.
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
    # Delegate to the single membership-grant entry point. Locking, capacity,
    # discarded-reactivation, and :shared-posture role reconciliation all live
    # in Workspace#admit so the open-link self-join flow (Reshape 2) shares
    # identical semantics.
    invitable.admit(user, role: role, granted_by: invited_by)
  end

  def accept_project_invitation!(user)
    # A discarded project is unacceptable — the same generic NotAcceptable the
    # workspace and client paths raise. Checked first so a dead project never
    # grants a workspace membership as a side effect.
    raise NotAcceptable, "Invitation no longer acceptable" unless invitable.kept?

    # Same single membership-grant entry point as the workspace path — lock,
    # locked admittability re-check, capacity, discarded-reactivation, and
    # granted_by provenance all live in Workspace#admit. :adopt because a
    # project invite must TOLERATE an existing workspace member (just add them
    # to the project) — see the "already a project member" spec.
    invitable.workspace.admit(user, role: role, granted_by: invited_by, on_existing: :adopt)

    raise ActiveRecord::RecordInvalid.new(self), "User is already a project member" if invitable.project_memberships.exists?(user: user)
    invitable.project_memberships.create!(user: user, role: project_role || "editor")
  end

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  # Attribute activity to the invitation's own workspace context, never the
  # ambient Current.workspace (an invitation can be created/accepted from a
  # different workspace's page).
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

  # Mirror of notify_accepted's self-recipient guard. Decline has no accepted_by
  # column (declines come from email/magic-link, not a signed-in user), so the
  # check is "did the inviter decline their own invitation?" — compared via
  # EmailNormalizer.equivalent? to absorb case / Unicode-NFC / IDN punycode
  # variation between the stored invitation email and the inviter's address.
  def notify_declined
    return if invited_by.blank?
    return if EmailNormalizer.equivalent?(email, invited_by.email_address)
    WorkspaceInvitationDeclinedNotifier.with(record: self).deliver(invited_by)
  end
end
