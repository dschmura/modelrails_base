# Redirects a project-tool's routes back to the project home when that tool is
# disabled for the project. Include AFTER the before_action that sets @project,
# so @project is resolved before the guard runs. Declare the tool with
# `enforces_tool :key`.
module EnforcesProjectTool
  extend ActiveSupport::Concern

  included do
    before_action :enforce_project_tool_enabled
  end

  class_methods do
    def enforces_tool(key)
      @enforced_tool_key = key
    end

    def enforced_tool_key
      @enforced_tool_key
    end
  end

  private

  def enforce_project_tool_enabled
    key = self.class.enforced_tool_key
    return if key.nil? || @project.nil?
    return if @project.tool_enabled?(key)

    redirect_to workspace_project_path(@workspace, @project),
      alert: t("project_tools.disabled")
  end
end
