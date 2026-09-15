module Operations
  class WorkspacesController < BaseController
    def index
      authorize [ :operations, Workspace ]
      # SQLite's default BINARY collation sorts uppercase before lowercase —
      # matches the sibling fix on Operations::UsersController#show.
      @pagy, @workspaces = pagy(:offset,
        operated_workspaces.includes(memberships: %i[role user]).order(Arel.sql("LOWER(workspaces.name)")))
    end

    def show
      @workspace = operated_workspaces.find_by!(slug: params[:slug])
      authorize [ :operations, @workspace ]
      # first_name/last_name are non-deterministically encrypted (user.rb's
      # `encrypts :pending_email, :first_name, :last_name` carries no
      # `deterministic: true`), so an SQL ORDER BY on either sorts
      # ciphertext, not names. Sort in Ruby on the decrypted values instead;
      # the eager loads below are unchanged, so this doesn't reintroduce a
      # query per row.
      @memberships = @workspace.memberships.kept.includes(:role, :user).to_a
        .sort_by { |m| [ m.user.last_name.to_s.downcase, m.user.first_name.to_s.downcase ] }
      @activities = @workspace.activity_logs.visible.recent.for_feed
    end

    def new
      authorize [ :operations, Workspace ]
      @workspace = Workspace.new
      @owner_email = ""
    end

    # Name plus an owner email. Existing user → they own it. Unknown email →
    # the operator owns it and the email gets a workspace invitation carrying
    # the Owner role through the ordinary invitation path; the operator hands
    # off later with the existing ownership-transfer or leave flows. "Invited
    # to nothing" is not a state this product has a page for.
    def create
      authorize [ :operations, Workspace ]
      @owner_email = params.dig(:workspace, :owner_email).to_s.strip
      @workspace = Workspace.new(create_params)
      @workspace.owner_email = @owner_email

      # Invitation.bulk_invite! does not raise on a malformed email — it
      # silently skips it (its own EMAIL_FORMAT check). Left unguarded, a
      # blank/invalid owner_email would quietly hand the new workspace to the
      # OPERATOR with no invitation and no error surfaced. Workspace itself
      # validates the format, attaching the error to the FIELD via the
      # owner_email attribute (not :base); checked here first only to skip
      # the owner lookup and transaction on input already known to be bad.
      return render :new, status: :unprocessable_entity if @workspace.invalid?

      owner = User.find_by(email_address: @owner_email)

      @workspace = Workspace.transaction do
        workspace = Workspace.create_owned(create_params, owner: owner || Current.user)
        if workspace.persisted? && owner.nil?
          Invitation.bulk_invite!(
            workspace: workspace, emails: [ @owner_email ],
            role: Role.system_default!("owner"), invited_by: Current.user
          )
        end
        workspace
      end

      if @workspace.persisted?
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def create_params
      params.require(:workspace).permit(:name)
    end
  end
end
