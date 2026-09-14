module Operations
  class UsersController < BaseController
    def index
      authorize [ :operations, User ]
      # Exact email only: email_address is deterministically encrypted (#902)
      # so equality works through normalizes + find_by; names are encrypted
      # non-deterministically and cannot be searched. Search-only index is a
      # UI choice, not the trust boundary: it avoids a one-click enumeration
      # of every user, but `show` still resolves any id, and an operator's
      # reach already spans every workspace. A non-sequential identifier is
      # deferred to the scoped-operator arc, where reach becomes a real
      # subset and enumeration would cross it (ruling, fix round 1).
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
