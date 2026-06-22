class AddWebauthnHandleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :webauthn_handle, :string
    add_index :users, :webauthn_handle, unique: true
  end
end
