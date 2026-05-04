# frozen_string_literal: true

class WorkspaceInvitationAcceptedNotifier < ApplicationNotifier
  category :workspace_activity

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_accepted.message",
          locale: recipient_locale,
          accepter: event.record.accepted_by&.email_address,
          workspace: workspace_name
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.workspace_path(resolved_workspace)
    end

    private

    # The invitation may target a Workspace directly or a Project — in the
    # latter case the workspace context comes from the project's workspace.
    def resolved_workspace
      invitable = event.record.invitable
      invitable.is_a?(Workspace) ? invitable : invitable.workspace
    end

    def workspace_name
      resolved_workspace&.name
    end
  end
end
