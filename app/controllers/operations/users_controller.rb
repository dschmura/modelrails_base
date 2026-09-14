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
      # SQLite's BINARY collation sorts uppercase before lowercase; LOWER()
      # matches the sibling workspace-member sort's case-insensitive intent
      # (fix round 2, item 8). workspaces.name is a plain column — unlike
      # User#first_name/#last_name, this can be sorted in SQL (R21).
      # `references(:workspace)` is required here: unlike a plain String,
      # Arel.sql isn't scanned for table references, so `includes` would
      # preload instead of join and the ORDER BY would hit an unjoined table.
      @memberships = @user.memberships.kept.includes(:role, :workspace).references(:workspace)
        .order(Arel.sql("LOWER(workspaces.name)"))
    end
  end
end
