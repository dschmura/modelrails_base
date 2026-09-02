# frozen_string_literal: true

require "rails_helper"

# The mirror of WorkspaceMemberAddedNotifier: a membership leaving the kept set
# was silent, so a removed member learned about it by hitting a wall (#933).
#
# Copy is per CHANNEL, not per reader: the in-app row is third-person event-log
# voice for everyone who receives it, and the email — which only the removed
# person ever gets — is second person.
RSpec.describe WorkspaceMemberRemovedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Scoped drains only: the un-scoped `perform_enqueued_jobs` would also run
  # CheckGravatarJob from the user factory, which does network IO.
  def drain_noticed_jobs
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
  end

  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
  end

  let(:workspace) { create(:workspace) }

  # `let!` throughout, for the reason spelled out in the member-added spec: the
  # User factory's onboarding callback creates a personal workspace membership,
  # and a lazy reference would fire notifiers during the action under test.
  let!(:owner_a) { create(:user, first_name: "Ada") }
  let!(:owner_b) { create(:user, first_name: "Bea") }
  let!(:removed_user) { create(:user, first_name: "Dee") }
  let!(:owner_a_membership) { create(:membership, user: owner_a, workspace: workspace, role: owner_role) }
  let!(:owner_b_membership) { create(:membership, user: owner_b, workspace: workspace, role: owner_role) }
  let!(:target_membership) { create(:membership, user: removed_user, workspace: workspace, role: member_role) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  def recipients_of_removal
    Noticed::Notification
      .where(type: "#{described_class.name}::Notification")
      .includes(:recipient)
      .map(&:recipient)
  end

  describe "declaration" do
    it "is workspace_activity at warning severity" do
      expect(described_class.category_name).to eq("workspace_activity")
      expect(described_class.severity_name).to eq(:warning)
    end
  end

  describe "recipient resolution" do
    it "tells the removed member and the owners who did not do it" do
      target_membership.deactivate!(removed_by: owner_a)

      expect(recipients_of_removal).to contain_exactly(removed_user, owner_b)
    end

    it "tells both owners, and not the leaver, when a member leaves on their own" do
      target_membership.deactivate!(removed_by: removed_user)

      expect(recipients_of_removal).to contain_exactly(owner_a, owner_b)
    end

    it "leaves only the removed member when the sole owner does the removing" do
      owner_b_membership.deactivate!(removed_by: owner_a)
      Noticed::Notification.delete_all
      Noticed::Event.delete_all

      target_membership.deactivate!(removed_by: owner_a)

      expect(recipients_of_removal).to eq([ removed_user ])
    end

    it "tells everyone when no actor is named" do
      target_membership.deactivate!

      expect(recipients_of_removal).to contain_exactly(removed_user, owner_a, owner_b)
    end
  end

  describe "message copy" do
    def message_for(user)
      Noticed::Notification
        .where(type: "#{described_class.name}::Notification", recipient: user)
        .last&.message
    end

    it "reads as a removal for everyone when someone else did it" do
      target_membership.deactivate!(removed_by: owner_a)

      expect(message_for(removed_user)).to eq("Dee was removed from #{workspace.name}")
      expect(message_for(owner_b)).to eq("Dee was removed from #{workspace.name}")
    end

    it "reads as a departure when the member removed themselves" do
      target_membership.deactivate!(removed_by: removed_user)

      expect(message_for(owner_a)).to eq("Dee left #{workspace.name}")
    end
  end

  describe "email leg" do
    it "emails the removed member and nobody else" do
      target_membership.deactivate!(removed_by: owner_a)
      drain_noticed_jobs
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([ removed_user.email_address ])
      expect(ActionMailer::Base.deliveries.last.subject)
        .to eq("You've been removed from #{workspace.name}")
    end

    it "sends nothing when the member left on their own" do
      expect {
        target_membership.deactivate!(removed_by: removed_user)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_removed)
    end

    it "never emails an owner" do
      target_membership.deactivate!(removed_by: owner_a)
      drain_noticed_jobs
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

      owner_addresses = [ owner_a.email_address, owner_b.email_address ]
      expect(ActionMailer::Base.deliveries.flat_map(&:to) & owner_addresses).to be_empty
    end

    it "respects the removed member's category opt-out" do
      prefs = create(:user_preferences, user: removed_user)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["workspace_activity"] = false
      prefs.update!(notification_preferences: np)

      expect {
        target_membership.deactivate!(removed_by: owner_a)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_removed)
    end
  end

  describe "dispatch trigger" do
    it "fires exactly one event on the discard" do
      expect {
        target_membership.deactivate!(removed_by: owner_a)
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end

    # Both of these travel past the notifier's one-minute idempotency bucket
    # first. Without that, a callback firing on the WRONG side of the
    # discarded_at change still produces no new event — the dedup key
    # (notifier, record, minute) swallows it — and the example passes while
    # the guard it exists to prove is gone.
    it "does not fire when the member is brought back" do
      target_membership.deactivate!(removed_by: owner_a)

      expect {
        travel_to(2.minutes.from_now) { target_membership.reactivate!(granted_by: owner_a) }
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end

    it "does not fire on an unrelated update" do
      target_membership.deactivate!(removed_by: owner_a)
      target_membership.reactivate!(granted_by: owner_a)

      expect {
        travel_to(2.minutes.from_now) { target_membership.update!(last_accessed_at: Time.current) }
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end
  end

  describe "#url" do
    it "renders a placeholder rather than raising when the workspace is gone" do
      target_membership.deactivate!(removed_by: owner_a)
      notification = Noticed::Notification
        .where(type: "#{described_class.name}::Notification", recipient: removed_user).last
      allow(notification.event.record).to receive(:workspace).and_return(nil)

      expect { notification.url }.not_to raise_error
    end
  end
end
