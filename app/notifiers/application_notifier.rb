# frozen_string_literal: true

class ApplicationNotifier < Noticed::Event
  class_attribute :category_name, instance_writer: false

  def self.category(name)
    self.category_name = name.to_s
  end

  before_create :populate_idempotency_key

  notification_methods do
    def recipient_pref(channel)
      preferences_object.allow?(category: event.class.category_name, channel: channel.to_s)
    end

    def recipient_locale
      recipient.try(:preferences)&.locale.presence&.to_sym || I18n.default_locale
    end

    def mark_seen!
      return if seen_at.present?
      update_columns(seen_at: Time.current, updated_at: Time.current)
    end

    def render_safe_or_placeholder
      yield
    rescue ActiveRecord::RecordNotFound
      Rails.logger.info("Notification ##{id} references deleted record; rendering placeholder")
      I18n.t("notifications.placeholder")
    rescue NoMethodError => e
      raise unless e.receiver.nil?
      Rails.logger.info("Notification ##{id} references deleted record; rendering placeholder")
      I18n.t("notifications.placeholder")
    end

    private

    def preferences_object
      recipient.try(:preferences)&.notification_preferences_object || NotificationPreferences.new(nil)
    end
  end

  # Override deliver to return sentinel :delivered on first-send or :deduplicated
  # on RecordNotUnique rescue. The DB partial unique index on noticed_events
  # (idempotency_key) is the atomic source of truth for concurrent dispatch;
  # this rescue is the real backstop, not dead code.
  #
  # No app-level SELECT-then-INSERT fast-path: that pattern was a TOCTOU race
  # in the previous implementation. The DB constraint enforces atomically.
  def deliver(recipients = nil, **options)
    super
    :delivered
  rescue ActiveRecord::RecordNotUnique
    :deduplicated
  end

  private

  # Populates record.idempotency_key (the column added by Task 2's hardening
  # migration). Writes to the column directly, NOT to params — the key is a
  # first-class identifier, not metadata buried in JSONB.
  #
  # Raises ArgumentError if no resource and no explicit key are supplied.
  # Loud failure beats silent dedup-collapse across distinct events.
  def populate_idempotency_key
    return if idempotency_key.present?

    explicit_key = params[:idempotency_key] || params["idempotency_key"]
    if explicit_key.present?
      self.idempotency_key = explicit_key
      return
    end

    resource = params[:resource] || params["resource"]
    resource_id = resource.try(:id) || resource.try(:to_gid_param)

    if resource_id.blank?
      raise ArgumentError,
        "#{self.class.name} requires either a :resource with an id, or an explicit :idempotency_key"
    end

    self.idempotency_key = "#{self.class.name}_#{resource_id}_#{Time.current.to_i / 60}"
  end
end
