class AddPasskeyPromptSeenAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :passkey_prompt_seen_at, :datetime
  end
end
