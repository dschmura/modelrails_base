class AddActiveDaysToQuietHoursDefault < ActiveRecord::Migration[8.1]
  # Adds `active_days` to the user_preferences.notification_preferences JSONB
  # column default. The value object (NotificationPreferences#quiet_hours_active?)
  # treats a missing `active_days` key as all-7-days for backward compat, so
  # existing rows continue working without an in-place data update. New rows
  # get the explicit all-7-days list from this default.
  #
  # No data backfill: existing users' rows acquire `active_days` only when
  # they next submit a quiet_hours change through the preferences page (the
  # controller's deep_merge handles partial updates). Until then, the value
  # object's fallback covers them.
  NEW_DEFAULT_JSONB = {
    "notification_types" => {
      "security" => true,
      "account_access" => true,
      "workspace_activity" => true,
      "project_activity" => true,
      "billing" => true
    },
    "delivery_methods" => {
      "in_app" => { "enabled" => true },
      "email"  => { "enabled" => true, "frequency" => "instant" }
    },
    "quiet_hours" => {
      "enabled" => false,
      "start" => "22:00",
      "end" => "07:00",
      "allow_urgent" => true,
      "active_days" => %w[monday tuesday wednesday thursday friday saturday sunday]
    },
    "retention_days" => 90
  }.freeze

  PREVIOUS_DEFAULT_JSONB = {
    "notification_types" => {
      "security" => true,
      "account_access" => true,
      "workspace_activity" => true,
      "project_activity" => true,
      "billing" => true
    },
    "delivery_methods" => {
      "in_app" => { "enabled" => true },
      "email"  => { "enabled" => true, "frequency" => "instant" }
    },
    "quiet_hours" => {
      "enabled" => false,
      "start" => "22:00",
      "end" => "07:00",
      "allow_urgent" => true
    },
    "retention_days" => 90
  }.freeze

  def up
    change_column_default :user_preferences, :notification_preferences, NEW_DEFAULT_JSONB
  end

  def down
    change_column_default :user_preferences, :notification_preferences, PREVIOUS_DEFAULT_JSONB
  end
end
