# frozen_string_literal: true

class PasswordChangedNotifier < ApplicationNotifier
  category :security

  required_param :resource

  notification_methods do
    def message
      I18n.t(
        "notifications.password_changed.message",
        locale: recipient_locale,
        user_name: event.params[:resource].first_name
      )
    end

    def url
      # Account security / connected-accounts page; full wiring in PR-3.
      Rails.application.routes.url_helpers.account_connected_accounts_path
    rescue NoMethodError
      "/account/security"
    end
  end
end
