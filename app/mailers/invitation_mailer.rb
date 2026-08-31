class InvitationMailer < ApplicationMailer
  before_action :abort_unless_deliverable

  def invite
    invitation = params[:invitation]
    @invitation = invitation
    @inviter = invitation.invited_by
    @role = invitation.role

    if invitation.invitable_type == "Project"
      @project = invitation.invitable
      @workspace = @project.workspace
    else
      @workspace = invitation.invitable
    end

    @accept_url = accept_invitation_url(token: invitation.token)
    @decline_url = decline_invitation_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: t("invitation_mailer.invite.subject", app_name: t("application.name"))
    )
  end

  def invite_client
    invitation = params[:invitation]
    @invitation = invitation
    @inviter = invitation.invited_by
    @project = invitation.invitable
    @workspace = @project.workspace
    @accept_url = accept_invitation_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: t("invitation_mailer.invite_client.subject", app_name: t("application.name"))
    )
  end

  private

  # Halting the chain leaves a NullMail — deliver is a no-op; the mechanism the
  # deleted nil-email returns relied on. Covers every method here, including a
  # fork's (PR 4 spec §8.2).
  #
  # DEVIATION from spec §8.2's literal `throw :abort`: verified against Rails
  # 8.1.3.1 (isolated ActiveSupport::Callbacks repro, a bare ActionMailer::Base
  # subclass, and a fully Rack-dispatched ActionController::Base subclass) that
  # a `before_action`'s `throw :abort` raises UncaughtThrowError rather than
  # halting. `catch(:abort)` only wraps ActiveSupport::Callbacks::DEFAULT_TERMINATOR
  # (the ActiveModel/ActiveRecord callback convention, and — confirmed via
  # Rails' own actionmailer/test/callbacks_test.rb — ActionMailer's separate
  # `before_deliver`/`around_deliver` chain); `before_action` reuses
  # AbstractController::Callbacks' `process_action` terminator, which checks
  # `performed?` instead and never catches the throw. Setting `response_body`
  # is that terminator's real halt signal — the same one `render`/`head` use to
  # stop a controller `before_action`. The action method still never runs, so
  # `@_mail_was_called` stays false and `ActionMailer::Base#process` still
  # substitutes NullMail, preserving §8.2's intent (skip building the message,
  # not just skip delivering it — `before_deliver` would build it first).
  def abort_unless_deliverable
    invitation = params[:invitation]
    return if invitation.deliverable?
    # Magic link: nothing to deliver — not a suppression; no stamp, no row.
    invitation.suppress_delivery!(mailer_action: action_name) if invitation.has_invitee?
    self.response_body = ""
  end
end
