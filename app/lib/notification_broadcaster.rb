# frozen_string_literal: true

# Refreshes a user's three independent notification surfaces (D1):
#   - bell LABEL frame      (sr-only aria-label text — sibling of the bell
#                            link, NOT the link itself; replacing the label
#                            keeps the focusable link stable so clicks
#                            landing mid-broadcast still hit a live target)
#   - bell indicator frame  (severity-colored chip overlay rendered inside
#                            the bell link)
#   - aria-live region      (SR announcement)
#
# Each broadcast runs in its own rescue scope: a failure on ONE surface
# must NOT abort the others. Real failure mode this prevents: a transient
# cable adapter hiccup or a partial-rendering exception on the first
# broadcast used to silently drop the indicator + aria-live refresh,
# leaving the UI stale.
#
# D1 dropped the `notifications_menu_count_frame` broadcast: the user
# menu no longer carries a Notifications link with an inline count (the
# bell is now a standalone header affordance with the count baked into
# its aria-label).
#
# D1 renamed the label frame: `notifications_avatar_button_label_frame`
# → `notifications_bell_label_frame`, matching its new home on the bell
# rather than the avatar.
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
# The swallow-log-report contract from PR #97 lives here too (per
# broadcast): a cable adapter outage doesn't propagate back to notification
# creation or controller actions but still reaches error tracking.
#
# Performance: the unread breakdown summary is computed ONCE at the top of
# refresh_for and passed to each receiving partial as a `summary:` local.
# This avoids redundant `unread_notification_breakdown` queries that would
# otherwise fire (one per partial that needs it).
module NotificationBroadcaster
  module_function

  def refresh_for(user, announcement_key:)
    stream_key = [ user, :notifications ]
    summary = NotificationBellHelper.unread_notification_summary(user)

    safe_broadcast(stream_key, source: "bell_label") do
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_key,
        target: "notifications_bell_label_frame",
        partial: "shared/notifications_bell_label",
        locals: { user: user, summary: summary }
      )
    end

    safe_broadcast(stream_key, source: "bell_indicator") do
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_key,
        target: "notifications_bell_indicator_frame",
        partial: "shared/notifications_bell",
        locals: { user: user, summary: summary }
      )
    end

    safe_broadcast(stream_key, source: "aria_live") do
      Turbo::StreamsChannel.broadcast_update_to(
        stream_key,
        target: "notifications-live",
        content: I18n.t(announcement_key)
      )
    end
  end

  def safe_broadcast(stream_key, source:)
    yield
  rescue StandardError => e
    Rails.logger.warn("notification broadcast failed (#{source}): #{e.class}: #{e.message}")
    Rails.error.report(
      e,
      handled: true,
      severity: :warning,
      context: { source: "NotificationBroadcaster.#{source}", stream_key: stream_key.inspect }
    )
  end
  private_class_method :safe_broadcast
end
