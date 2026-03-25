module WorkspaceScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_workspace
  end

  private

  def set_workspace
    slug = params[:workspace_slug] || params[:slug]
    @workspace = Current.user.workspaces.kept.find_by!(slug: slug)
    Current.workspace = @workspace
    session[:current_workspace_id] = @workspace.id
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: t("workspaces.not_found")
  end
end
