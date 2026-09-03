class MagicLinkCallbacksController < ApplicationController
  include Signupable

  allow_unauthenticated_access

  # GET only. Never consumes the token or starts a session — a mail scanner or
  # prefetcher doing a bare GET must not be able to burn a link or sign anyone
  # in. Existing users get a confirmation page whose button POSTs to #sign_in;
  # new users get the registration form (which already POSTs to #create).
  def show
    @token_record = MagicLinkToken.find_valid(params[:token])
    unless @token_record
      redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
      return
    end

    @token = params[:token]
    @email = @token_record.email
    @user = User.find_by(email_address: @token_record.email)
    if @user
      render :confirm
    else
      @user = User.new(email_address: @token_record.email)
      render :new_registration
    end
  end

  def sign_in
    # Consume first, then branch: a sign-in POST for an address with no account
    # is misuse (the confirm page sends unknown addresses to #create), so the
    # token is spent either way (#954).
    token_record = MagicLinkToken.consume!(params[:token])
    user = token_record && User.find_by(email_address: token_record.email)

    unless user
      if (replayed = replayed_sign_in)
        # Not a failure: this browser is signed in as the address the token
        # belongs to, so the POST that spent it is the one that signed them in.
        # Answering "invalid or has expired" here tells a signed-in user the
        # opposite of what just happened (#846).
        redirect_to magic_link_return_path(replayed), notice: t("magic_link_callbacks.show.signed_in")
        return
      end

      redirect_to(authenticated? ? root_path : new_session_path, alert: t("magic_link_callbacks.show.invalid"))
      return
    end

    start_new_session_for(user)
    redirect_to magic_link_return_path(token_record), notice: t("magic_link_callbacks.show.signed_in")
  end

  def create
    token_record = MagicLinkToken.find_valid(params[:token])
    unless token_record
      redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
      return
    end

    unless signups_open?
      redirect_to new_session_path,
                  alert: t("registrations.closed.oauth_blocked"),
                  status: :see_other
      return
    end

    @user = User.new(
      email_address: token_record.email,
      first_name: params[:user][:first_name],
      last_name: params[:user][:last_name]
    )

    token_consumed = false

    success = commit_signup_atomically(@user) do |user|
      # Atomic compare-and-swap: if a concurrent request already consumed the
      # token, raise Rollback to unwind user creation — no orphaned User row.
      token_consumed = MagicLinkToken.consume!(params[:token])
      raise ActiveRecord::Rollback unless token_consumed

      user.authentications.create!(
        provider: "email",
        uid: user.email_address,
        verified_at: Time.current
      )
    end

    if success && token_consumed
      start_new_session_for(@user)
      # Here, not inside commit_signup_atomically: a concurrently-consumed
      # token rolls the signup back yet still returns true, and never from a
      # User callback (see WelcomeNotifier).
      WelcomeNotifier.with(record: @user).deliver(nil)
      redirect_to after_authentication_url, notice: t(".registered")
    elsif @user.errors.any?
      # User failed model validation — re-render the registration form.
      @token = params[:token]
      @email = token_record.email
      render :new_registration, status: :unprocessable_entity
    else
      # Token was consumed by a concurrent request — treat as invalid.
      redirect_to(authenticated? ? root_path : new_session_path, alert: t(".invalid"))
    end
  end

  private

  # The spent token this same browser already redeemed, or nil.
  #
  # A second POST of one token is ordinary: a double-clicked confirm button, a
  # browser retrying a POST, a driver re-dispatching a click on a loaded CI
  # shard. `consume!` is single-use, so the replay comes back nil and looks
  # exactly like an expired link — except the session the first POST created is
  # live, which no expiry and no superseding mint can produce.
  #
  # Matching on the address is the fence: only the owner may read a spent token
  # as their own replay. A signed-in visitor holding somebody else's used link
  # still gets the invalid alert, and no session is started either way.
  def replayed_sign_in
    return nil unless authenticated?

    spent = MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(params[:token]))
    return nil if spent.nil? || spent.consumed_at.nil?

    spent if spent.email == Current.user.email_address
  end

  # Server-side intent → fixed path. Never trust a user-supplied URL here.
  def magic_link_return_path(token_record)
    case token_record.intent
    when "set_password" then edit_settings_password_path
    else after_authentication_url
    end
  end
end
