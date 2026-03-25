module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    def index
      @memberships = @workspace.memberships.kept.includes(:user, :role)
    end
  end
end
