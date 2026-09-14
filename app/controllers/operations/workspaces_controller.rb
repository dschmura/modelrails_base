module Operations
  class WorkspacesController < BaseController
    def index
      authorize [ :operations, Workspace ]
      @pagy, @workspaces = pagy(:offset,
        operated_workspaces.includes(memberships: %i[role user]).order(:name))
    end
  end
end
