class Workspace < ApplicationRecord
  include Discardable
  include Trackable
  include Broadcastable
  include Sluggable

  has_one_attached :logo
  has_one_attached :logo_original
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles, dependent: :destroy
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :projects, dependent: :destroy

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  validates :name, presence: true, length: { maximum: 255 }
  validates :logo,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 5.megabytes }
  validates :logo_original,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 10.megabytes }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validates :max_projects, numericality: { greater_than: 0 }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
  validates :logo_source, inclusion: { in: %w[upload initials] }

  def self.broadcast_events
    [ :update ]
  end

  def discard!
    transaction do
      super
      projects.kept.find_each(&:discard!)
    end
  end

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
  end

  def owner
    # Uses detect (not joins + find_by) so it works from preloaded
    # memberships without firing a per-row query in list views.
    memberships.detect { |m| m.role.slug == "owner" }&.user
  end

  # Returns all User records currently holding an owner-role kept membership
  # in this workspace. Used by the capacity-approaching sweep to broadcast a
  # billing alert to every owner, and exposed for future ownership-management
  # UIs that need the full owner roster (vs. `#owner`, which returns just one).
  #
  # Two-path implementation to avoid an N+1 on `workspaces#index` without
  # introducing staleness on mutating call sites:
  #
  # * When `memberships` is already loaded (controller preloads
  #   `memberships: [:role, { user: ... }]` for the index page), filter the
  #   in-memory Array — zero extra queries per row. This is the hot path:
  #   `MembershipPolicy#destroy?` calls `.owners.size` on every Leave-button
  #   render.
  # * When `memberships` is NOT loaded (notifier recipient resolution after
  #   a membership mutation), issue a fresh narrow query so we see the
  #   latest committed state. The notifiers run after mutations that change
  #   the owner roster; we cannot reuse a cached Array there without risk
  #   of stale reads.
  def owners
    relation = memberships.loaded? ? memberships : memberships.kept.includes(:role, :user)
    relation
      .reject(&:discarded?)
      .select { |m| m.role.slug == "owner" }
      .map(&:user)
      .compact
  end

  def available_logo_sources
    %w[upload initials]
  end

  def effective_roles
    Role.where(workspace_id: [ nil, id ])
  end

  private
end
