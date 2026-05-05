# frozen_string_literal: true

# Fires when a scheduled sweep job (`WorkspaceCapacitySweepJob`) detects that a
# workspace has reached >= 80% of its `max_members` quota. Recipients are every
# owner of the workspace; channels are in-app + email; category is `:billing`
# (NOT security — DND suppresses these).
#
# Idempotency:
#   The base ApplicationNotifier seeds (class, record.id, minute). For a billing
#   alert that's emitted by a recurring sweep, a one-minute bucket is too tight:
#   the sweep cadence is 12 hours, but two manual triggers in the same minute
#   would silently collapse, AND we want at most one alert per (workspace, metric)
#   per DAY regardless of how many sweep runs land in that day. Override with
#   a day-bucket key folded with the metric so:
#     - Members and projects metrics for the same workspace on the same day each
#       get one alert (don't collapse onto each other).
#     - Repeat sweeps the same day collapse onto the same key (deduplicated).
#     - The next day's sweep gets a fresh key (delivers again if still over).
#
# In-app gating happens at recipient-resolution time: owners whose
# billing.in_app preference is false (or DND on, since billing is non-security)
# are filtered out of `recipients` entirely, so no notification row is created
# for them. This mirrors WorkspaceMemberAddedNotifier's gate point — the
# :database delivery method is deprecated in Noticed 2.9.x, so per-recipient
# in-app gating MUST happen here.
class WorkspaceCapacityApproachingNotifier < ApplicationNotifier
  category :billing

  required_param :metric, :current, :limit

  recipients do
    workspace = record
    # Owners include both global ("workspace_id IS NULL") and any workspace-scoped
    # owner role, mirroring `WorkspaceMemberAddedNotifier`'s resolver.
    # `.includes(:user)` preloads the user association so the subsequent
    # `.map(&:user)` does not N+1 — the resolver runs synchronously inside the
    # sweep job's tight loop, so per-row association loads compound quickly.
    owner_role_ids = Role.where(slug: "owner", workspace_id: [ nil, workspace.id ]).pluck(:id)
    owner_users = workspace.memberships.kept.where(role_id: owner_role_ids).includes(:user).map(&:user).compact

    # Filter out users whose billing.in_app pref is off (or DND). See class-level
    # docs above for why this is the correct gate point. The `preferences_for`
    # helper wraps the schema-default JSONB blob for users without a persisted
    # UserPreferences row, so newly-created users are correctly treated as
    # opted-in for in-app at the column-default level.
    owner_users.select do |user|
      preferences_for(user).allow?(category: "billing", channel: "in_app")
    end
  end

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_capacity_approaching
    config.before_enqueue = -> { throw(:abort) unless recipient_pref(:email) }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_capacity_approaching.message",
          locale: recipient_locale,
          workspace: event.record.name,
          metric: event.params[:metric],
          current: event.params[:current],
          limit: event.params[:limit]
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.edit_workspace_settings_path(event.record)
    end
  end

  private

  # Day-bucket idempotency, scoped per (workspace, metric) — see class-level
  # docs above for the full rationale.
  def populate_idempotency_key
    return if idempotency_key.present?
    day = Time.current.to_date.iso8601
    self.idempotency_key = "#{self.class.name}_#{record.id}_#{params[:metric]}_#{day}"
  end
end
