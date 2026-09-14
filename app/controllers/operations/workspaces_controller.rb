module Operations
  class WorkspacesController < BaseController
    def index
      authorize [ :operations, Workspace ]
      @pagy, @workspaces = pagy(:offset,
        operated_workspaces.includes(memberships: %i[role user]).order(:name))
    end

    def show
      @workspace = operated_workspaces.find_by!(slug: params[:slug])
      authorize [ :operations, @workspace ]
      # first_name/last_name are non-deterministically encrypted (user.rb's
      # `encrypts :pending_email, :first_name, :last_name` carries no
      # `deterministic: true`), so an SQL ORDER BY on either sorts ciphertext,
      # not names (fix round 2, finding 7 — a prior instruction to sort in SQL
      # was wrong). Sort in Ruby on the decrypted values instead; the eager
      # loads below are unchanged, so this doesn't reintroduce a query per row.
      @memberships = @workspace.memberships.kept.includes(:role, :user).to_a
        .sort_by { |m| [ m.user.last_name.to_s.downcase, m.user.first_name.to_s.downcase ] }
      @activities = @workspace.activity_logs.visible.recent.for_feed
    end
  end
end
