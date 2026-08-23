module Onboarding
  class WorkspacesController < BaseController
    def new
      authorize Workspace
      @workspace = Workspace.new
    end

    def create
      authorize Workspace
      @workspace = Workspace.create_owned(workspace_params, owner: Current.user)

      if @workspace.persisted?
        redirect_to new_onboarding_project_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def workspace_params
      params.require(:workspace).permit(:name)
    end
  end
end
