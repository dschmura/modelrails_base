module Workspaces
  module Projects
    class MembershipsController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped

      def index
        authorize ProjectMembership
        @memberships = @project.project_memberships.includes(:user)
      end

      def new
        authorize ProjectMembership
        @available_members = @workspace.memberships.kept.includes(:user)
          .where.not(user_id: @project.project_memberships.select(:user_id))
      end

      def create
        authorize ProjectMembership
        @pm = @project.project_memberships.build(membership_params)

        if @pm.save
          redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".success")
        else
          @available_members = @workspace.memberships.kept.includes(:user)
            .where.not(user_id: @project.project_memberships.select(:user_id))
          render :new, status: :unprocessable_entity
        end
      end

      def update
        @pm = @project.project_memberships.find(params[:id])
        authorize @pm
        role = params[:project_membership][:role]
        # Guard the enum value up front — the enum setter raises a bare
        # ArgumentError, which is too broad a thing to rescue honestly.
        unless ProjectMembership.roles.key?(role)
          return redirect_to workspace_project_memberships_path(@workspace, @project),
            alert: t("workspaces.projects.memberships.update.invalid_role")
        end

        @pm.update!(role: role)
        redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".role_updated")
      end

      def destroy
        @pm = @project.project_memberships.find(params[:id])
        authorize @pm
        @pm.destroy!
        redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".removed")
      end

      private

      def membership_params
        params.require(:project_membership).permit(:user_id, :role)
      end
    end
  end
end
