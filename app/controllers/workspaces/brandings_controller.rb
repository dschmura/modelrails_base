module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      # Remove logo (modal remove button)
      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Logo upload from the modal (top-level param)
      logo_file = params[:logo]

      if logo_file.present?
        @workspace.logo.attach(logo_file)
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Full branding form (nested under workspace)
      if params.key?(:workspace)
        @workspace.logo.attach(params[:workspace][:logo]) if params.dig(:workspace, :logo).present?

        if @workspace.update(branding_params)
          redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        else
          render :edit, status: :unprocessable_entity
        end
      else
        redirect_to edit_workspace_branding_path(@workspace)
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    end
  end
end
