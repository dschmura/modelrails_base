module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      # Remove logo (from identity picker or form)
      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        @workspace.logo_original.purge if @workspace.logo_original.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Handle logo attachments (from identity picker crop flow)
      if params[:logo].present?
        @workspace.logo.attach(params[:logo])
      end

      if params[:logo_original].present?
        @workspace.logo_original.attach(params[:logo_original])
      end

      # Store crop coordinates
      if params[:crop_coordinates].present? && @workspace.logo_original.attached?
        coords = JSON.parse(params[:crop_coordinates])
        blob = @workspace.logo_original.blob
        blob.update!(metadata: blob.metadata.merge("crop" => coords))
      end

      # Handle nested form params (branding form)
      if params.dig(:workspace, :logo).present?
        @workspace.logo.attach(params[:workspace][:logo])
      end

      if @workspace.update(branding_params)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_workspace_branding_path(@workspace), notice: t(".success") }
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    rescue ActionController::ParameterMissing
      {}
    end
  end
end
