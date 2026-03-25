class PasswordsController < ApplicationController
  allow_unauthenticated_access

  def new
  end

  def create
    user = User.find_by(email_address: params[:email_address])
    if user
      user.generate_reset_password_token!
      AuthenticationMailer.password_reset_email(user).deliver_later
    end
    # Always redirect — don't reveal whether email exists
    redirect_to new_session_path, notice: t(".success")
  end

  def edit
    @user = User.find_by(reset_password_token: params[:token])
    if @user.nil? || @user.reset_password_token_expired?
      redirect_to new_password_path, alert: t(".invalid_or_expired_token")
    end
  end

  def update
    @user = User.find_by(reset_password_token: params[:token])
    if @user.nil? || @user.reset_password_token_expired?
      redirect_to new_password_path, alert: t(".invalid_or_expired_token")
      return
    end

    if @user.update(password_params)
      @user.clear_reset_password_token!
      redirect_to new_session_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
