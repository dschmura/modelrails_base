module Account
  class ConnectedAccountsController < ApplicationController
    allow_unauthenticated_access only: :verify

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

      auth.verify!

      if authenticated?
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: auth.provider.titleize)
      else
        redirect_to new_session_path,
          notice: t(".success_signed_out", provider: auth.provider.titleize)
      end
    end

    def destroy
      authentication = Current.user.authentications.find(params[:id])

      if Current.user.authentications.count <= 1
        redirect_to account_connected_accounts_path,
          alert: t(".last_method")
      else
        authentication.destroy!
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: authentication.provider.titleize)
      end
    end
  end
end
