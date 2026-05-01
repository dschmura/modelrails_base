# frozen_string_literal: true

class NotificationPreferences
  CATEGORIES = %w[security account_access workspace_activity project_activity billing].freeze
  CHANNELS   = %w[in_app email digest].freeze
  SECURITY_CATEGORY = "security"
  DIGEST_ELIGIBLE_CATEGORIES = %w[workspace_activity project_activity].freeze
  # Used by NotificationCleanupJob (PR-5) to enforce a 1-year retention floor
  # on security-class notifications regardless of user retention preference.
  RETENTION_FLOORS = { "security" => 365.days }.freeze
  # Class names of Notifiers in the security category. Consumed by the cleanup
  # job to identify which noticed_notifications rows fall under the floor.
  # @see app/jobs/notification_cleanup_job.rb (added in PR-5).
  SECURITY_NOTIFIER_TYPES = %w[SignInFromNewDeviceNotifier PasswordChangedNotifier].freeze

  def initialize(jsonb_hash)
    @data = jsonb_hash || {}
  end

  def allow?(category:, channel:)
    return false unless CATEGORIES.include?(category) && CHANNELS.include?(channel)
    return true if category == SECURITY_CATEGORY  # security bypasses DND
    return false if do_not_disturb?
    @data.dig("categories", category, channel) == true
  end

  def do_not_disturb?
    @data["do_not_disturb"] == true
  end

  def digest_enabled?
    @data.dig("digest", "enabled") != false
  end

  def digest_cadence
    @data.dig("digest", "cadence") || "daily"
  end

  def digest_hour_local
    @data.dig("digest", "hour_local") || 8
  end

  # Returns nil when key is absent or explicitly nil ("never auto-delete").
  # The default 90 lives in the JSONB column default in the migration
  # (db/migrate/<ts>_add_notification_preferences_to_user_preferences.rb),
  # not in this method — keeps the "never" semantics representable.
  def retention_days
    @data["retention_days"]
  end

  def next_due_at_in(timezone)
    now = Time.current.in_time_zone(timezone)
    next_local = timezone.local(now.year, now.month, now.day, digest_hour_local)
    next_local += 1.day if next_local <= now
    next_local += 6.days if digest_cadence == "weekly"
    next_local
  end

  def to_h = @data.deep_dup
end
