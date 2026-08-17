module Workspaces
  module Projects
    class ToolsController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped

      def edit
        authorize @project, :update?
        @tools = ProjectTools::Registry.toggleable
      end

      def update
        authorize @project, :update?

        allowed = ProjectTools::Registry.toggleable.map { |t| t.key.to_s }
        selected = Array(params.dig(:project, :enabled_tools)) & allowed
        @project.update!(enabled_tools: selected)

        redirect_to edit_workspace_project_tools_path(@workspace, @project),
          notice: t("project_tools.settings.saved")
      end
    end
  end
end
