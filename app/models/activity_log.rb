class ActivityLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  # No FK on actor_id; the row keeps an encrypted name snapshot instead (#1122,
  # see /docs/developer/architecture, "An audit row outlives the people in it").
  encrypts :actor_name
  belongs_to :trackable, polymorphic: true
  belongs_to :workspace, optional: true

  # The audit trail is best-effort to write (Trackable rescues rather than
  # failing the business operation — see /docs/developer/architecture) and immutable
  # after: persisted rows refuse instance-level update/destroy. Relation-level
  # bypasses (update_all/delete_all) are fenced by
  # spec/code_smells/activity_log_immutability_spec.rb, where the retention
  # sweep job (#438) has its explicit carve-out.
  def readonly? = persisted?

  # Derived, never caller-supplied. Pre-#1122 rows have none and resolve live (#1250).
  before_create do
    self.actor_name = actor&.full_name
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
    user.suspended
    user.unsuspended
    user.unlocked
    operatorship.granted
    operatorship.revoked
  ].freeze

  # The members whose writer records the device os in metadata (Authenticatable's
  # new-device sign-in); the account activity card renders their _with_os label.
  SECURITY_ACTIONS_WITH_OS = %w[user.signed_in_new_device].freeze

  # The one writer for security-tier rows (User password callbacks,
  # WebauthnCredential, Authenticatable, Operatorship all route here); the
  # row shape lives in exactly one place. `actor:` and `visibility:` default
  # to the self-event shape — the subject is the actor, personal visibility —
  # and a writer whose actor is someone else (an operator acting on a user)
  # overrides both, writing admin visibility so the row lands in the
  # operations feed rather than the subject's account card.
  #
  # A non-member action raises: a drifted literal ("user.passkey_add") would
  # otherwise write a plausible row the sweep deletes at 12 months instead of
  # the security floor, with the suite green. ArgumentError on purpose — a
  # programmer error propagates rather than being swallowed; callers choose
  # the write guarantee by rescuing or not.
  def self.record_security_event!(action:, user:, actor: user, visibility: "personal", metadata: {})
    unless SECURITY_ACTIONS.include?(action)
      raise ArgumentError, "#{action.inspect} is not in ActivityLog::SECURITY_ACTIONS"
    end

    create!(action: action, actor: actor, trackable: user,
            visibility: visibility, workspace_id: nil, metadata: metadata)
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
  # the self-event default is personal, but an operator-actor row
  # (Operatorship's grant/revoke) is written at admin visibility on purpose,
  # so it belongs in the operations feed, not this card — this predicate is
  # what keeps it out.
  scope :security_events_for, ->(user) {
    where(action: SECURITY_ACTIONS, trackable: user, visibility: :personal)
      .order(created_at: :desc)
  }
  scope :recent, -> { order(created_at: :desc).limit(20) }
  # Hidden even from an operator who is also the inviter (security.md invariant I3).
  INVITER_UNREADABLE_ACTIONS = %w[invitation.delivery_suppressed].freeze

  # The operations feed: workspace and admin rows, never personal — an
  # operator reading a user's own security events is a privacy decision the
  # template leaves to a fork. id breaks the created_at tie: this is the app's
  # only OFFSET-paginated feed, and rows written in one burst (bulk_invite!)
  # share a timestamp, so without it a row can land on two pages or neither.
  scope :for_operations_feed, -> {
    where(visibility: %w[workspace admin])
      .where.not(action: INVITER_UNREADABLE_ACTIONS)
      .order(created_at: :desc, id: :desc)
  }
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

  # Only rows the viewer may open (#1154). A Trackable type in neither list is dropped
  # on purpose; activity_log_feed_scope_spec fails on an unclassified one.
  WORKSPACE_LEVEL_TRACKABLES = %w[Workspace Membership].freeze
  PROJECT_LEVEL_TRACKABLES = %w[Project Resource].freeze
  # Classified by what they hang off, so they appear in both partitions.
  POLYMORPHIC_TRACKABLES = %w[Invitation].freeze

  # `projects:` arrives policy-scoped and stays a subselect, keeping this one query.
  scope :for_workspace_feed, ->(workspace, projects:) {
    project_ids = projects.select(:id)

    workspace_level = where(trackable_type: WORKSPACE_LEVEL_TRACKABLES)
      .or(where(trackable_type: "Invitation",
                trackable_id: Invitation.where(invitable_type: "Workspace", invitable_id: workspace.id).select(:id)))

    project_level = where(trackable_type: "Project", trackable_id: project_ids)
      .or(where(trackable_type: "Resource",
                trackable_id: Resource.where(project_id: project_ids).select(:id)))
      .or(where(trackable_type: "Invitation",
                trackable_id: Invitation.where(invitable_type: "Project", invitable_id: project_ids).select(:id)))

    visible.for_workspace(workspace).merge(workspace_level.or(project_level))
  }

  # One entry per action family; activity_log_filters_spec pins it to the locales.
  # Filters on the action prefix to walk the created_at index; re-EXPLAIN past
  # ~5M rows (measured on in-memory SQLite, #1165).
  KINDS = %w[workspace membership invitation project resource user operatorship].freeze

  scope :of_kind, ->(kind) { where(arel_table[:action].matches("#{kind}.%")) }
  # Rows the person acted in or was the subject of: actor, a User trackable
  # (operator actions on them), or a Membership of theirs. Widening on purpose —
  # a rule-out question must see the superset.
  scope :involving, ->(user) {
    where(actor_id: user.id)
      .or(where(trackable_type: "User", trackable_id: user.id))
      .or(where(trackable_type: "Membership", trackable_id: user.memberships.select(:id)))
  }
  # The ledger search's filter: every record `ActivityLog::Search` resolved,
  # OR'd into one predicate. Widening across the four kinds is the point — an
  # operator ruling something out must see the superset, and a query that
  # named a person and a workspace means either, not both.
  scope :matching_any, ->(users:, workspaces:, projects:) {
    clauses = []
    if users.any?
      ids = users.map(&:id)
      clauses << where(actor_id: ids)
      clauses << where(trackable_type: "User", trackable_id: ids)
      clauses << where(trackable_type: "Membership", trackable_id: Membership.where(user_id: ids).select(:id))
    end
    clauses << where(workspace_id: workspaces.map(&:id)) if workspaces.any?
    clauses << where(trackable_type: "Project", trackable_id: projects.map(&:id)) if projects.any?
    clauses.reduce { |combined, clause| combined.or(clause) } || none
  }
  scope :within, ->(from, to) { where(created_at: from..to) }
  scope :oldest_first, -> { reorder(created_at: :asc, id: :asc) }
  # The ledger's other SQL sort: workspaces.name is the one plaintext name in
  # the table (actor names are encrypted and cannot be ordered — see
  # operations.md, "What it deliberately does not do"). Instance-level rows
  # have no name and sit last in either direction, so "Instance" never reads
  # as a name that sorted first. Direction is checked, not interpolated.
  scope :by_workspace_name, ->(direction) {
    raise ArgumentError, "direction must be asc or desc" unless %w[asc desc].include?(direction.to_s)

    name = Arel.sql("LOWER(workspaces.name)")
    left_joins(:workspace).reorder((direction.to_s == "asc" ? name.asc : name.desc).nulls_last, created_at: :desc, id: :desc)
  }
  scope :at_instance_level, -> { where(workspace_id: nil) }

  # Returns an Array: trackable is polymorphic, so each type preloads on its own
  # slice (#1120).
  def self.for_feed
    # `all`: reached as relation.for_feed, where self is the class.
    logs = all.to_a
    preload_legacy_actors(logs)
    preload_trackables(logs, "Membership") do |members|
      ActiveRecord::Associations::Preloader.new(records: members, associations: :user).call
    end
    preload_trackables(logs, "User")
    logs
  end

  # Only pre-snapshot rows read the actor (#1122). The ops ledger preloads :actor
  # itself, for the live email its pivot needs.
  def self.preload_legacy_actors(logs)
    rows = logs.select do |log|
      log.actor_id.present? && log.actor_name.blank? && !log.association(:actor).loaded?
    end
    return if rows.empty?

    ActiveRecord::Associations::Preloader.new(records: rows, associations: :actor).call
  end
  private_class_method :preload_legacy_actors

  def self.preload_trackables(logs, type)
    rows = logs.select { |log| log.trackable_type == type }
    return if rows.empty?

    ActiveRecord::Associations::Preloader.new(records: rows, associations: :trackable).call
    return unless block_given?

    # Reads the association only when a caller needs it — reading it
    # unconditionally would mark the hop "used" to Bullet regardless of
    # whether anything downstream did, permanently masking an unused eager
    # load. The Membership slice above stays invisible to Bullet the same
    # way, consumed only to feed the nested :user preload.
    trackables = rows.filter_map(&:trackable)
    yield trackables if trackables.any?
  end
  private_class_method :preload_trackables

  # The locale key the feed renders this row with — usually just `action`.
  # A deactivation, a self-removal and a reactivation all arrive as
  # `membership.updated` (Discardable#discard! is an ordinary update), so the
  # one action carries four different sentences and the feed used to call every
  # one of them a role change (#932). The row's own `changes` metadata tells
  # the status changes from the role change; the actor tells a removal from a
  # departure. A status change outranks a role change: `reactivate!` can carry
  # both, and losing or regaining access is the more consequential half.
  # A workspace lock/unlock is the same shape (Suspendable#suspend! is a
  # guarded update! too), splitting workspace.updated on suspended_at
  # instead of discarded_at.
  # Unknown shapes fall through to `action` itself. The partial has no
  # `default:` (the ModelRails/NoI18nDefault cop forbids it, #1022); in test
  # (`raise_on_missing_translations`) a missing activity.actions label raises,
  # while dev/prod render a "translation missing" marker instead.
  # spec/code_smells/dynamic_i18n_keys_have_values_spec.rb is what keeps a
  # missing label from shipping in the first place.
  def display_action
    case action
    when "membership.updated" then membership_display_action
    when "workspace.updated"  then workspace_display_action
    else action
    end
  end

  # The member a membership row is ABOUT, which is not its actor: Trackable
  # records the actor as whoever performed the change, so an owner removing
  # someone produced a row whose only name was the owner's. An operatorship
  # grant/revoke's trackable is a User directly, not a Membership —
  # Operatorship is above the workspace layer (#1120): without this case the
  # row read "granted a member operator access", naming neither party.
  # nil for every other trackable, and for a membership that has since been
  # hard-deleted — the partial supplies the neutral noun.
  def display_member
    return trackable&.full_name if trackable_type == "User"

    tracked_membership&.user&.full_name
  end

  # Four outcomes: the snapshot; a live actor (pre-#1122 rows); "a former member"
  # when that actor is gone; nil for a job or the console. Only membership.created
  # names its member instead, since onboarding creates it before any session exists.
  def display_subject
    return actor_name if actor_name.present?
    # Gated on actor_id so an actorless row never touches the association (Bullet).
    return actor&.full_name || I18n.t("activity.departed_actor") if actor_id.present?

    display_member if display_action == "membership.created"
  end

  # Public because the ledger's details row reads it to name the member a
  # membership row is about (app/views/operations/activity_logs/_row.html.erb).
  def tracked_membership
    return nil unless trackable_type == "Membership"

    trackable
  end

  private

  def membership_display_action
    transition = metadata.to_h.with_indifferent_access.dig(:changes, :discarded_at)
    return action if transition.blank?
    return "membership.reactivated" if transition.last.blank?

    self_removal? ? "membership.left" : "membership.deactivated"
  end

  def workspace_display_action
    transition = metadata.to_h.with_indifferent_access.dig(:changes, :suspended_at)
    return action if transition.blank?

    transition.last.blank? ? "workspace.unsuspended" : "workspace.suspended"
  end

  # The actor removed their own membership, so the row is a departure rather
  # than an eviction.
  def self_removal?
    member = tracked_membership
    member.present? && actor_id.present? && actor_id == member.user_id
  end
end
