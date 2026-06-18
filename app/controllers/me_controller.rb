class MeController < ApplicationController
  # Identity home — the signed-in user's own launchpad. Self-scoped (you only
  # ever see your own /me), so there is no Pundit authorize call: the page reads
  # Current.user and the workspaces they belong to. Per the project's Pundit
  # opt-in posture, a self-scoped resource needs no policy.
  def show
    @memberships = Current.user.memberships.kept.includes(:workspace, :role)
  end
end
