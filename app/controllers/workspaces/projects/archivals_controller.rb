module Workspaces
  module Projects
    # Archived is a state the project is in, so it is a singular resource:
    # create archives, destroy restores. Same shape as Workspaces::ArchivalsController.
    class ArchivalsController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped

      def create
        authorize @project, :archive?
        @project.archive!
        redirect_to workspace_projects_path(@workspace), notice: t(".success")
      end

      def destroy
        authorize @project, :unarchive?
        @project.unarchive!
        redirect_to workspace_project_path(@workspace, @project), notice: t(".success")
      end
    end
  end
end
