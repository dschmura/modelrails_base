module Operations
  module Workspaces
    class SuspensionsController < BaseController
      before_action :set_workspace

      def create
        authorize [ :operations, @workspace ], :suspend?
        # Early redirect on a repeat POST (fix round 1, item 3): calling
        # suspend! unconditionally bumped suspended_at to a fresh timestamp
        # and wrote a second workspace.updated row that rendered as a second
        # "locked" entry in the tenant's feed. The workspace genuinely IS
        # locked either way, so the same success notice still holds.
        return redirect_to operations_workspace_path(@workspace), notice: t(".success") if @workspace.suspended?

        @workspace.suspend!
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      end

      def destroy
        authorize [ :operations, @workspace ], :unsuspend?
        # Early redirect with NO success flash when it is not suspended (fix
        # round 1, item 4): unsuspend! unconditionally wrote zero-change
        # rows and flashed "Workspace unlocked." for an action that never
        # happened — unlike item 3, nothing here is true to report.
        return redirect_to operations_workspace_path(@workspace) unless @workspace.suspended?

        @workspace.unsuspend!
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      end

      private

      def set_workspace
        @workspace = operated_workspaces.find_by!(slug: params[:workspace_slug])
      end
    end
  end
end
