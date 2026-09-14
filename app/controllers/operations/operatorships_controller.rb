module Operations
  class OperatorshipsController < BaseController
    def index
      authorize [ :operations, Operatorship ]
      @operatorships = Operatorship.kept.includes(:user, :granted_by).order(:created_at)
    end
  end
end
