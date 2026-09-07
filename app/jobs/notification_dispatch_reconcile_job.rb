# frozen_string_literal: true

# The recovery half of the #927 dispatch watermark. `Noticed::EventJob` stamps
# `noticed_events.dispatched_at` the moment it starts (see
# `config/initializers/noticed.rb`), so an event still carrying NULL after the
# grace window is one whose enqueue never landed: the rows committed, the
# recipient can see the notification, the idempotency key is burned — and the
# email and broadcast legs never ran.
#
# Only the never-enqueued gap. A job that WAS claimed and then failed is Solid
# Queue's to retry or discard under its own policy, and it is already stamped,
# so this sweep can never re-run an event whose delivery legs fanned out.
#
# GRACE is well past any plausible enqueue latency and short enough that a
# recovered notification is late rather than missing; the 15-minute cadence in
# config/recurring.yml is the other half of that budget.
#
# Mirrors NotificationCleanupJob's shape: attempted/failed counters, per-row
# rescue reported through Rails.error, and a re-raise when every attempt failed
# so a systemic fault (SQLite's writer lock is global) is recorded as a job
# failure instead of logged as a successful cycle.
class NotificationDispatchReconcileJob < ApplicationJob
  queue_as :low

  GRACE = 5.minutes

  def perform
    attempted = 0
    failed = 0
    last_error = nil

    undispatched.find_each do |event|
      attempted += 1
      Noticed::EventJob.perform_later(event)
    rescue StandardError => e
      failed += 1
      last_error = e
      Rails.error.report(e, handled: true, context: { event_id: event.id, job: self.class.name })
    end

    raise last_error if failed.positive? && failed == attempted
  end

  private

  # `notifications_count` is written inside noticed's own deliver transaction,
  # so a zero is a real zero-recipient dispatch — the artifact #928 is about —
  # and there is nobody for a re-enqueue to reach. Rows with a NULL count were
  # never delivered through `deliver` at all and are skipped by the same
  # NULL-unsafe `!=`, deliberately.
  def undispatched
    Noticed::Event
      .where(dispatched_at: nil)
      .where(created_at: ..GRACE.ago)
      .where.not(notifications_count: 0)
  end
end
