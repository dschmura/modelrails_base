class MagicLinkRegistrationsController < ApplicationController
  allow_unauthenticated_access

  def show
    @token_record = MagicLinkToken.find_valid(params[:token])
    if @token_record.nil?
      redirect_to new_session_path, alert: t(".invalid_or_expired")
      return
    end
    @user = User.new(email_address: @token_record.email)
  end

  def create
    @token_record = MagicLinkToken.find_valid(params[:token])
    if @token_record.nil?
      redirect_to new_session_path, alert: t(".invalid_or_expired")
      return
    end

    @user = User.new(
      email_address: @token_record.email,
      first_name: params[:user][:first_name],
      last_name: params[:user][:last_name]
    )

    if @user.save
      @user.authentications.create!(
        provider: "email",
        uid: @user.email_address,
        verified_at: Time.current
      )
      @token_record.consume!
      start_new_session_for(@user)
      redirect_to root_path, notice: t(".success")
    else
      render :show, status: :unprocessable_entity
    end
  end
end
