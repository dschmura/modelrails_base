module Operations
  class UserPolicy < BasePolicy
    def create?  = false
    def update?  = false
    def destroy? = false
    def unlock?  = operator?
    def suspend? = operator?
  end
end
