class MagicLinksController < ApplicationController
  allow_unauthenticated_access

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 5, within: 3.minutes, only: :create,
    store: RATE_LIMIT_STORE,
    with: -> { redirect_to new_session_path, alert: t("magic_links.create.rate_limited") }

  def create
    email = params[:email_address]&.downcase&.strip
    user = User.find_by(email_address: email)

    if user
      user.generate_magic_link_token!
      MagicLinkMailer.sign_in_link(user).deliver_later
    end

    # Always show same message — no information leakage
    redirect_to new_session_path, notice: t(".check_email")
  end
end
