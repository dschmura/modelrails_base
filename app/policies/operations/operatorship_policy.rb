module Operations
  class OperatorshipPolicy < BasePolicy
    def show?    = false
    def update?  = false
    # create?/destroy? are the verbs Task 14 made live; stated explicitly for
    # the same reason as Operations::WorkspacePolicy (fix round 1, item 8) —
    # even though they only repeat BasePolicy's inherited `operator?` answer,
    # leaving live verbs implicit reads as an oversight rather than a decision.
    def create?  = operator?
    def destroy? = operator?
  end
end
