class OmniauthCallbacksController < ApplicationController
  include Signupable

  allow_unauthenticated_access

  def create
    identity = OauthIdentity.new(request.env["omniauth.auth"])
    resume_session
    existing = Authentication.find_by(provider: identity.provider, uid: identity.uid)

    if existing
      handle_existing_auth(existing, identity)
    elsif Current.user
      handle_signed_in_link(Current.user, identity)
    else
      handle_new_user_oauth(identity)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ArgumentError
    redirect_to fallback_path,
      alert: t("omniauth_callbacks.create.linking_failed")
  end

  def failure
    redirect_to new_session_path,
      alert: t("sessions.create.oauth_failure")
  end

  private

  def handle_existing_auth(auth, identity)
    if Current.user.present? && Current.user.id != auth.user_id
      # Cross-user collision: the OAuth provider+uid is already linked to a
      # different user. Notify the legitimate owner (defense-in-depth) so
      # they're aware someone tried to attach their identity elsewhere.
      # Throttled to prevent flooding a victim if many attackers attempt this.
      if EmailRecipientThrottle.allow!(auth.user.email_address, kind: :collision_alert)
        AuthenticationMailer.collision_alert(auth.user, identity.provider_name).deliver_later
      end
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user", provider: identity.provider_name)
    elsif auth.pending?
      if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
        AuthenticationMailer.link_verification_email(auth).deliver_later
      end
      redirect_to fallback_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: auth.email)
    else
      auth.update!(identity.auth_attrs)
      start_new_session_for(auth.user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    end
  end

  def handle_signed_in_link(user, identity)
    existing = user.authentications.find_by(provider: identity.provider)

    if existing&.verified?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked", provider: identity.provider_name)
      return
    elsif existing&.pending?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.pending_in_progress",
                 provider: identity.provider_name, email: existing.email)
      return
    end

    if identity.email.blank?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.linking_failed")
      return
    end

    auth = user.authentications.build(
      provider: identity.provider,
      uid: identity.uid,
      email: identity.email,
      **identity.auth_attrs
    )

    if EmailNormalizer.equivalent?(identity.email, user.email_address) && identity.email_verified?
      auth.verified_at = Time.current
      auth.save!
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: identity.provider_name)
    else
      auth.save!
      if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
        AuthenticationMailer.link_verification_email(auth).deliver_later
      end
      flash[:confirming_email_for] = auth.id
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending", email: identity.email, provider: identity.provider_name)
    end
  end

  def handle_new_user_oauth(identity)
    unless signups_open?
      redirect_to new_session_path,
                  alert: t("registrations.closed.oauth_blocked"),
                  status: :see_other
      return
    end

    if identity.email_verified?
      handle_verified_email_oauth(identity)
    else
      handle_unverified_email_oauth(identity)
    end
  end

  def handle_verified_email_oauth(identity)
    existing = find_verified_user_by_email(identity.email)
    @user = existing || create_user_from_oauth(identity)

    # A pre-existing user linking a new verified provider must not be silently
    # force-joined by a pending join token riding the session (drive-by join).
    success = commit_signup_atomically(@user, newly_registered: existing.nil?) do |user|
      user.authentications.create!(
        provider: identity.provider,
        uid: identity.uid,
        email: identity.email,
        verified_at: Time.current,
        **identity.auth_attrs
      )
    end

    if success
      start_new_session_for(@user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    else
      redirect_to new_session_path, alert: t("omniauth_callbacks.create.linking_failed")
    end
  end

  def handle_unverified_email_oauth(identity)
    # OAuth provider explicitly reports email as unverified (e.g., Google's
    # info.email_verified: false). Refuse to auto-link to an existing user
    # (account-takeover risk) and refuse to auto-verify. Create the user
    # fresh — if the email already belongs to another account, User
    # validation/uniqueness raises and the outer rescue surfaces a generic
    # "linking failed" alert. Otherwise, create the auth as pending and
    # email a verification link without signing the user in.
    #
    # NOTE: does NOT call commit_signup_atomically — that concern calls
    # accept_pending_invitation! which would consume the invitation immediately.
    # Instead, we persist the invitation token on the pending Authentication so
    # it can be claimed when the user proves email ownership by clicking the
    # verification link (Settings::ConnectedAccountsController#verify, Task 9).
    auth = nil
    ApplicationRecord.transaction do
      user = create_user_from_oauth(identity)
      auth = user.authentications.build(
        provider: identity.provider,
        uid: identity.uid,
        email: identity.email,
        # Park both pending claims for the deferred-OAuth flow (mirror
        # registrations_controller).
        pending_invitation_token: session[:pending_invitation_token],
        pending_join_link_digest: parked_join_digest,
        **identity.auth_attrs
      )
      auth.save!
    end

    # Tokens are safely persisted on the Authentication; clear from session.
    session.delete(:pending_invitation_token)
    session.delete(:pending_join_token)

    # deliver_later runs after the transaction commits (project convention:
    # deliver_later inside a transaction can enqueue a job that fires on rollback).
    if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
      AuthenticationMailer.link_verification_email(auth).deliver_later
    end
    redirect_to new_session_path,
      notice: t("omniauth_callbacks.create.unverified_email_pending", email: identity.email)
  end

  def fallback_path
    Current.user.present? ? settings_connected_accounts_path : new_session_path
  end

  # The join token is hashed at rest (WorkspaceJoinLink stores only a digest),
  # so park the digest — not the plaintext — for the deferred-OAuth claim.
  def parked_join_digest
    token = session[:pending_join_token]
    WorkspaceJoinLink.digest(token) if token.present?
  end

  def find_verified_user_by_email(email)
    user = User.find_by(email_address: email)
    return nil unless user
    return user if user.authentications.email.where.not(verified_at: nil).exists?
    nil
  end

  def create_user_from_oauth(identity)
    User.create!(
      email_address: identity.email,
      first_name: identity.first_name,
      last_name: identity.last_name
    )
  end
end
