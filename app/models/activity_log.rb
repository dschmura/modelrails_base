class ActivityLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :trackable, polymorphic: true
  belongs_to :workspace, optional: true

  enum :visibility, { workspace: "workspace", admin: "admin" }, default: "workspace"

  validates :action, presence: true

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :visible, -> { where(visibility: "workspace") }
  scope :recent, -> { order(created_at: :desc).limit(20) }
end
