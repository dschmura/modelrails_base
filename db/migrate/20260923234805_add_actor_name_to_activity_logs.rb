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
  # COST, before you run this on a big table: `remove_foreign_key` is not a
  # metadata edit on SQLite. The adapter rebuilds the table -- CREATE new,
  # INSERT..SELECT, DROP, RENAME, and the indexes with it -- inside one
  # transaction holding the single writer lock. `activity_logs` is retained
  # twelve months and takes a row per tracked write, so it is the largest table
  # in a mature fork. Size it (`SELECT COUNT(*) FROM activity_logs`) and pick a
  # window; `add_column` below is free by comparison and is not the cost.
  #
  # Reversible in form, not always in practice: once any row's actor has been
  # deleted, a rollback re-adds the FK against a dangling actor_id and SQLite
  # refuses the rebuild -- without naming the constraint.
  def change
    add_column :activity_logs, :actor_name, :string

    remove_foreign_key :activity_logs, :users, column: :actor_id
  end
end
