module Operations
  class WorkspacePolicy < BasePolicy
    def update?    = false
    def destroy?   = false
    def suspend?   = operator?
    def unsuspend? = operator?
  end
end
