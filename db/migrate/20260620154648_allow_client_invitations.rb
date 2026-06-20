class AllowClientInvitations < ActiveRecord::Migration[8.1]
  def up
    add_column :invitations, :company_name, :string
    change_column_null :invitations, :role_id, true
  end

  def down
    change_column_null :invitations, :role_id, false
    remove_column :invitations, :company_name
  end
end
