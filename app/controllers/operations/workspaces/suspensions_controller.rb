module Operations
  module Workspaces
    class SuspensionsController < BaseController
      before_action :set_workspace

      def create
        authorize [ :operations, @workspace ], :suspend?
        # Report the resulting state, not the transition: an already-suspended
        # workspace returns early so a repeat submit doesn't bump suspended_at
        # or write a second "locked" activity row. The notice still holds —
        # the workspace IS locked, which is what it says.
        return redirect_to operations_workspace_path(@workspace), notice: t(".success") if @workspace.suspended?

        @workspace.suspend!
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      end

      def destroy
        authorize [ :operations, @workspace ], :unsuspend?
        # An already-unlocked workspace returns early: unsuspend! would be a
        # true no-op (no activity row, no updated_at change) except that
        # Broadcastable's after_update_commit still fires on a no-op save,
        # pushing a spurious Turbo refresh to every connected tenant member.
        return redirect_to operations_workspace_path(@workspace), notice: t(".success") unless @workspace.suspended?

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
