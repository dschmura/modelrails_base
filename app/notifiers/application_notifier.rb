# frozen_string_literal: true

class ApplicationNotifier < Noticed::Event
  class_attribute :category_name, instance_accessor: false

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
      update_column(:seen_at, Time.current)
    end

    # Wrap any Notifier message/url body that traverses associations or
    # accesses attributes on the resource. Catches:
    #   - ActiveRecord::RecordNotFound (e.g., resource was destroyed mid-render)
    #   - NoMethodError on nil receiver (e.g., a chained association is now nil)
    # Real bugs (typos, missing methods on non-nil receivers) propagate.
    #
    # Note: only deletion shapes where Ruby raises with a *nil* receiver are
    # caught. If your message accesses `resource.invitable.name` and the
    # `invitable` is gone, the call to `.name` on nil raises NoMethodError
    # with receiver=nil — caught. Other deletion patterns (stale FK pointing
    # to a deleted record that still loads as a stub object) won't trigger
    # nil-receiver and may bubble up as RecordNotFound or other exceptions.
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

  # CALLSITE CONVENTION: Notifier callers should pass BOTH `record:` AND
  # `resource:` in the with(...) hash. They are typically the same object,
  # but conceptually distinct:
  #   - `record:` is Noticed's polymorphic backref (populates noticed_events.record_type/_id)
  #   - `resource:` is our idempotency-key seed (read by populate_idempotency_key below)
  # Future Notifiers should follow this pattern unless there's a reason to use
  # different objects (e.g., resource is a transient activity object while
  # record points to the canonical domain entity).
  #
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

    # One-minute bucket is the documented dedup window. Cross-boundary
    # dispatches (one at second 59, retry at second 0 of next minute) get
    # different keys and BOTH succeed. This is intentional — coalescing
    # beyond a minute is digest territory, not idempotency.
    self.idempotency_key = "#{self.class.name}_#{resource_id}_#{Time.current.to_i / 60}"
  end
end
