# frozen_string_literal: true

# Broadcast quartet that refreshes a user's notification surfaces:
#   - avatar button frame  (refreshes aria-label so AT narrative stays
#                           coherent with the severity-colored chip overlay)
#   - bell indicator frame (severity-colored chip overlay on the avatar)
#   - menu count frame     (Notifications menu-link count text, e.g. "(3)")
#   - aria-live region     (SR announcement)
#
# `announcement_key` is an I18n key passed straight to `I18n.t`. Two
# canonical values exist today:
#   - notifications.bell.arrival_announcement   ("New notification")
#   - notifications.bell.read_state_announcement ("Notifications updated")
#
# Two callers, one shape:
#   1. ApplicationNotifier#broadcast_notifications_arrival (after_create_commit
#      on the event), called per recipient.
#   2. Account::NotificationsController#broadcast_bell_refresh, called for
#      Current.user after a read-state mutation (mark/unmark, mark_all_read,
#      open, destroy-when-unread).
#
# Both paths previously inlined the same Turbo::StreamsChannel calls —
# extracting them here removes the duplication and (more importantly)
# means future broadcast additions land in one place. The swallow-log-report
# contract from PR #97 lives here too, so a cable adapter outage doesn't
# propagate back to notification creation or controller actions but still
# reaches error tracking.
module NotificationBroadcaster
  module_function

  def refresh_for(user, announcement_key:)
    stream_key = [ user, :notifications ]

    Turbo::StreamsChannel.broadcast_replace_to(
      stream_key,
      target: "notifications_avatar_button_frame",
      partial: "shared/user_menu_avatar_button",
      locals: { user: user }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream_key,
      target: "notifications_bell_indicator_frame",
      partial: "shared/notifications_bell",
      locals: { user: user }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream_key,
      target: "notifications_menu_count_frame",
      partial: "shared/notifications_menu_count_span",
      locals: { user: user }
    )

    Turbo::StreamsChannel.broadcast_update_to(
      stream_key,
      target: "notifications-live",
      content: I18n.t(announcement_key)
    )
  rescue StandardError => e
    Rails.logger.warn("notification broadcast failed: #{e.class}: #{e.message}")
    Rails.error.report(
      e,
      handled: true,
      severity: :warning,
      context: { source: "NotificationBroadcaster.refresh_for", announcement_key: announcement_key }
    )
  end
end
