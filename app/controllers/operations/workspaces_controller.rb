module Operations
  class WorkspacesController < BaseController
    def index
      authorize [ :operations, Workspace ]
      @pagy, @workspaces = pagy(:offset,
        operated_workspaces.includes(memberships: %i[role user]).order(:name))
    end

    def show
      @workspace = operated_workspaces.find_by!(slug: params[:slug])
      authorize [ :operations, @workspace ]
      @memberships = @workspace.memberships.kept.includes(:role, :user).order("users.id")
      @activities = @workspace.activity_logs.visible.recent.for_feed
    end
  end
end
