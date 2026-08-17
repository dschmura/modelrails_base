module Workspaces
  module Projects
    class ClientInvitationsController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped
      before_action :ensure_clientside_enabled

      def new
        authorize Invitation
        @invitation = Invitation.new
      end

      def create
        authorize Invitation
        Invitation.invite_client!(
          project: @project,
          email: client_invitation_params[:email],
          company_name: client_invitation_params[:company_name],
          invited_by: Current.user
        )
        redirect_to edit_workspace_project_clientside_path(@workspace, @project),
          notice: t("clientside.invitations.sent")
      rescue ActiveRecord::RecordInvalid
        @invitation = Invitation.new(client_invitation_params)
        flash.now[:alert] = t("clientside.invitations.invalid")
        render :new, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique
        @invitation = Invitation.new(client_invitation_params)
        flash.now[:alert] = t("clientside.invitations.already_invited")
        render :new, status: :unprocessable_entity
      end

      private

      def ensure_clientside_enabled
        return if @project.clientside_enabled?
        redirect_to edit_workspace_project_clientside_path(@workspace, @project),
          alert: t("clientside.invitations.disabled")
      end

      def client_invitation_params
        params.require(:client_invitation).permit(:email, :company_name)
      end
    end
  end
end
