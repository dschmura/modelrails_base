# frozen_string_literal: true

# Fires when someone creates a workspace through `Workspace.create_owned`.
# The single recipient is the creator: partly a receipt, partly onboarding —
# it puts something on a brand-new account's notifications page and points at
# the next useful step (inviting people).
#
# The creator rides as a param, not off the record: `workspaces` has no
# created_by column, and the transient `Workspace#created_by` that gates the
# callback is not readable once the event is reloaded.
class WorkspaceCreatedNotifier < ApplicationNotifier
  category :workspace_activity
  severity :success

  required_param :creator

  recipients do
    permitted_in_app([ params[:creator] ].compact)
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_created.message",
          locale: recipient_locale,
          workspace: event.record.name
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.workspace_members_path(event.record)
    end
  end
end
