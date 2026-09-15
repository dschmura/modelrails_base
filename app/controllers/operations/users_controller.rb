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
      # deferred until reach becomes a real subset (scoped operators), where
      # enumeration would actually cross a boundary.
      @query = params[:q].to_s.strip
      @user = @query.present? ? User.find_by(email_address: @query) : nil
    end

    def show
      @user = User.find(params[:id])
      authorize [ :operations, @user ]
      # SQLite's BINARY collation sorts uppercase before lowercase; LOWER()
      # matches the sibling workspace-member sort's case-insensitive intent.
      # workspaces.name is a plain column, so unlike User#first_name/
      # #last_name it can be sorted in SQL.
      #
      # `references(:workspace)` must be explicit: Rails only auto-detects a
      # raw order string's table from a bare `table.column` shape, and
      # `LOWER(workspaces.name)` doesn't match that shape (plain String or
      # Arel.sql alike) — so without it, `includes` preloads instead of
      # joining and the ORDER BY hits an unjoined table.
      @memberships = @user.memberships.kept.includes(:role, :workspace).references(:workspace)
        .order(Arel.sql("LOWER(workspaces.name)"))
    end
  end
end
