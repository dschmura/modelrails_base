# frozen_string_literal: true

class WorkspaceInvitationDeclinedNotifier < ApplicationNotifier
  category :workspace_activity

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_invitation_declined.message",
          locale: recipient_locale,
          decliner_email: event.record.email,
          workspace: workspace_name
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.workspace_path(resolved_workspace)
    end

    private

    def resolved_workspace
      invitable = event.record.invitable
      invitable.is_a?(Workspace) ? invitable : invitable.workspace
    end

    def workspace_name
      resolved_workspace&.name
    end
  end
end
