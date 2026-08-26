module Onboarding
  # Singular `resource :team` maps to a PLURAL controller name.
  class TeamsController < BaseController
    include InvitationSending
    before_action :require_workspace_with_project

    def new
      authorize Invitation
      @invitation = Invitation.new
      @roles = assignable_roles_for(Invitation)
    end

    def create
      authorize Invitation

      parsed = Invitation.parse_email_list(invitation_params[:emails])
      emails = parsed.emails

      # An unhandled cap here would silently drop teammates the founder typed
      # in during first-run, with nothing on screen to say so.
      if parsed.over_limit?
        flash.now[:alert] = t(".capped", cap: Invitation::MAX_EMAILS_PER_SUBMISSION)
        @invitation = Invitation.new
        @roles = assignable_roles_for(Invitation)
        render :new, status: :unprocessable_entity
        return
      end

      if emails.empty?
        flash.now[:alert] = t(".no_emails")
        @invitation = Invitation.new
        @roles = assignable_roles_for(Invitation)
        render :new, status: :unprocessable_entity
        return
      end

      role = Current.workspace.effective_roles.find(invitation_params[:role_id])
      authorize_role_grant!(Invitation, role)
      Invitation.bulk_invite!(workspace: Current.workspace, emails: emails, role: role, invited_by: Current.user)

      Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?
      redirect_to project_home_path, notice: t(".sent")
    end

    private

    def require_workspace_with_project
      redirect_to onboarding_path if Current.workspace.nil? || Current.workspace.projects.kept.none?
    end

    def project_home_path
      workspace_project_path(Current.workspace, Current.workspace.projects.kept.first)
    end

    def invitation_params
      params.require(:invitation).permit(:emails, :role_id)
    end
  end
end
