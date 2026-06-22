class CreateWebauthnChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_challenges do |t|
      t.string :challenge, null: false
      t.string :purpose, null: false
      t.references :user, null: true, foreign_key: true
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :webauthn_challenges, :challenge, unique: true
  end
end
