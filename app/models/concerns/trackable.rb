module Trackable
  extend ActiveSupport::Concern

  SENSITIVE_ATTRIBUTES = %w[
    token password_digest password_reset_token
    oauth_token oauth_refresh_token
  ].freeze

  included do
    has_many :activities, as: :trackable, class_name: "ActivityLog"
    after_commit :track_creation, on: :create
    after_commit :track_update, on: :update
  end

  private

  def track_creation
    create_activity("#{model_name.param_key}.created")
  end

  def track_update
    changes = previous_changes.except("updated_at", "created_at")
    changes = changes.except(*SENSITIVE_ATTRIBUTES)
    return if changes.empty?
    create_activity("#{model_name.param_key}.updated", changes: changes)
  end

  def create_activity(action, metadata = {})
    ActivityLog.create!(
      actor: Current.user,
      action: action,
      trackable: self,
      workspace: resolve_workspace_for_activity,
      metadata: metadata
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Activity tracking failed for #{self.class.name}##{id} (#{action}): #{e.message}")
  end

  def resolve_workspace_for_activity
    if respond_to?(:workspace)
      workspace
    elsif respond_to?(:project) && project&.respond_to?(:workspace)
      project.workspace
    else
      Current.workspace
    end
  end
end
