class AddPendingInvitationTokenToAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :authentications, :pending_invitation_token, :string

    # Partial index keeps the index small — only the rare authentications
    # carrying a pending invitation get indexed. Used by
    # Authentication#claim_pending_invitation!.
    add_index :authentications, :pending_invitation_token,
              where: "pending_invitation_token IS NOT NULL"
  end
end
