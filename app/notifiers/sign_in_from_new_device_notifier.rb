# frozen_string_literal: true

# Fires the first time a user signs in from a (user_agent, os) digest we
# haven't recorded for them. Mirrors PasswordChangedNotifier's shape:
# `category :security` so it auto-registers as a security type and bypasses
# DND, with both in-app and email channels gated by per-recipient
# preferences. Email uses the `before_enqueue throw(:abort)` idiom so an
# opt-out skips the job entirely rather than enqueueing-then-discarding.
class SignInFromNewDeviceNotifier < ApplicationNotifier
  category :security

  required_param :user_agent, :os

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :sign_in_from_new_device
    config.before_enqueue = -> { throw(:abort) unless recipient_pref(:email) }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.sign_in_from_new_device.message",
          locale: recipient_locale,
          os: event.params[:os]
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.account_connected_accounts_path
    end
  end
end
