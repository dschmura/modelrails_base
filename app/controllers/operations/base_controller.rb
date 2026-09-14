module Operations
  # The operations area sits ABOVE the workspaces. Operators are Users who are
  # not (necessarily) members of anything, so this area never includes
  # WorkspaceScoped and never sets Current.workspace — the same posture as
  # Clientside::BaseController. Workspaces are reached only through
  # Current.user.operated_workspaces (the arc 2 seam), and everything inside a
  # workspace still hops the association.
  class BaseController < ApplicationController
    # An operator under the :none preset may have onboarded_at: nil; they must
    # reach the operations area rather than the onboarding wizard.
    skip_onboarding_requirement
    layout "operations"

    before_action :require_operator
    # Credential-grade area: force: true, same as passkey enrollment
    # (reauthenticatable.rb) — granting an operatorship mints a durable
    # credential and revokes nothing, so this gate must survive a fork
    # turning reauth_enabled off (config/initializers/sessions.rb).
    before_action -> { require_reauthentication!(force: true) }

    private

    # 404, not 403: don't confirm the area exists to non-operators.
    def require_operator
      head :not_found unless Current.user&.operator?
    end

    def operated_workspaces
      Current.user.operated_workspaces
    end
    helper_method :operated_workspaces
  end
end
