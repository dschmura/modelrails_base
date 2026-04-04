class AddPendingEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_email, :string
    add_column :users, :pending_email_token, :string
    add_column :users, :pending_email_sent_at, :datetime
    add_index :users, :pending_email_token, unique: true
  end
end
