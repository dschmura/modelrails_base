class AddLastKnownBrowsersToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_known_browsers, :json, default: [], null: false
  end
end
