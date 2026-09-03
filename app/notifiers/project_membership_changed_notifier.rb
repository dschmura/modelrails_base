# frozen_string_literal: true

class ProjectMembershipChangedNotifier < ApplicationNotifier
  category :project_activity
  severity :info
  record_preloads project: :workspace

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.project_membership_changed.message",
          locale: recipient_locale,
          project: event.record.project.name,
          new_role: event.record.role.to_s.titleize
        )
      end
    end

    def url
      # Projects are nested under their workspace; a bare project_path never
      # existed. Nothing rendered a notifier url in-app before #919, which is
      # how this stayed hidden.
      project = event.record.project
      Rails.application.routes.url_helpers.workspace_project_path(project.workspace, project)
    end
  end
end
