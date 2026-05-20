class AddPersonalWorkspaceIdToUsers < ActiveRecord::Migration[8.1]
  # Denormalizes the personal workspace pointer onto users so a database-level
  # UNIQUE constraint can enforce "at most one personal workspace per user".
  # Without this, the after_create callback that builds the personal workspace
  # could (under unusual conditions like manual reinvocation or skipped
  # validations) create duplicate personal workspaces with no schema-level
  # guard. The spec's data-model section explicitly promised this constraint
  # in Phase 1 — it was missed; landing it now closes the gap.

  def up
    add_reference :users, :personal_workspace,
                  foreign_key: { to_table: :workspaces, on_delete: :nullify },
                  null: true

    # Unique partial index: ignore NULL so users without a personal workspace
    # yet (the brief window between user insert and after_create callback)
    # don't collide with each other.
    add_index :users, :personal_workspace_id,
              unique: true,
              where: "personal_workspace_id IS NOT NULL",
              name: "index_users_on_personal_workspace_id_unique"

    # Backfill: each existing user's owner Membership on a personal workspace
    # points us to that user's personal_workspace_id.
    execute <<~SQL
      UPDATE users
      SET personal_workspace_id = (
        SELECT workspaces.id
        FROM workspaces
        INNER JOIN memberships ON memberships.workspace_id = workspaces.id
        INNER JOIN roles ON roles.id = memberships.role_id
        WHERE workspaces.personal = 1
          AND workspaces.discarded_at IS NULL
          AND memberships.user_id = users.id
          AND memberships.discarded_at IS NULL
          AND roles.slug = 'owner'
        LIMIT 1
      )
      WHERE personal_workspace_id IS NULL
    SQL
  end

  def down
    remove_index :users, name: "index_users_on_personal_workspace_id_unique"
    remove_reference :users, :personal_workspace, foreign_key: { to_table: :workspaces }
  end
end
