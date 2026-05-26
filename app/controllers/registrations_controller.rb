class RegistrationsController < ApplicationController
  include Signupable

  allow_unauthenticated_access
  require_unauthenticated_access only: :new
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: t("registrations.create.rate_limited") }

  def new
    if signups_open?
      @user = User.new
    else
      render :closed
    end
  end

  def create
    unless signups_open?
      render :closed, status: :unprocessable_entity
      return
    end

    @user = User.new(registration_params)
    authentication = nil

    success = commit_signup_atomically(@user) do |user|
      authentication = user.authentications.create!(
        provider: "email",
        uid: user.email_address
      )
      authentication.generate_verification_token!
    end

    if success
      AuthenticationMailer.verification_email(authentication).deliver_later
      start_new_session_for(@user)
      redirect_to root_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(
      :email_address, :first_name, :last_name,
      :password, :password_confirmation
    )
  end
end
