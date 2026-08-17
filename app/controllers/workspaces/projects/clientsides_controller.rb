module Workspaces
  module Projects
    class ClientsidesController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped

      def edit
        authorize @project, :update?
      end

      def update
        authorize @project, :update?

        if @project.update(clientside_params)
          redirect_to edit_workspace_project_clientside_path(@workspace, @project),
            notice: t("clientside.settings.saved")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def clientside_params
        params.require(:project).permit(:clientside_enabled)
      end
    end
  end
end
