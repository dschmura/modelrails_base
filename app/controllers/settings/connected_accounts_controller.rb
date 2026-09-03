module Settings
  class ConnectedAccountsController < ApplicationController
    before_action :require_reauthentication!, only: :destroy
    layout "settings"

    rate_limit to: 3, within: 3.minutes, only: :resend_verification,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        redirect_to settings_connected_accounts_path,
          alert: t("settings.connected_accounts.resend_verification.rate_limited")
      }

    def index
      @authentications = Current.user.authentications
    end

    def resend_verification
      auth = Current.user.authentications.find(params[:id])

      if auth.verified?
        redirect_to settings_connected_accounts_path,
          alert: t(".already_verified")
      else
        if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
          AuthenticationMailer.link_verification_email(auth).deliver_later
        end
        redirect_to settings_connected_accounts_path,
          notice: t(".resent", email: auth.email)
      end
    end

    def destroy
      destroyed_auth = nil

      destroyed = Authentication.transaction do
        # `.lock` issues SELECT FOR UPDATE on Postgres/MySQL. SQLite no-ops it,
        # but BEGIN IMMEDIATE (Rails default) gives database-wide write
        # serialization for the transaction's duration — same correctness.
        destroyed_auth = Current.user.authentications.lock.find(params[:id])

        if destroyed_auth.only_verified_remaining?
          false
        else
          destroyed_auth.destroy!
          true
        end
      end

      if destroyed
        redirect_to settings_connected_accounts_path,
          notice: t(".success", provider: destroyed_auth.display_provider)
      else
        redirect_to settings_connected_accounts_path,
          alert: t(".cannot_remove_last_verified")
      end
    end
  end
end
