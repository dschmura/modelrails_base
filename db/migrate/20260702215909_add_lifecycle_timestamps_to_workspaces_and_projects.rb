class AddLifecycleTimestampsToWorkspacesAndProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :archived_at, :datetime
    add_index  :workspaces, :archived_at
    add_column :workspaces, :suspended_at, :datetime
    add_index  :workspaces, :suspended_at
    add_column :projects, :archived_at, :datetime
    add_index  :projects, :archived_at
  end
end
