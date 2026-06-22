class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :public_key, null: false
      t.integer :sign_count, null: false, default: 0
      t.string :nickname
      t.datetime :last_used_at
      t.datetime :verified_at
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :webauthn_credentials, :external_id, unique: true
  end
end
