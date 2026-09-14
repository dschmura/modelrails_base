module Operations
  module Workspaces
    class SuspensionsController < BaseController
      before_action :set_workspace

      def create
        authorize [ :operations, @workspace ], :suspend?
        # Both halves of this toggle report the RESULTING STATE, not the
        # transition (fix round 1, items 3 and 4): calling suspend!
        # unconditionally bumped suspended_at and wrote a second "locked" row
        # into the tenant's feed on a repeat submit. The notice still holds on
        # the early return — the workspace is locked, which is what it says.
        return redirect_to operations_workspace_path(@workspace), notice: t(".success") if @workspace.suspended?

        @workspace.suspend!
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      end

      def destroy
        authorize [ :operations, @workspace ], :unsuspend?
        # Mirror of #create's early return — see the note there.
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
