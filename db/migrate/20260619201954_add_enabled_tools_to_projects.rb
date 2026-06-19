class AddEnabledToolsToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :enabled_tools, :json, null: false, default: []

    # Backfill existing projects with the registry's default-enabled tools.
    Project.reset_column_information
    Project.update_all(enabled_tools: ProjectTools::Registry.default_keys)
  end

  def down
    remove_column :projects, :enabled_tools
  end
end
