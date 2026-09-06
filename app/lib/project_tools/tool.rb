module ProjectTools
  # An available project tool. Immutable; identity is its key. `path_helper` is
  # the route-helper name the tab bar calls as `helper(workspace, project)`.
  Tool = Data.define(:key, :default_enabled, :implemented, :path_helper) do
    def implemented?      = implemented
    def default_enabled?  = default_enabled
    # Dynamic keys; spec/code_smells/project_tools_have_locale_keys_spec.rb is the gate.
    def name        = I18n.t("project_tools.#{key}.name")
    def description = I18n.t("project_tools.#{key}.description")
  end
end
