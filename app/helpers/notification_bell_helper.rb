module NotificationBellHelper
  SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }.freeze

  SEVERITY_CLASSES = {
    danger:  { bg: "bg-danger",  icon: "text-danger-icon"  },
    warning: { bg: "bg-warning", icon: "text-warning-icon" },
    info:    { bg: "bg-info",    icon: "text-info-icon"    },
    success: { bg: "bg-success", icon: "text-success-icon" }
  }.freeze

  def unread_notification_summary(user)
    breakdown = user.unread_notification_breakdown
    return { count: 0, severity: nil } if breakdown.empty?

    count = breakdown.values.sum
    severity = breakdown.keys
      .map { resolve_severity_for(_1) }
      .max_by { SEVERITY_RANK.fetch(_1) }

    { count: count, severity: severity }
  end

  def notification_bell_classes(severity)
    SEVERITY_CLASSES.fetch(severity, SEVERITY_CLASSES[:info])
  end

  def avatar_button_aria_label(user, summary = unread_notification_summary(user))
    if summary[:count].zero?
      t("navigation.user_menu_label", name: user.full_name)
    else
      t("navigation.user_menu_label_with_unread",
        name: user.full_name,
        count: summary[:count],
        phrase: t("notifications.severity_phrase.#{summary[:severity]}"))
    end
  end

  private

  def resolve_severity_for(notifier_class_name)
    case notifier_class_name.safe_constantize
    in nil
      Rails.logger.warn("Stale notifier class in unread notifications: #{notifier_class_name}")
      :info
    in notifier_class
      notifier_class.severity_name || :info
    end
  end
end
