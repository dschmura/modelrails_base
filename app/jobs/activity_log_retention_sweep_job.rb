# frozen_string_literal: true

# Bounds the activity log (#438) — now in TWO grades:
#   * workspace-domain rows (Trackable): best-effort to write, swept at 12 months.
#   * account-security rows (ActivityLog::SECURITY_ACTIONS): written strictly
#     in-transaction with the credential mutation, retained for at least
#     SECURITY_RETENTION_FLOOR. This floor REPLACED the notification-layer
#     RETENTION_FLOORS (notifications lifecycle arc, 2026-08) — deleting or
#     shortening it silently destroys the system's only credential-event record.
# This job is the registered bypass through the ActivityLog immutability guard
# (#604). Batched delete_all — SQLite serializes writers.
# See /docs/developer/architecture (Activity Tracking).
class ActivityLogRetentionSweepJob < ApplicationJob
  queue_as :default

  RETENTION_WINDOW = 12.months
  SECURITY_RETENTION_FLOOR = 365.days

  def perform
    ActivityLog.where(created_at: ...RETENTION_WINDOW.ago)
               .where.not(action: ActivityLog::SECURITY_ACTIONS)
               .in_batches(of: 100, &:delete_all)
    ActivityLog.where(action: ActivityLog::SECURITY_ACTIONS)
               .where(created_at: ...SECURITY_RETENTION_FLOOR.ago)
               .in_batches(of: 100, &:delete_all)
  end
end
