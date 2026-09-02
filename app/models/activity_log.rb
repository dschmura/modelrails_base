class ActivityLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :trackable, polymorphic: true
  belongs_to :workspace, optional: true

  # The audit trail is best-effort to write (Trackable rescues rather than
  # failing the business operation — see /docs/developer/architecture) and immutable
  # after: persisted rows refuse instance-level update/destroy. Relation-level
  # bypasses (update_all/delete_all) are fenced by
  # spec/code_smells/activity_log_immutability_spec.rb, where the retention
  # sweep job (#438) has its explicit carve-out.
  def readonly? = persisted?

  # The locale key the feed renders this row with — usually just `action`.
  # A membership deactivation and a reactivation both arrive as
  # `membership.updated` (Discardable#discard! is an ordinary update), so the
  # one action carried three different sentences and the feed said "had their
  # role changed" for a removal (#932). The row's own `changes` metadata is the
  # only thing that tells them apart. A status change outranks a role change:
  # `reactivate!` can carry both, and losing or regaining access is the more
  # consequential half. Unknown shapes fall through to `action`, which the
  # partial's `default:` humanizes — true, if plain.
  def display_action
    return action unless action == "membership.updated"

    transition = metadata.to_h.with_indifferent_access.dig(:changes, :discarded_at)
    return action if transition.blank?

    transition.last.present? ? "membership.deactivated" : "membership.reactivated"
  end

  enum :visibility, { workspace: "workspace", admin: "admin", personal: "personal" }, default: "workspace"

  # The security tier: the ONLY membership test for the audit retention floor.
  # ActivityLogRetentionSweepJob's exemption and record_security_event! below
  # reference this same constant — never re-derive the set from visibility,
  # which also carries non-security personal/admin rows.
  # Spec: activity_log_retention_sweep_job_spec.
  SECURITY_ACTIONS = %w[
    user.password_changed
    user.password_removed
    user.signed_in_new_device
    user.passkey_added
    user.passkey_removed
  ].freeze

  # The one writer for security-tier rows (User password callbacks,
  # WebauthnCredential, Authenticatable all route here). Two reasons it exists:
  # the row shape lives in exactly one place, and an action outside
  # SECURITY_ACTIONS raises instead of writing. Without the guard a drifted
  # literal ("user.passkey_add") would still write a plausible-looking row that
  # the sweep deletes at 12 months instead of the security floor — audit
  # evidence lost silently, with the whole suite green.
  #
  # ArgumentError is deliberate: a non-member action is a programmer error, so
  # it propagates through Authenticatable's ActiveRecord-only rescue rather
  # than being swallowed. This method does not choose the write guarantee —
  # callers do, by rescuing or not.
  def self.record_security_event!(action:, user:, metadata: {})
    unless SECURITY_ACTIONS.include?(action)
      raise ArgumentError, "#{action.inspect} is not in ActivityLog::SECURITY_ACTIONS"
    end

    create!(action: action, actor: user, trackable: user,
            visibility: "personal", workspace_id: nil, metadata: metadata)
  end

  validates :action, presence: true

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :visible, -> { where(visibility: "workspace") }
  # The read side of the security tier. MEMBERSHIP is the test (#827): before
  # this, the card filtered on `personal` visibility alone, which describes who
  # a row is scoped to, not whether it is a security event.
  # `Trackable#activity_visibility` is an overridable seam — Membership already
  # returns "admin" through it — so a fork returning "personal" for a domain
  # event had its rows rendered under a security heading.
  # `visibility` is kept as a second, narrowing predicate rather than dropped:
  # record_security_event! always writes personal, so a security action at any
  # other visibility is malformed, and an existing spec deliberately pins that
  # such a row stays out of this card.
  scope :security_events_for, ->(user) {
    where(action: SECURITY_ACTIONS, trackable: user, visibility: :personal)
      .order(created_at: :desc)
  }
  scope :recent, -> { order(created_at: :desc).limit(20) }
  # Project feed (#680): the LEADING for_workspace predicate rides
  # index_activity_logs_on_workspace_id_and_created_at, so the trackable OR
  # filters within one workspace's rows instead of scanning the global
  # activity table (which retention deliberately grows to 12 months).
  scope :for_project, ->(project) {
    visible.for_workspace(project.workspace_id).merge(
      where(trackable: project)
        .or(where(trackable: project.resources))
        .or(where(trackable: project.project_memberships))
        .or(where(trackable: project.invitations))
    )
  }
end
