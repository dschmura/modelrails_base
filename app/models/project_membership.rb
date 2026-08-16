class ProjectMembership < ApplicationRecord
  include Broadcastable

  belongs_to :project
  belongs_to :user

  enum :role, { creator: "creator", editor: "editor", viewer: "viewer" }, default: "editor"

  validates :user_id, uniqueness: { scope: :project_id }
  validate :user_is_workspace_member, on: :create

  # Lambda form (not symbols) — symbol form trips ActiveSupport's callback
  # de-duplication; see Broadcastable's note on this.
  after_create_commit -> { notify_project_membership_changed }
  after_update_commit -> { notify_project_membership_changed }, if: :saved_change_to_role?

  scope :pinned, -> { where(pinned: true) }

  def self.broadcast_events
    [ :create, :update, :destroy ]
  end

  private

  def broadcast_target
    project
  end

  def user_is_workspace_member
    return unless project&.workspace
    unless project.workspace.memberships.kept.exists?(user: user)
      errors.add(:user, :not_workspace_member)
    end
  end

  def notify_project_membership_changed
    return if user.blank?
    ProjectMembershipChangedNotifier.with(record: self).deliver(user)
  end
end
