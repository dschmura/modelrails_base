class MagicLinkSessionsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = User.find_by(magic_link_token: params[:token])

    if user&.magic_link_token_valid?
      user.clear_magic_link_token!
      start_new_session_for(user)
      redirect_to root_path, notice: t(".success")
    else
      redirect_to new_session_path, alert: t(".invalid_or_expired")
    end
  end
end
