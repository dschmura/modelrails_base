module Workspaces
  class ProjectsController < ApplicationController
    include WorkspaceScoped
    include ProjectScoped
    # Collection actions carry no project slug to resolve.
    skip_before_action :set_project, only: [ :index, :new, :create ]

    def index
      authorize Project
      # Not with_attached_logo: that scope eager-loads the variant tree
      # (variant_records, preview_image_attachment), and project logos render
      # the original blob without variants (#691) — Bullet flags the unused
      # includes. Switch back to with_attached_logo when #691 adds variants.
      @projects = policy_scope(@workspace.projects).kept.not_archived.includes(logo_attachment: :blob)
      @archived_projects = policy_scope(@workspace.projects).kept.archived.order(:name)
    end

    def new
      authorize Project
      @project = @workspace.projects.build
    end

    def create
      authorize Project
      @project = @workspace.create_project(project_params, creator: Current.user)

      if @project.persisted?
        redirect_to workspace_project_path(@workspace, @project), notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @project
      @activities = ActivityLog.for_project(@project).recent.includes(:actor)
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
