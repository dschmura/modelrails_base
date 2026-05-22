class AddLastAccessedAtToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :last_accessed_at, :datetime
    add_index  :memberships, [ :user_id, :last_accessed_at ]
  end
end
