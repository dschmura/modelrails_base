require "rails_helper"

RSpec.describe NotificationBroadcaster do
  let(:user) { create(:user) }

  describe ".refresh_for" do
    it "broadcasts the bell-button frame, dropdown frame, and aria-live update for the given user" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ user, :notifications ],
        target: "notifications_bell_frame",
        partial: "shared/notifications_bell_button",
        locals: { user: user }
      )
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ user, :notifications ],
        target: "notifications_dropdown_frame",
        partial: "shared/notifications_dropdown_list",
        locals: { user: user }
      )
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        [ user, :notifications ],
        target: "notifications-live",
        content: I18n.t("notifications.bell.arrival_announcement")
      )

      described_class.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
    end

    it "uses the announcement key to localize the aria-live content (e.g., read_state_announcement)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        [ user, :notifications ],
        target: "notifications-live",
        content: I18n.t("notifications.bell.read_state_announcement")
      )

      described_class.refresh_for(user, announcement_key: "notifications.bell.read_state_announcement")
    end

    # Inherits the same swallow-log-report contract documented on the
    # original broadcast site (PR #97). A broadcast adapter outage must
    # never propagate back to the caller (notifier callback or controller
    # action), but the failure must reach error tracking.
    it "swallows + logs + reports broadcast adapter errors so callers aren't blocked" do
      error = StandardError.new("cable down")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(error)

      expect(Rails.logger).to receive(:warn).with(/cable down/).at_least(:once)
      expect(Rails.error).to receive(:report).with(error, hash_including(handled: true)).at_least(:once)

      expect {
        described_class.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
      }.not_to raise_error
    end
  end
end
