module Workspaces
  class SettingsController < ApplicationController
    include WorkspaceScoped
    before_action :require_owner_or_admin

    def edit
    end

    def update
      if @workspace.update(settings_params)
        redirect_to edit_workspace_settings_path(@workspace), notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:workspace).permit(:max_members, :max_teams)
    end

    def require_owner_or_admin
      membership = @workspace.memberships.kept.find_by(user: Current.user)
      unless membership&.role&.slug&.in?(%w[owner admin])
        redirect_to workspace_path(@workspace), alert: t("workspaces.unauthorized")
      end
    end
  end
end
