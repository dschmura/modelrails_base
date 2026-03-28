class CreateMagicLinkTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :magic_link_tokens do |t|
      t.string :token, null: false
      t.string :email, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :magic_link_tokens, :token, unique: true
  end
end
