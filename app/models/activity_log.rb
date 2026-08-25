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

  enum :visibility, { workspace: "workspace", admin: "admin", personal: "personal" }, default: "workspace"

  # The security tier: the ONLY membership test for the audit retention floor.
  # Writers (User password callbacks, WebauthnCredential, Authenticatable) and
  # ActivityLogRetentionSweepJob's exemption reference this same constant —
  # never re-derive the set from visibility, which also carries non-security
  # personal/admin rows. Spec: activity_log_retention_sweep_job_spec.
  SECURITY_ACTIONS = %w[
    user.password_changed
    user.password_removed
    user.signed_in_new_device
    user.passkey_added
    user.passkey_removed
  ].freeze

  validates :action, presence: true

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :visible, -> { where(visibility: "workspace") }
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
