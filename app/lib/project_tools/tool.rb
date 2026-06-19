module ProjectTools
  # An available project tool. Immutable; identity is its key. `path_helper` is
  # the route-helper name the tab bar calls as `helper(workspace, project)`.
  Tool = Data.define(:key, :default_enabled, :implemented, :path_helper) do
    def implemented?      = implemented
    def default_enabled?  = default_enabled
    def name        = I18n.t("project_tools.#{key}.name", default: key.to_s.humanize)
    def description = I18n.t("project_tools.#{key}.description", default: "")
  end
end
