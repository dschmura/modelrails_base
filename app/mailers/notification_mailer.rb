class NotificationMailer < ApplicationMailer
  # Mailer methods invoked by Noticed via `deliver_by :email, mailer: ..., method: ...`.
  # Noticed dispatches through ActionMailer's parameterized API:
  #   NotificationMailer.with(notification:, record:, recipient:, **event_params).workspace_role_changed
  # so each method reads from `params[:notification]` / `params[:record]` / `params[:recipient]`
  # rather than taking positional arguments. See Noticed::DeliveryMethods::Email for the exact
  # call shape.
  #
  # Convention: the locale subject lives at notification_mailer.<method>.subject
  # with any positional substitutions documented in the per-method signature.

  def workspace_role_changed
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace
    @role = @membership.role

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_role_changed.subject",
                 workspace: @workspace.name)
    )
  end

  def workspace_invitation_expiring_soon
    @notification = params[:notification]
    @recipient = params[:recipient]
    @invitation = params[:record]
    @workspace = @invitation.resolved_workspace
    @hours_remaining = @invitation.expires_in_hours
    @accept_url = accept_invitation_url(token: @invitation.token)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_invitation_expiring_soon.subject",
                 workspace: @workspace.name)
    )
  end

  def workspace_member_added
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace
    @role = @membership.role

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_member_added.subject",
                 workspace: @workspace.name)
    )
  end

  # Security alert: a sign-in arrived from a (user_agent, os) digest we haven't
  # seen for this user. The notification.params hash carries `:user_agent` and
  # `:os` from SignInFromNewDeviceNotifier.with(...).
  #
  # Per-recipient throttle (EmailRecipientThrottle): mirrors the pattern in
  # OmniauthCallbacksController#handle_existing_auth — even security-category
  # mail is gated by per-recipient flood protection so a coordinated attack
  # can't flood a single inbox by triggering many novel-device sign-ins. The
  # throttle is checked here (inside the mailer method) rather than at the
  # Notifier callsite because Noticed dispatches via deliver_later through its
  # own job pipeline, not directly through deliver_later from a controller.
  # The throttle fails open if Rails.cache.increment is unavailable, so a
  # cache outage doesn't suppress security alerts.
  def sign_in_from_new_device
    @notification = params[:notification]
    @recipient = params[:recipient]
    @user = params[:record]
    @os = @notification&.params&.dig(:os) || @notification&.params&.dig("os")
    @user_agent = @notification&.params&.dig(:user_agent) || @notification&.params&.dig("user_agent")
    @account_url = account_connected_accounts_url

    return unless EmailRecipientThrottle.allow!(@recipient.email_address, kind: :sign_in_from_new_device)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.sign_in_from_new_device.subject", os: @os)
    )
  end
end
