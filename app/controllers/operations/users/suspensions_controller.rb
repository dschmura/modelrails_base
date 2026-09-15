module Operations
  module Users
    class SuspensionsController < BaseController
      def create
        user = User.find(params[:user_id])
        authorize [ :operations, user ], :suspend?
        user.suspend_access!
        redirect_to operations_user_path(user), notice: t(".success")
      end
    end
  end
end
