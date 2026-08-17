# Redirects a project-tool's routes back to the project home when that tool is
# disabled for the project. Declare the tool with `enforces_tool :key` after
# the include that resolves @project (ProjectScoped) — the declaration itself
# registers the guard callback, so it runs in declaration order.
module EnforcesProjectTool
  extend ActiveSupport::Concern

  included do
    class_attribute :enforced_tool_key, instance_writer: false, default: nil
  end

  class_methods do
    def enforces_tool(key)
      self.enforced_tool_key = key
      before_action :enforce_project_tool_enabled
    end
  end

  private

  def enforce_project_tool_enabled
    key = enforced_tool_key
    return if key.nil? || @project.nil?
    return if @project.tool_enabled?(key)

    redirect_to workspace_project_path(@workspace, @project),
      alert: t("project_tools.disabled")
  end
end
