class CreateInvitationBlocksAndSuppression < ActiveRecord::Migration[8.1]
  def change
    create_table :invitation_blocks do |t|
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false # encrypted deterministic — declared on the model
      t.timestamps
    end
    add_index :invitation_blocks, [ :email, :inviter_id ], unique: true,
              name: "index_invitation_blocks_on_email_and_inviter"

    add_column :invitations, :suppressed_at, :datetime

    # Full original signature so `change` re-creates it on rollback (spec §4.2).
    remove_index :invitations, [ :email, :invitable_type, :invitable_id ],
                 unique: true, where: "status = 'pending'",
                 name: "index_invitations_on_email_and_invitable_pending"
    # One live (unsuppressed) pending invitation per (email, invitable) — any inviter.
    add_index :invitations, [ :email, :invitable_type, :invitable_id ], unique: true,
              where: "status = 'pending' AND suppressed_at IS NULL",
              name: "index_invitations_pending_live"
    # One ghost per (email, invitable, inviter) — caps ghosts without blocking other inviters.
    add_index :invitations, [ :email, :invitable_type, :invitable_id, :invited_by_id ], unique: true,
              where: "status = 'pending' AND suppressed_at IS NOT NULL",
              name: "index_invitations_pending_ghosts"
  end
end
