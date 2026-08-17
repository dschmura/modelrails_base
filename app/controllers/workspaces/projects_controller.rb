module Workspaces
  class ProjectsController < ApplicationController
    include WorkspaceScoped
    include ProjectScoped
    # Collection actions carry no project slug to resolve.
    skip_before_action :set_project, only: [ :index, :new, :create ]

    def index
      authorize Project
      @projects = @workspace.projects.kept.not_archived
      @archived_projects = @workspace.projects.kept.archived.order(:name)
    end

    def new
      authorize Project
      @project = @workspace.projects.build
    end

    def create
      authorize Project
      @project = @workspace.projects.build(project_params)
      @project.created_by = Current.user

      if @project.save
        @project.project_memberships.create!(user: Current.user, role: "creator")
        redirect_to workspace_project_path(@workspace, @project), notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @project
    end

    def edit
      authorize @project
    end

    def update
      authorize @project
      if @project.update(project_params)
        redirect_to workspace_project_path(@workspace, @project), notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @project
      @project.discard!
      redirect_to workspace_projects_path(@workspace), notice: t(".success")
    end

    def archive
      authorize @project
      @project.archive!
      redirect_to workspace_projects_path(@workspace), notice: t(".success")
    end

    def unarchive
      authorize @project
      @project.unarchive!
      redirect_to workspace_project_path(@workspace, @project), notice: t(".success")
    end

    private

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
