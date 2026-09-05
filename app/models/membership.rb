class Membership < ApplicationRecord
  # Subclasses RecordInvalid so generic boundary rescues still catch it; controllers rescue the NAMED condition.
  class LastOwner < ActiveRecord::RecordInvalid; end

  include Discardable
  include Trackable
  include Broadcastable
  include Notifications

  belongs_to :user
  belongs_to :workspace

  # Non-persisted grant provenance for the creation audit entry (G): set by
  # Workspace#admit when an invitation acceptance created this membership.
  attr_accessor :granted_by

  # Non-persisted self-join marker. Grades, and why it is kept apart from granted_by:
  # /docs/developer/notifications (The actor rule).
  attr_accessor :self_join

  # Non-persisted removal actor (#933), an argument to #deactivate! — the model never reads Current.
  # See /docs/developer/notifications (The actor rule).
  attr_accessor :removed_by
  belongs_to :role

  SELF_JOIN_GRADES = [ nil, false, true, :onboarding ].freeze

  CONFLICTING_PROVENANCE_MESSAGE =
    "granted_by and self_join are mutually exclusive: a self-join has no granter"

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate :workspace_has_member_capacity, on: :create

  # Model invariant, not only the entry-point guard: direct creates (User#join_shared_workspace) never
  # see .reject_conflicting_provenance!. See /docs/developer/membership-lifecycle.
  validate :provenance_markers_are_coherent

  # The real capacity guard is post-INSERT; the pre-flight lock! is a no-op across SQLite connections.
  # See /docs/developer/architecture (Concurrency).
  after_create :enforce_capacity_invariant

  scope :filter_by_role, ->(role_slug) {
    return all if role_slug.blank?
    joins(:role).where(roles: { slug: role_slug })
  }

  scope :filter_by_status, ->(status) {
    case status
    when "active" then kept
    when "deactivated" then discarded
    else all
    end
  }

  # Mirror of Invitation.for_members_index; the two split one status filter — keep them in sync.
  scope :for_members_index, ->(role:, status:) {
    return none if status == "pending"

    includes(:user, :role)
      .filter_by_role(role)
      .filter_by_status(status)
  }

  # Mutually exclusive, and refused rather than documented. See /docs/developer/notifications (The actor rule).
  def self.reject_conflicting_provenance!(granted_by:, self_join:)
    return unless granted_by && self_join
    raise ArgumentError, CONFLICTING_PROVENANCE_MESSAGE
  end

  # Kept owner-role memberships in the workspace, excluding the given
  # membership id — "are there OTHER owners besides this one?".
  def self.other_kept_owners(workspace_id, excluding:)
    kept.joins(:role)
        .where(workspace_id: workspace_id, roles: { slug: "owner" })
        .where.not(id: excluding)
  end

  # Role identity only — deliberately silent on kept/discarded state; the
  # owner-floor queries carry their own kept filtering.
  def owner?
    role.present? && role.owner?
  end

  def change_role!(new_role)
    demoting_owner = owner? && !new_role.owner?
    transaction do
      workspace.lock!
      update!(role: new_role)
      enforce_owner_floor! if demoting_owner
    end
  end

  def deactivate!(removed_by: nil)
    # Idempotence guard: MembersController#destroy resolves through the UNSCOPED association, so replays
    # land here. See /docs/developer/membership-lifecycle.
    return if discarded?

    self.removed_by = removed_by
    transaction do
      workspace.lock!
      validate_not_last_owner!
      discard!
      enforce_owner_invariant!
      ProjectMembership.joins(:project)
        .where(projects: { workspace_id: workspace_id }, user_id: user_id)
        .destroy_all
    end
  end

  # Deliberately NOT gated on Workspace#admittable? — archived workspaces still reactivate; pinned in
  # membership_spec. See /docs/developer/membership-lifecycle.
  def reactivate!(granted_by: nil, self_join: false)
    self.class.reject_conflicting_provenance!(granted_by: granted_by, self_join: self_join)
    self.granted_by = granted_by
    self.self_join = self_join
    undiscard!
  end

  def transfer_ownership_to!(target_membership)
    owner_role = Role.system_default!("owner")
    admin_role = Role.system_default!("admin")

    transaction do
      workspace.lock!

      # CAS demote: zero rows means a racer demoted us first — abort before promoting. Skips callbacks
      # by design. See /docs/developer/architecture (Concurrency).
      rows = Membership.where(id: id)
                       .where(role_id: Role.where(slug: "owner").select(:id))
                       .update_all(role_id: admin_role.id)
      raise ActiveRecord::RecordInvalid, self if rows.zero?
      reload
      record_ownership_demotion(admin_role)

      target_membership.reload
      target_membership.update!(role: owner_role)
    end
  end

  private

  def broadcast_target
    workspace
  end

  def activity_workspace
    workspace
  end

  def provenance_markers_are_coherent
    errors.add(:base, CONFLICTING_PROVENANCE_MESSAGE) if granted_by && self_join
    return if SELF_JOIN_GRADES.include?(self_join)

    errors.add(:base,
      "self_join must be one of #{SELF_JOIN_GRADES.map(&:inspect).join(', ')}, " \
      "got #{self_join.inspect}")
  end

  def workspace_has_member_capacity
    return unless workspace
    workspace.lock!
    if workspace.at_capacity?
      errors.add(:base, :workspace_member_limit)
    end
  end

  def enforce_capacity_invariant
    return unless workspace_id
    count = Membership.where(workspace_id: workspace_id, discarded_at: nil).count
    limit = Workspace.where(id: workspace_id).pick(:max_members)
    return unless limit && count > limit
    errors.add(:base, :workspace_member_limit)
    raise ActiveRecord::RecordInvalid, self
  end

  def validate_not_last_owner!
    if owner? && !Membership.other_kept_owners(workspace_id, excluding: id).exists?
      errors.add(:base, :last_owner)
      raise LastOwner, self
    end
  end

  # Post-discard race net. See /docs/developer/architecture (Concurrency).
  def enforce_owner_invariant!
    return unless owner?
    # Self is already discarded here, so "any kept owner" == "any OTHER kept
    # owner" — the shared query reads identically either way.
    return if Membership.other_kept_owners(workspace_id, excluding: id).exists?
    errors.add(:base, :last_owner)
    raise LastOwner, self
  end

  # Post-UPDATE owner-floor net. See /docs/developer/architecture (Concurrency).
  def enforce_owner_floor!
    # Self is already demoted here, so counting all kept owners == counting
    # the OTHER kept owners — the shared query reads identically either way.
    return if Membership.other_kept_owners(workspace_id, excluding: id).exists?
    errors.add(:base, :last_owner)
    raise LastOwner, self
  end

  def track_creation
    metadata = { "role" => role&.slug }
    metadata["granted_by"] = granted_by.id if granted_by
    create_activity("membership.created", metadata.compact)
  end

  # Re-admission is an UPDATE that track_creation never sees, so the granter is merged here.
  # See /docs/developer/membership-lifecycle.
  def tracked_update_metadata(changes)
    return super unless just_reactivated? && granted_by

    super.merge("granted_by" => granted_by.id)
  end

  # One of Trackable's named out-of-concern best-effort writers: the CAS demote skips callbacks, so the
  # audit row is written explicitly.
  def record_ownership_demotion(to_role)
    ActivityLog.create!(
      actor: Current.user,
      action: "membership.updated",
      trackable: self,
      workspace: workspace,
      visibility: "admin",
      metadata: { "changes" => { "role" => [ "owner", to_role.slug ] } }
    )
  rescue StandardError => e
    Rails.logger.warn("Activity tracking failed for Membership##{id} (transfer demote): #{e.message}")
    Rails.error.report(e, handled: true, context: { trackable: "Membership##{id}", action: "transfer_demote" })
  end

  # SEC-1 audit: a role change is a privilege event. Record the role slugs by
  # value (not the mutable role_id FK) and route it to the admin-only feed.
  def enrich_tracked_changes(changes)
    return changes unless changes.key?("role_id")
    from_id, to_id = changes["role_id"]
    slugs = Role.where(id: [ from_id, to_id ].compact).pluck(:id, :slug).to_h
    changes.merge("role" => [ slugs[from_id], slugs[to_id] ])
  end

  def activity_visibility(action)
    (action == "membership.updated" && saved_change_to_role_id?) ? "admin" : "workspace"
  end

  # Inclusion, not `!= :onboarding`: an unvalidated new grade must not read as "chosen" and mail someone.
  def chosen_self_join?
    self_join == true
  end

  # Self-exclusion is the contract: the very first owner being seeded
  # (User#create_personal_workspace, bootstrap) must not count as a pre-existing owner.
  def workspace_has_other_owners?
    return false if workspace_id.blank?
    Membership.other_kept_owners(workspace_id, excluding: id).exists?
  end

  # Discarded → kept. Direction matters: the same column change in the other
  # direction is a removal.
  def just_reactivated?
    saved_change_to_discarded_at? && discarded_at.nil?
  end

  # The before-value matters: a re-stamp on an already-removed row is not a removal.
  def just_deactivated?
    saved_change_to_discarded_at? && discarded_at.present? && discarded_at_before_last_save.nil?
  end
end
