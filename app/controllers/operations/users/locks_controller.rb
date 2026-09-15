module Operations
  module Users
    class LocksController < BaseController
      def destroy
        user = User.find(params[:user_id])
        authorize [ :operations, user ], :unlock?
        user.unlock!
        redirect_to operations_user_path(user), notice: t(".success")
      end
    end
  end
end
