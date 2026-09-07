# frozen_string_literal: true

# #927: the dispatch watermark. noticed commits the event + notification rows
# in one transaction and enqueues `Noticed::EventJob` after it; nothing records
# whether that enqueue ever landed. `dispatched_at` is stamped at the start of
# the job, and `NotificationDispatchReconcileJob` scans for rows that never got
# one. Nullable by construction — NULL *is* the "not yet dispatched" state.
#
# The index is partial and ordered by created_at because that is exactly the
# reconciler's scan (`dispatched_at IS NULL AND created_at <= ?`): once an
# event is stamped it leaves the index, so the index stays roughly empty in
# steady state rather than shadowing the whole ledger.
class AddDispatchedAtToNoticedEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :noticed_events, :dispatched_at, :datetime
    add_index :noticed_events, :created_at,
      where: "dispatched_at IS NULL",
      name: "index_noticed_events_undispatched"
  end
end
