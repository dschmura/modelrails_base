# Project tools registry — the fork extension seam.
#
# Register a tool here AFTER you've built its surface (model + controller +
# routes + views). `path_helper` is a project-scoped route helper the project
# tab bar calls as `helper(workspace, project)`.
#
#   ProjectTools::Registry.register(
#     key: :messages,
#     path_helper: :workspace_project_messages_path,
#     default_enabled: true
#   )
#
# See app/docs/project-tools.md. The base template ships only :docs.
Rails.application.config.to_prepare do
  ProjectTools::Registry.reset!

  ProjectTools::Registry.register(
    key: :docs,
    path_helper: :workspace_project_resources_path,
    default_enabled: true
  )
end
