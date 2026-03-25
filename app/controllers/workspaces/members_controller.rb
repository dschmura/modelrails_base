module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    def index
      authorize Membership
      @memberships = @workspace.memberships.includes(:user, :role)
    end
  end
end
