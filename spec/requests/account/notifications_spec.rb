# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Notifications", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/notifications to sign in" do
      get account_notifications_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects POST /account/notifications/mark_all_read to sign in" do
      post mark_all_read_account_notifications_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/notifications/destroy_all_read to sign in" do
      delete destroy_all_read_account_notifications_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    before { sign_in(user) }

    # Helper: dispatches a real notifier so the message body, recipient
    # association, idempotency key — everything the index renders — is exactly
    # what production builds. Using PasswordChangedNotifier (security category)
    # for the default; tests that need account_access dispatch their own.
    def deliver_security_notification(recipient = user)
      # Travel forward by random minutes to avoid the 1-minute idempotency
      # bucket from collapsing repeat dispatches in the same example.
      travel_to(Time.current + rand(1..1000).minutes) do
        PasswordChangedNotifier.with(record: recipient).deliver(recipient)
      end
      recipient.notifications.reload.last
    end

    def deliver_account_access_notification(recipient: user, inviter: nil)
      inviter ||= create(:user)
      workspace = create(:workspace)
      invitation = create(:invitation,
                          invitable: workspace,
                          email: "x#{SecureRandom.hex(4)}@example.com",
                          invited_by: inviter)
      travel_to(Time.current + rand(1..1000).minutes) do
        WorkspaceInvitationResentNotifier.with(record: invitation).deliver(recipient)
      end
      recipient.notifications.reload.last
    end

    # Matches the dom_id pattern used by the placeholder index view (Task 12
    # will swap to a per-row partial that may use a different identifier
    # shape; if so, update this helper).
    def dom_id_fragment(notification)
      "id=\"#{ActionView::RecordIdentifier.dom_id(notification)}\""
    end

    describe "GET /account/notifications" do
      it "returns 200 and renders the index" do
        deliver_security_notification
        get account_notifications_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("notifications.index.heading"))
      end

      it "scopes to the current user (own notifications visible, others' not)" do
        own = deliver_security_notification
        foreign = deliver_security_notification(other_user)
        # Sign-in detection itself dispatches a SignInFromNewDeviceNotifier
        # to the current user, so the user's notifications list is non-empty
        # by the time this request fires. Assert specifically that:
        #   1. the user's OWN dispatched notification IS rendered (positive),
        #   2. the foreign user's notification is NOT rendered.
        # The positive assertion guards against a future regression where the
        # index breaks rendering for legitimate recipients but coincidentally
        # still hides foreign rows.
        get account_notifications_path
        expect(response.body).to include(dom_id_fragment(own))
        expect(response.body).not_to include(dom_id_fragment(foreign))
        expect(response).to have_http_status(:ok)
      end

      it "paginates with Pagy at 25 per page" do
        # Create 30 notifications via direct insert (faster than dispatch).
        event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: user)
        notifications = Array.new(30) do
          Noticed::Notification.create!(
            event: event,
            recipient: user,
            type: "PasswordChangedNotifier::Notification"
          )
        end
        get account_notifications_path
        rendered = notifications.count { |n| response.body.include?(dom_id_fragment(n)) }
        # Sign-in detection adds 1 user notification on the way in, so first
        # page may include 24 of our 30 + the sign-in notification — still 25
        # total on the page. Assert at least 24 of our 30 rendered (Pagy caps
        # the page at 25 rows).
        expect(rendered).to be >= 24
        expect(rendered).to be <= 25
      end

      context "?filter=unread" do
        it "renders only unread notifications" do
          read_notification = deliver_security_notification
          read_notification.update!(read_at: Time.current)
          unread_notification = deliver_security_notification

          get account_notifications_path, params: { filter: "unread" }
          expect(response.body).to include(dom_id_fragment(unread_notification))
          expect(response.body).not_to include(dom_id_fragment(read_notification))
        end
      end

      context "?category=security" do
        it "renders only notifications for that category" do
          security_notification = deliver_security_notification
          access_notification = deliver_account_access_notification(recipient: user)

          get account_notifications_path, params: { category: "security" }
          expect(response.body).to include(dom_id_fragment(security_notification))
          expect(response.body).not_to include(dom_id_fragment(access_notification))
        end
      end
    end

    describe "PATCH /account/notifications/:id" do
      let!(:notification) { deliver_security_notification }

      it "marks the notification as read when read_at is set" do
        patch account_notification_path(notification), params: { read_at: "now" }
        expect(notification.reload.read_at).to be_present
      end

      it "marks the notification as unread when read_at is blank" do
        notification.update!(read_at: Time.current)
        patch account_notification_path(notification), params: { read_at: "" }
        expect(notification.reload.read_at).to be_nil
      end

      it "redirects via the ApplicationController not-found rescue for another user's notification" do
        foreign = deliver_security_notification(other_user)
        patch account_notification_path(foreign), params: { read_at: "now" }
        # set_notification scopes through Current.user.notifications.find,
        # so a foreign id raises ActiveRecord::RecordNotFound — rescued by
        # ApplicationController#record_not_found which redirects HTML format
        # to request.referer || root_path with the not_found alert.
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
        expect(foreign.reload.read_at).to be_nil
      end
    end

    describe "DELETE /account/notifications/:id" do
      let!(:notification) { deliver_security_notification }

      it "destroys the notification" do
        expect {
          delete account_notification_path(notification)
        }.to change { user.notifications.count }.by(-1)
      end

      it "redirects via the ApplicationController not-found rescue for another user's notification" do
        foreign = deliver_security_notification(other_user)
        expect {
          delete account_notification_path(foreign)
        }.not_to change { other_user.notifications.count }
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      end
    end

    describe "POST /account/notifications/mark_all_read" do
      it "marks ALL of the current user's unread notifications as read (250-row behavior assertion)" do
        # Build 250 unread notifications without going through the notifier
        # (faster + avoids idempotency collisions). We assert the OUTCOME —
        # all 250 rows have read_at set after the request — not the
        # implementation detail (single update_all vs. batched).
        event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: user)
        notifications = Array.new(250) do
          Noticed::Notification.create!(
            event: event,
            recipient: user,
            type: "PasswordChangedNotifier::Notification"
          )
        end

        post mark_all_read_account_notifications_path

        unread_remaining = user.notifications.where(read_at: nil).count
        expect(unread_remaining).to eq(0)
        expect(notifications.first.reload.read_at).to be_present
        expect(notifications.last.reload.read_at).to be_present
      end

      it "does not affect other users' unread notifications" do
        foreign_event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: other_user)
        foreign = Noticed::Notification.create!(
          event: foreign_event,
          recipient: other_user,
          type: "PasswordChangedNotifier::Notification"
        )

        post mark_all_read_account_notifications_path

        expect(foreign.reload.read_at).to be_nil
      end

      it "redirects with a success notice" do
        post mark_all_read_account_notifications_path
        expect(response).to redirect_to(account_notifications_path)
        expect(flash[:notice]).to eq(I18n.t("notifications.index.mark_all_read.success"))
      end
    end

    describe "DELETE /account/notifications/destroy_all_read" do
      it "destroys ALL of the current user's read notifications (250-row behavior assertion)" do
        event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: user)
        Array.new(250) do
          Noticed::Notification.create!(
            event: event,
            recipient: user,
            type: "PasswordChangedNotifier::Notification",
            read_at: Time.current
          )
        end

        expect {
          delete destroy_all_read_account_notifications_path
        }.to change { user.notifications.count }.by(-250)
        expect(user.notifications.where.not(read_at: nil).count).to eq(0)
      end

      it "leaves unread notifications intact" do
        unread = deliver_security_notification
        delete destroy_all_read_account_notifications_path
        expect { unread.reload }.not_to raise_error
      end

      it "does not affect other users' read notifications" do
        foreign_event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: other_user)
        foreign = Noticed::Notification.create!(
          event: foreign_event,
          recipient: other_user,
          type: "PasswordChangedNotifier::Notification",
          read_at: Time.current
        )

        delete destroy_all_read_account_notifications_path

        expect { foreign.reload }.not_to raise_error
      end
    end
  end
end
