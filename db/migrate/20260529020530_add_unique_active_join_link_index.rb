class AddUniqueActiveJoinLinkIndex < ActiveRecord::Migration[8.1]
  # Enforce "exactly one active join link per workspace" at the database level.
  # JoinLinksController#create maintains this in application code (revoke-then-
  # create inside an IMMEDIATE transaction, which serializes concurrent rotates
  # on SQLite). A partial unique index makes the invariant adapter-agnostic and
  # immune to a future caller that creates a link without first revoking the
  # prior one. Only active rows (revoked_at IS NULL) participate, so any number
  # of revoked links may coexist as history.
  def change
    add_index :workspace_join_links, :workspace_id,
      unique: true,
      where: "revoked_at IS NULL",
      name: "index_workspace_join_links_unique_active_per_workspace"
  end
end
