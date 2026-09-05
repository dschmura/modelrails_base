module Workspaces
  module Projects
    module Resources
      # A resource's place in the project's ordering; clamped to the kept range.
      class PositionsController < ApplicationController
        include WorkspaceScoped
        include ProjectScoped
        include EnforcesProjectTool
        enforces_tool :docs

        def update
          resource = @project.resources.kept.find(params[:resource_id])
          authorize resource, :reposition?
          max_position = @project.resources.kept.count - 1
          new_position = params[:resource][:position].to_i.clamp(0, [ max_position, 0 ].max)
          resource.update!(position: new_position)
          head :ok
        end
      end
    end
  end
end
