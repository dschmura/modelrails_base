class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :show

  def new
    @authentication = Current.user&.authentications&.email&.first
  end

  def show
    authentication = Authentication.find_by_token_for(:email_verification, params[:token])

    if authentication.nil?
      redirect_to root_path, alert: t(".invalid_or_expired")
    else
      authentication.verify!
      redirect_to root_path, notice: t(".success")
    end
  end
end
