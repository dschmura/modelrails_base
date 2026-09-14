module Operations
  class UsersController < BaseController
    def index
      authorize [ :operations, User ]
      # Exact email only: email_address is deterministically encrypted (#902)
      # so equality works through normalizes + find_by; names are encrypted
      # non-deterministically and cannot be searched. A browsable global list
      # is deliberately not offered — it is a data-export surface.
      @query = params[:q].to_s.strip
      @user = @query.present? ? User.find_by(email_address: @query) : nil
    end

    def show
      @user = User.find(params[:id])
      authorize [ :operations, @user ]
      @memberships = @user.memberships.kept.includes(:role, :workspace).order("workspaces.name")
    end
  end
end
