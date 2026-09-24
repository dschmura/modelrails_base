class AddActorNameToActivityLogs < ActiveRecord::Migration[8.1]
  # An audit row keeps its actor's name even after the user row is gone, and
  # in exchange actor_id stops being a foreign key (#1122).
  #
  # Encrypted, because a name is the same PII on this table as it is on
  # `users` — and `activity_logs` is retained for twelve months, longer than
  # most of what it points at. Non-deterministic: nothing looks an actor up by
  # name here (the ledger's one SQL sort is on workspaces.name for exactly
  # this reason).
  #
  # Deliberately NOT backfilled. Existing rows keep a NULL snapshot and fall
  # back to the association while it resolves; an UPDATE across the table
  # would rewrite immutable audit history to add a field, which is the thing
  # ActivityLog#readonly? and the immutability guard exist to prevent.
  def change
    add_column :activity_logs, :actor_name, :string

    remove_foreign_key :activity_logs, :users, column: :actor_id
  end
end
