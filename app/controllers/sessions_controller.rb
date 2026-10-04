class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  skip_onboarding_requirement only: :destroy
  require_unauthenticated_access only: :new
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

  def new
  end

  def create
    @password_sign_in = PasswordSignIn.new(email_address: params[:email_address], password: params[:password])

    if (user = @password_sign_in.user)
      start_new_session_for(user)
      user.register_successful_login!
      redirect_to after_authentication_url, notice: t(".success")
    else
      render "sessions/passwords/new", status: :unprocessable_content
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: t(".success")
  end
end
