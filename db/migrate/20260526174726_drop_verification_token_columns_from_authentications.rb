class DropVerificationTokenColumnsFromAuthentications < ActiveRecord::Migration[8.1]
  # Email verification now uses signed, stateless tokens (Authentication's
  # generates_token_for :email_verification), so the stored token and its
  # "sent at" bookkeeping — plus the unique index that backed collision
  # retries — are no longer used. Explicit up/down keeps it reversible.
  def up
    remove_index :authentications, :verification_token,
      unique: true, name: "index_authentications_on_verification_token", if_exists: true
    remove_column :authentications, :verification_token, :string
    remove_column :authentications, :verification_sent_at, :datetime
  end

  def down
    add_column :authentications, :verification_sent_at, :datetime
    add_column :authentications, :verification_token, :string
    add_index :authentications, :verification_token,
      unique: true, name: "index_authentications_on_verification_token"
  end
end
