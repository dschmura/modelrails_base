# frozen_string_literal: true

module Account
  class NotificationsController < ApplicationController
    before_action :set_notification, only: [ :update, :destroy ]

    def index
      scope = policy_scope(Noticed::Notification, policy_scope_class: NotificationPolicy::Scope)
                .order(created_at: :desc)
      scope = scope.where(read_at: nil) if params[:filter] == "unread"
      if params[:category].present?
        scope = scope.where(type: notifier_types_in_category(params[:category]))
      end
      @pagy, @notifications = pagy(scope, limit: 25)
      # NOTE: per-row eager-loading (event, event.record, recipient) is not
      # applied here because the notifier subtypes vary in which associations
      # their `#message` traverses (e.g. SignInFromNewDevice reads only
      # event.params, while WorkspaceInvitationAccepted traverses
      # event.record.invited_by). Task 12's per-row partial wires the
      # right-shaped includes once the per-subtype rendering surface is
      # finalized.
    end

    def update
      authorize @notification, policy_class: NotificationPolicy
      @notification.update!(read_at: read_value)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: account_notifications_path }
      end
    end

    def destroy
      authorize @notification, policy_class: NotificationPolicy
      @notification.destroy!
      redirect_to account_notifications_path, notice: t("notifications.destroy.success")
    end

    def mark_all_read
      Current.user.notifications.where(read_at: nil).in_batches(of: 100) do |batch|
        batch.update_all(read_at: Time.current, updated_at: Time.current)
      end
      redirect_to account_notifications_path,
                  notice: t("notifications.index.mark_all_read.success")
    end

    def destroy_all_read
      Current.user.notifications.where.not(read_at: nil).in_batches(of: 100) do |batch|
        batch.destroy_all
      end
      redirect_to account_notifications_path,
                  notice: t("notifications.index.destroy_all_read.success")
    end

    private

    def set_notification
      @notification = Current.user.notifications.find(params[:id])
    end

    def read_value
      params[:read_at].present? ? Time.current : nil
    end

    # Maps a category slug back to the set of Notifier subclass names so we can
    # filter the notifications scope by `type`. Note: noticed_notifications.type
    # stores the per-notification subclass (e.g. "PasswordChangedNotifier::Notification"),
    # so we suffix here. We force-load the notifiers directory in development/test
    # because ApplicationNotifier.descendants is empty until subclasses are
    # autoloaded — eager_load is only on in CI and production.
    def notifier_types_in_category(category)
      ensure_notifiers_loaded
      ApplicationNotifier.descendants
                         .select { |c| c.category_name == category.to_s }
                         .map { |c| "#{c.name}::Notification" }
    end

    def ensure_notifiers_loaded
      return if Rails.application.config.eager_load
      Rails.root.glob("app/notifiers/*.rb").each { |p| require_dependency p.to_s }
    end
  end
end
