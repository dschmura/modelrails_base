module NotificationBellHelper
  # Higher rank wins when multiple severities are unread.
  # `max_by { SEVERITY_RANK.fetch(_1) }` in #unread_notification_summary
  # uses this to select the dominant severity for the bell.
  SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }.freeze

  # The bell IS the indicator — no chip. Each severity uses its saturated
  # `--color-{severity}` token (registered as a Tailwind utility in
  # application.css's `@theme inline` block), so `text-danger` /
  # `text-warning` / `text-info` / `text-success` compile to the same AAA
  # foreground tokens used elsewhere (e.g. flash messages, link colors).
  # The partial pairs these with a stacked white drop-shadow outline for
  # legibility on arbitrary avatar backgrounds.
  # `dark:text-danger-strong` on danger ONLY: the AAA-readable dark
  # `--color-danger` (L=0.808) reads as coral/pink on the bell-sized
  # graphic at high lightness. The `-strong` variant (L=0.65) restores
  # the fire-engine red character. Other severities stay on their
  # AAA tokens — only red has the high-lightness identity-shift
  # problem (see `_signals.css` for the rule).
  SEVERITY_CLASSES = {
    danger:  { icon: "text-danger dark:text-danger-strong" },
    warning: { icon: "text-warning" },
    info:    { icon: "text-info"    },
    success: { icon: "text-success" }
  }.freeze

  # `extend self` makes every method below callable BOTH as a module
  # method (e.g. `NotificationBellHelper.unread_notification_summary(user)`,
  # used by NotificationBroadcaster which has no view-helper context) AND
  # as a public instance method when the module is mixed into a view (the
  # normal ActionView helper path). Unlike `module_function`, instance-mixed
  # methods remain public — so `helper.foo` works in specs.
  extend self

  def unread_notification_summary(user)
    breakdown = user.unread_notification_breakdown
    return { count: 0, severity: nil } if breakdown.empty?

    count = breakdown.values.sum
    severity = breakdown.keys
      .map { _resolve_severity_for(_1) }
      .max_by { SEVERITY_RANK.fetch(_1) }

    { count: count, severity: severity }
  end

  def notification_bell_classes(severity)
    SEVERITY_CLASSES.fetch(severity, SEVERITY_CLASSES[:info])
  end

  # Normalizes any severity input to one of the four canonical values.
  # Used by the bell partial so `data-bell-severity` always reads as one
  # of [danger, warning, info, success], even if a notifier class slips
  # through with an off-canonical severity. Production paths are already
  # guarded by ApplicationNotifier's `severity` DSL validation, so this
  # is defensive coverage for test stubs, library injection, and other
  # non-production cases.
  def canonical_severity(severity)
    SEVERITY_RANK.key?(severity) ? severity : :info
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

  # Accessible name for the standalone notifications bell header link
  # (D1). Parallels `avatar_button_aria_label` but speaks for the bell —
  # it announces unread count + dominant-severity phrase without naming
  # the user (the bell sits beside the avatar; the avatar carries the
  # identity label). When there are no unread notifications, the label
  # collapses to plain "Notifications" — the icon glyph + click target
  # are sufficient affordance.
  def bell_link_aria_label(user, summary = unread_notification_summary(user))
    if summary[:count].zero?
      t("navigation.bell.label")
    elsif summary[:severity]
      t("navigation.bell.label_with_unread",
        count: summary[:count],
        phrase: t("notifications.severity_phrase.#{summary[:severity]}"))
    else
      t("navigation.bell.label_with_unread_count_only", count: summary[:count])
    end
  end

  def _resolve_severity_for(notifier_class_name)
    case notifier_class_name.safe_constantize
    in nil
      Rails.logger.warn("Stale notifier class in unread notifications: #{notifier_class_name}")
      :info
    in notifier_class
      notifier_class.severity_name || :info
    end
  end
end
