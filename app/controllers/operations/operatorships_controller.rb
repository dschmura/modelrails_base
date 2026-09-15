module Operations
  class OperatorshipsController < BaseController
    def index
      authorize [ :operations, Operatorship ]
      @operatorships = Operatorship.kept.includes(:user, :granted_by).order(:created_at)
    end

    def create
      authorize [ :operations, Operatorship ]
      user = User.find_by(email_address: params[:email].to_s.strip)
      if user.nil?
        redirect_to operations_operatorships_path, alert: t(".not_found")
      elsif user.operator?
        redirect_to operations_operatorships_path, notice: t(".already")
      else
        # Rescued inline, not with a model uniqueness validation (C1, carried
        # from Task 1/R13): the partial unique index is the real guarantee
        # under concurrency, and a double submit racing the operator? check
        # above is the only way to reach it — the ordinary sequential path
        # never does. Kept inside #create (not a private helper) so the
        # lazy t(".key") lookups below still scope to this action.
        begin
          Operatorship.grant!(user: user, granted_by: Current.user)
          redirect_to operations_operatorships_path, notice: t(".success")
        rescue ActiveRecord::RecordNotUnique
          redirect_to operations_operatorships_path, notice: t(".already")
        end
      end
    end

    # The last kept operatorship cannot be revoked from the panel — that would
    # lock everyone out of the area. `rails operators:revoke` still can
    # (break-glass): the guard lives here, not in Operatorship#revoke!, so the
    # rake task keeps its documented ability to remove the last one.
    def destroy
      operatorship = Operatorship.kept.find(params[:id])
      authorize [ :operations, operatorship ]
      if Operatorship.kept.count <= 1
        redirect_to operations_operatorships_path, alert: t(".last_operator")
      else
        operatorship.revoke!(revoked_by: Current.user)
        redirect_to operations_operatorships_path, notice: t(".success")
      end
    end
  end
end
