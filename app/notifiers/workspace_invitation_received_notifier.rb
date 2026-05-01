# frozen_string_literal: true

class WorkspaceInvitationReceivedNotifier < ApplicationNotifier
  category :account_access

  required_param :resource

  notification_methods do
    def message
      I18n.t(
        "notifications.workspace_invitation_received.message",
        locale: recipient_locale,
        workspace: event.params[:resource].invitable.name,
        inviter: event.params[:resource].invited_by&.email_address
      )
    end

    def url
      # Routes to the accept-invitation page; full wiring with workspace context in PR-3.
      Rails.application.routes.url_helpers.accept_invitation_path(
        token: event.params[:resource].token
      )
    rescue NoMethodError
      "/invitations/#{event.params[:resource].token}/accept"
    end
  end
end
