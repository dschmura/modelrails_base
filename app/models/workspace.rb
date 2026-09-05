class Workspace < ApplicationRecord
  include Discardable
  include Archivable
  include Suspendable
  include Trackable
  include Broadcastable
  # `name` stays plaintext while other personal data is encrypted (#902,
  # ruling R3): the slug is the name parameterized, and sits in every URL.
  include Sluggable

  # Defense in depth behind WorkspacePolicy — covers console/direct-call paths the policy never sees.
  HomeWorkspaceProtectedError = Class.new(StandardError)

  # Non-disclosing by contract: an outsider must not learn which lifecycle state blocked them.
  # See /docs/developer/architecture (Key Concepts).
  NotAdmittableError = Class.new(StandardError)
  # Typed so callers never match the humanized validation string (locale edits break it).
  AlreadyMember = Class.new(StandardError)
  AtCapacity = Class.new(StandardError)

  has_one_attached :logo
  has_one_attached :logo_original
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles, dependent: :destroy
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :projects, dependent: :destroy

  # :delete_all because ActivityLog#readonly? refuses instance destroy — a reviewed bypass (#921).
  # See /docs/developer/architecture (Activity Tracking).
  has_many :activity_logs, dependent: :delete_all

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  # Composes with the instance-level SignupPolicy.permits_strategy? allowlist. See /docs/developer/presets.
  enum :join_policy, { invite: "invite", open_link: "open_link" }, default: "invite"

  has_many :join_links, class_name: "WorkspaceJoinLink", dependent: :destroy

  # Gate for the created notification: .create_owned sets it; seeds, fixtures and signup-time creation stay silent.
  # See /docs/developer/notifications (The actor rule).
  attr_accessor :created_by

  # _commit, not after_create: enqueuing into Solid Queue's SQLite under the primary write lock is a lock-ordering hazard.
  after_create_commit :notify_workspace_created, if: -> { created_by.present? }

  validates :name, presence: true, length: { maximum: 255 }
  validates :logo,
    content_type: IMAGE_CONTENT_TYPES,
    size: { less_than: 5.megabytes }
  validates :logo_original,
    content_type: IMAGE_CONTENT_TYPES,
    size: { less_than: 10.megabytes }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validates :max_projects, numericality: { greater_than: 0 }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
  validates :logo_source, inclusion: { in: %w[upload initials] }
  validate :personal_workspaces_are_invite_only
  validate :join_policy_must_be_permitted_by_instance

  def self.broadcast_events
    [ :update ]
  end

  # Time === ActiveSupport::TimeWithZone is true (case-equality is special-cased) — don't "fix" the Time patterns.
  # Display goes through LifecycleHelper#lifecycle_status_label, never status.to_s.
  def status
    case [ discarded_at, suspended_at, archived_at ]
    in [ Time, * ]     then :discarded
    in [ _, Time, * ]  then :suspended
    in [ _, _, Time ]  then :archived
    else                    :active
    end
  end

  # Compared by slug, never a query, so it stays correct whatever the workspace's own lifecycle state.
  def home?
    personal? || (TenancyConfig.shared? && slug == TenancyConfig.shared_workspace_slug)
  end

  # Derived from `status` so a future lifecycle state fails CLOSED here instead of silently admitting.
  def admittable?
    status == :active
  end

  # `next`, not `return`: an early exit commits nothing. See /docs/developer/architecture (Concurrency).
  def archive!
    transaction do
      lock!
      next if archived?
      raise HomeWorkspaceProtectedError if home?
      raise Suspendable::SuspendedError if suspended?
      super
    end
  end

  def unarchive!
    transaction do
      lock!
      next unless archived?
      raise Suspendable::SuspendedError if suspended?
      super
    end
  end

  def discard!
    transaction do
      lock!
      next if discarded?
      raise HomeWorkspaceProtectedError if home?
      raise Suspendable::SuspendedError if suspended?
      projects.kept.find_each(&:discard!)
      super
    end
  end

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
  end

  def owner
    # detect over preloaded memberships, no per-row query in lists. See /docs/developer/architecture (Owner Lookup).
    ms = memberships.loaded? ? memberships : memberships.includes(:role, :user)
    ms.detect(&:owner?)&.user
  end

  # Always a fresh query, even when memberships is loaded. See /docs/developer/architecture (Owner Lookup).
  def owners
    memberships.kept
      .joins(:role)
      .where(roles: { slug: "owner" })
      .includes(:user)
      .map(&:user)
      .compact
  end

  def available_logo_sources
    %w[upload initials]
  end

  def identity
    WorkspaceIdentity.new(self)
  end

  def effective_roles
    Role.where(workspace_id: [ nil, id ])
  end

  def open_join?
    open_link? && !personal? && SignupPolicy.permits_strategy?(:open_link)
  end

  # SignupPolicy's gate checks open_join? only; admittable? is re-checked here at claim time.
  def accepting_open_joins?
    open_join? && admittable?
  end

  # `>=` here vs the after-create net's strict `>` — both deliberate. See /docs/developer/architecture (Concurrency).
  def at_capacity?
    memberships.kept.count >= max_members
  end

  # Pinned to the lowest-privilege system role; per-link role customization is deliberately deferred.
  def default_self_join_role
    Role.find_by!(slug: "member", workspace_id: nil)
  end

  # The one membership-grant entry point (invitations and open-link self-joins). granted_by: audit
  # provenance only; self_join: the joiner acted; on_existing: :raise or :adopt.
  # See /docs/developer/notifications (The actor rule) and /docs/developer/architecture (Authorization).
  def admit(user, role:, granted_by: nil, self_join: false, on_existing: :raise)
    Membership.reject_conflicting_provenance!(granted_by: granted_by, self_join: self_join)
    transaction do
      lock!
      raise NotAdmittableError unless admittable?
      existing = memberships.find_by(user: user)
      if existing&.discarded?
        existing.reactivate!(granted_by: granted_by, self_join: self_join)
        existing
      elsif existing
        raise AlreadyMember unless on_existing == :adopt || TenancyConfig.shared?
        # Rails runs commit callbacks on the LAST saved instance, so this second instance must carry
        # the markers too. See /docs/developer/notifications (The actor rule).
        existing.granted_by = granted_by
        existing.self_join = self_join
        if on_existing != :adopt && existing.role_id != role.id
          # :shared placeholder reconciliation — see /docs/developer/presets.
          existing.update!(role: role)
        end
        existing
      else
        raise AtCapacity if at_capacity?
        memberships.create!(user: user, role: role, granted_by: granted_by, self_join: self_join)
      end
    end
  end

  # Atomic workspace + owner-membership creation (#676): the class-level twin of #create_project.
  # See /docs/developer/architecture (Concurrency).
  def self.create_owned(attrs, owner:)
    workspace = new(attrs)
    workspace.created_by = owner
    transaction do
      if workspace.save
        workspace.memberships.create!(user: owner, role: Role.system_default!("owner"))
      end
    end
    workspace
  end

  # The one project-creation entry point; only suspended? is guarded — archived workspaces accept new
  # projects (#688). See /docs/developer/architecture (Key Concepts, Concurrency).
  def create_project(attrs, creator:)
    transaction do
      lock!
      raise Suspendable::SuspendedError if suspended?
      project = projects.build(attrs)
      project.created_by = creator
      if project.save
        project.project_memberships.create!(user: creator, role: "creator")
      end
      project
    end
  end

  private

  def notify_workspace_created
    WorkspaceCreatedNotifier.with(record: self, creator: created_by).deliver(nil)
  end

  def personal_workspaces_are_invite_only
    return unless personal? && !invite?
    errors.add(:join_policy, :personal_must_be_invite)
  end

  def join_policy_must_be_permitted_by_instance
    return if SignupPolicy.permits_strategy?(join_policy)
    errors.add(:join_policy, :not_permitted_by_instance)
  end
end
