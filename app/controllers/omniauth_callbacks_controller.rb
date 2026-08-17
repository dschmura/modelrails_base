class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access

  # OauthLink outcome → session key to drop once the outcome spent it.
  SESSION_TOKEN_KEYS = {
    invitation: :pending_invitation_token,
    join: :pending_join_token
  }.freeze

  # The linking decision tree lives in OauthLink (unit-tested there); this
  # action only adapts it to HTTP: session in, redirect + flash out.
  def create
    resume_session
    outcome = OauthLink.new(
      request.env["omniauth.auth"],
      actor: Current.user,
      signups_open: signups_open?,
      invitation_token: session[:pending_invitation_token],
      join_token: session[:pending_join_token]
    ).claim

    outcome.spent_tokens.each { |kind| session.delete(SESSION_TOKEN_KEYS.fetch(kind)) }
    redirect_for(outcome)
  end

  def failure
    redirect_to new_session_path,
      alert: t("sessions.create.oauth_failure")
  end

  private

  def redirect_for(outcome)
    case outcome.code
    when :signed_in
      if outcome.problems.include?(:invitation_email_mismatch)
        flash[:alert] = t("registrations.create.invitation_email_mismatch")
      end
      start_new_session_for(outcome.user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    when :linked
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: outcome.provider_name)
    when :verification_sent
      flash[:confirming_email_for] = outcome.auth.id
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending",
                  email: outcome.email, provider: outcome.provider_name)
    when :verification_resent
      redirect_to fallback_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: outcome.email)
    when :pending_in_progress
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.pending_in_progress",
                 provider: outcome.provider_name, email: outcome.email)
    when :already_linked
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked", provider: outcome.provider_name)
    when :collision
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user", provider: outcome.provider_name)
    when :signups_closed
      redirect_to new_session_path,
        alert: t("registrations.closed.oauth_blocked"),
        status: :see_other
    when :unverified_pending
      redirect_to new_session_path,
        notice: t("omniauth_callbacks.create.unverified_email_pending", email: outcome.email)
    when :failed
      redirect_to fallback_path,
        alert: t("omniauth_callbacks.create.linking_failed")
    else
      raise ArgumentError, "unknown OauthLink outcome: #{outcome.code.inspect}"
    end
  end

  def fallback_path
    Current.user.present? ? settings_connected_accounts_path : new_session_path
  end
end
