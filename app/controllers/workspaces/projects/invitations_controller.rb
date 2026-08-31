module Workspaces
  module Projects
    class InvitationsController < ApplicationController
      include InvitationSending
      include WorkspaceScoped
      include ProjectScoped

      def new
        authorize @project, :update?
        @invitation = Invitation.new
      end

      def create
        authorize @project, :update?
        viewer_role = Role.system_default!("viewer")

        @invitation = @project.invitations.build(
          email: invitation_params[:email],
          role: viewer_role,
          project_role: invitation_params[:project_role] || "editor",
          invited_by: Current.user,
          expires_at: 7.days.from_now
        )

        if Invitation.already_invited?(invitable: @project, email: invitation_params[:email],
                                       invited_by: Current.user)
          flash.now[:alert] = t(".already_invited")
          render :new, status: :unprocessable_entity
        elsif @invitation.save
          InvitationMailer.with(invitation: @invitation).invite.deliver_later
          redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".success")
        else
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        # Invitation carries no uniqueness *validation*, so a lost race reaches
        # the action as the raw index error — unrescued that was a 500, an
        # outcome the blocked path could never produce (invariant I3).
        flash.now[:alert] = t(".already_invited")
        render :new, status: :unprocessable_entity
      end

      private

      def invitation_params
        params.require(:invitation).permit(:email, :project_role)
      end
    end
  end
end
