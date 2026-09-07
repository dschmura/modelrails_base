require "rails_helper"

RSpec.describe "Notification Turbo Stream broadcasts" do
  let(:user) { create(:user) }

  it "broadcasts the v2 trio (avatar dot + hamburger dot + user-menu count row) to each recipient on event commit" do
    # All surfaces use broadcast_update_to now; allow the aria-live one (asserted
    # separately) so the three frame expectations below are the only constraints.
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_indicator_avatar",
      partial: "shared/notifications_indicator",
      locals: hash_including(summary: hash_including(:count, :severity), surface: :avatar)
    )
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_indicator_hamburger",
      partial: "shared/notifications_indicator",
      locals: hash_including(summary: hash_including(:count, :severity), surface: :hamburger)
    )
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_menu_count_frame",
      partial: "shared/user_menu_notifications_row",
      locals: hash_including(user: a_kind_of(User), summary: hash_including(:count, :severity))
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts all four surfaces once per recipient when fanned out" do
    # 2 recipients × 4 surfaces (avatar dot + hamburger dot + menu count +
    # aria-live) = 8 update_to calls. v2 restored the menu-count broadcast that
    # D1 had dropped, because the user menu carries the canonical Notifications
    # link with a live count badge. All surfaces use broadcast_update_to so the
    # <turbo-frame> targets survive repeat refreshes.
    other = create(:user)

    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).exactly(8).times

    PasswordChangedNotifier.with(record: user).deliver([ user, other ])
  end

  it "skips broadcasts for an event that created no notification rows" do
    # Badge surfaces follow the notification ROWS, never the dispatch: an
    # event whose recipients all gated out commits with zero rows, and
    # nobody's bell should twitch for it.
    #
    # Reached publicly — the workspace's only owner switches the billing
    # category off, so WorkspaceCapacityApproachingNotifier's permitted_in_app
    # gate resolves to nobody. (The previous framing, "no User recipients",
    # is unreachable: db/schema.rb's `check_constraint "recipient_type =
    # 'User'"` on noticed_notifications rejects every other recipient type.)
    workspace = user.personal_workspace
    prefs = create(:user_preferences, user: user)
    types = prefs.notification_preferences["notification_types"].deep_dup
    types["billing"] = false
    prefs.update!(notification_preferences: prefs.notification_preferences.merge("notification_types" => types))
    # Not a vacuous pass: the owner IS a candidate, so zero recipients is the
    # preference gate's doing, not an empty owner set.
    expect(workspace.owners).to eq([ user ])
    # A notification row belonging to a DIFFERENT event, so the hook's
    # event_id scope is load-bearing here: a recipient query that dropped it
    # would broadcast to this user off the back of our empty event.
    other = create(:user)
    PasswordChangedNotifier.with(record: other).deliver(other)

    expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)

    event = WorkspaceCapacityApproachingNotifier.with(record: workspace, metric: "members", current: 8, limit: 10)
    expect { event.deliver(nil) }.to change { Noticed::Event.count }.by(1)
    expect(Noticed::Notification.where(event_id: Noticed::Event.last.id)).to be_empty
  end

  it "swallows broadcast adapter errors so notification creation isn't blocked" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(StandardError, "cable down")

    expect {
      PasswordChangedNotifier.with(record: user).deliver(user)
    }.not_to raise_error
  end

  # Panel-review blocker #1: bare `rescue StandardError` swallowed broadcast
  # errors silently. A genuine bug in the partial (e.g., a NoMethodError
  # introduced by a refactor) would disappear with zero signal to ops.
  # Swallow remains correct — notification creation must not block on a
  # broadcast outage — but the failure must reach error tracking.
  it "logs + reports broadcast errors so silent failures reach error tracking" do
    error = StandardError.new("cable down")
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(error)

    expect(Rails.logger).to receive(:warn).with(/cable down/).at_least(:once)
    expect(Rails.error).to receive(:report).with(error, hash_including(handled: true)).at_least(:once)

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts an aria-live announcement update to the recipient" do
    # The frame surfaces also broadcast_update_to (different targets); allow them
    # so the specific aria-live expectation below is the only constraint.
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    # #926: a danger-severity arrival is named and assertive; nothing generic.
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications-live-assertive",
      content: I18n.t("notifications.bell.arrival_announcement_with_severity",
                      phrase: I18n.t("notifications.severity_phrase.danger"))
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "announces an info-severity arrival politely, naming its severity (#926)" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications-live",
      content: I18n.t("notifications.bell.arrival_announcement_with_severity",
                      phrase: I18n.t("notifications.severity_phrase.info"))
    )

    workspace = create(:workspace)
    membership = create(:membership, user: user, workspace: workspace)
    WorkspaceRoleChangedNotifier.with(record: membership).deliver(user)
  end
end
