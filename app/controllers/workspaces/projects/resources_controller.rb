module Workspaces
  module Projects
    class ResourcesController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped
      include EnforcesProjectTool
      enforces_tool :docs
      before_action :set_resource, only: [ :show, :edit, :update, :destroy ]
      # The allowlist check is what makes the later constantize safe — declared
      # as a filter so an action can't forget it; it halts by redirecting.
      before_action :validate_resource_type, only: [ :new, :create ]

      def index
        authorize Resource
        @resources = @project.resources.kept.positioned.includes(:created_by)
      end

      def new
        authorize Resource
        @resource = @project.resources.build
        @resourceable = @type.constantize.new
      end

      def create
        authorize Resource

        ActiveRecord::Base.transaction do
          @resourceable = @type.constantize.create!(resourceable_params)
          @resource = @project.resources.create!(
            resource_params.merge(resourceable: @resourceable, created_by: Current.user)
          )
        end
        redirect_to workspace_project_resource_path(@workspace, @project, @resource), notice: t(".success")
      rescue ActiveRecord::RecordInvalid => e
        # Keep the INVALID record so the re-render shows its errors — the old
        # re-build produced an unvalidated copy with an empty errors set, so the
        # 422 rendered no message at all (the request spec asserted only status).
        if e.record.is_a?(Resource)
          @resource = e.record
        else
          # A failing RESOURCEABLE surfaces too (#747): keep it (the editor
          # retains what was typed) and merge its messages into the summary as
          # :base items — the old branch dropped them, so a validating
          # resourceable type re-rendered a 422 with an empty summary.
          @resourceable = e.record
          @resource = @project.resources.build(resource_params)
          e.record.errors.full_messages.each { |message| @resource.errors.add(:base, message) }
        end
        @resourceable ||= @type.constantize.new(resourceable_params)
        render :new, status: :unprocessable_entity
      end

      def show
        authorize @resource
      end

      def edit
        authorize @resource
        @resourceable = @resource.resourceable
      end

      def update
        authorize @resource
        ActiveRecord::Base.transaction do
          @resource.resourceable.update!(resourceable_params) if resourceable_params.present?
          @resource.update!(resource_params)
        end
        redirect_to workspace_project_resource_path(@workspace, @project, @resource), notice: t(".success")
      rescue ActiveRecord::RecordInvalid => e
        # The edit re-render's document partial binds @resourceable; without this
        # it rendered a blank editor on a failed update. Same resourceable-error
        # merge as create (#747).
        @resourceable = @resource.resourceable
        unless e.record.is_a?(Resource)
          e.record.errors.full_messages.each { |message| @resource.errors.add(:base, message) }
        end
        render :edit, status: :unprocessable_entity
      end

      def destroy
        authorize @resource
        @resource.discard!
        redirect_to workspace_project_resources_path(@workspace, @project), notice: t(".success")
      end

      private

      def set_resource
        @resource = @project.resources.kept.find(params[:id])
      end

      def validate_resource_type
        type = params.dig(:resource, :type) || params[:type] || "Document"
        unless Resource::ALLOWED_RESOURCEABLE_TYPES.include?(type)
          return redirect_to workspace_project_resources_path(@workspace, @project),
            alert: t("workspaces.projects.resources.invalid_type")
        end
        @type = type
      end

      def resource_params
        permitted = [ :title, :status ]
        permitted << :shared_with_client if @project&.clientside_enabled?
        params.require(:resource).permit(*permitted)
      end

      def resourceable_params
        case @type || @resource&.resourceable_type
        when "Document"
          params.fetch(:document, {}).permit(:body)
        else
          {}
        end
      end
    end
  end
end
