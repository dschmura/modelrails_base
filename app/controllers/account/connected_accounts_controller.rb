module Account
  class ConnectedAccountsController < ApplicationController
    include PersonalWorkspaceContext
    layout "settings"

    allow_unauthenticated_access only: :verify

    rate_limit to: 3, within: 3.minutes, only: :resend_verification,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        redirect_to account_connected_accounts_path,
          alert: t("account.connected_accounts.resend_verification.rate_limited")
      }

    def index
      @authentications = Current.user.authentications
    end

    def verify
      auth = Authentication.find_by(verification_token: params[:token])

      if auth.nil? || auth.token_expired?
        redirect_to(authenticated? ? account_connected_accounts_path : new_session_path,
                    alert: t(".invalid_or_expired"))
        return
      end

      # Cross-user case reuses invalid_or_expired flash deliberately:
      # never confirm or deny that a token belongs to a different account.
      if authenticated? && Current.user.id != auth.user_id
        redirect_to account_connected_accounts_path,
          alert: t(".invalid_or_expired")
        return
      end

      was_authenticated = authenticated?

      auth.verify!

      # For unauthenticated callers verifying their first auth (new-user OAuth
      # unverified-email flow from Task 8), sign them in now that their email
      # is proven. This is a one-shot sign-in tied to email verification.
      start_new_session_for(auth.user) unless was_authenticated

      # Claim any pending invitation that was persisted onto this Authentication
      # during unverified-email OAuth signup. A stale invitation (consumed by
      # someone else, expired, etc.) shouldn't block sign-in — surface as flash
      # but continue.
      begin
        auth.claim_pending_invitation!(Current.user)
      rescue Invitation::NotAcceptable
        flash[:alert] = t("registrations.create.invitation_consumed")
      end

      if was_authenticated
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: auth.display_provider)
      else
        redirect_to root_path, notice: t(".success", provider: auth.display_provider)
      end
    end

    def resend_verification
      auth = Current.user.authentications.find(params[:id])

      if auth.verified?
        redirect_to account_connected_accounts_path,
          alert: t(".already_verified")
      else
        auth.generate_verification_token!
        if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
          AuthenticationMailer.link_verification_email(auth).deliver_later
        end
        redirect_to account_connected_accounts_path,
          notice: t(".resent", email: auth.email)
      end
    rescue ActiveRecord::RecordNotUnique
      # The model retries on RecordNotUnique up to TOKEN_GENERATION_MAX_ATTEMPTS
      # times. Reaching here means every regenerated token still collided —
      # effectively impossible with 256 bits of entropy, but defended-in-depth.
      redirect_to account_connected_accounts_path,
        alert: t(".token_collision")
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
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: destroyed_auth.display_provider)
      else
        redirect_to account_connected_accounts_path,
          alert: t(".cannot_remove_last_verified")
      end
    end
  end
end
