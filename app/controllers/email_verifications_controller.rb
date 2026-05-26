class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access

  def show
    authentication = Authentication.find_by_token_for(:email_verification, params[:token])

    if authentication.nil?
      # Signed tokens can't distinguish "tampered" from "expired" — both surface
      # as a nil lookup, so we show a single combined message.
      redirect_to root_path, alert: t(".invalid_or_expired")
    else
      authentication.verify!
      redirect_to root_path, notice: t(".success")
    end
  end
end
