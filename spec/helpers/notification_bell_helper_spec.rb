require "rails_helper"

RSpec.describe NotificationBellHelper, type: :helper do
  let(:user) { create(:user) }
  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end

  describe "#unread_notification_summary" do
    it "returns count 0 and nil severity when there are no unread notifications" do
      expect(helper.unread_notification_summary(user)).to eq(count: 0, severity: nil)
    end

    it "returns the total count and the highest severity present" do
      # danger
      PasswordChangedNotifier.with(record: user).deliver(user)

      # warning — user must be a workspace owner to receive
      warning_workspace = create(:workspace)
      create(:membership, user: user, workspace: warning_workspace, role: owner_role)
      WorkspaceCapacityApproachingNotifier
        .with(record: warning_workspace, metric: :members, current: 8, limit: 10)
        .deliver(user)

      # success — added_user is the added Membership.user
      success_workspace = create(:workspace)
      added_membership = create(:membership, user: user, workspace: success_workspace)
      WorkspaceMemberAddedNotifier.with(record: added_membership).deliver(user)

      result = helper.unread_notification_summary(user)
      expect(result[:count]).to eq(3)
      expect(result[:severity]).to eq(:danger)
    end

    it "ranks warning above info above success" do
      warning_workspace = create(:workspace)
      create(:membership, user: user, workspace: warning_workspace, role: owner_role)
      WorkspaceCapacityApproachingNotifier
        .with(record: warning_workspace, metric: :members, current: 8, limit: 10)
        .deliver(user)

      invitation = create(:invitation, email: user.email_address)
      WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)

      result = helper.unread_notification_summary(user)
      expect(result[:severity]).to eq(:warning)
    end

    it "defaults to :info severity when a notifier class is missing" do
      # Simulate orphaned notifier row by stubbing the breakdown directly.
      allow(user).to receive(:unread_notification_breakdown).and_return("DeletedNotifier" => 1)
      expect(Rails.logger).to receive(:warn).with(/Stale notifier class.*DeletedNotifier/)

      result = helper.unread_notification_summary(user)
      expect(result[:severity]).to eq(:info)
      expect(result[:count]).to eq(1)
    end
  end

  describe "#notification_bell_classes" do
    it "returns bg-danger and text-danger-icon for :danger" do
      expect(helper.notification_bell_classes(:danger)).to eq(
        bg: "bg-danger", icon: "text-danger-icon"
      )
    end

    it "returns the info classes for an unknown severity" do
      expect(helper.notification_bell_classes(:unknown)).to eq(
        bg: "bg-info", icon: "text-info-icon"
      )
    end

    {
      warning: { bg: "bg-warning", icon: "text-warning-icon" },
      info:    { bg: "bg-info",    icon: "text-info-icon"    },
      success: { bg: "bg-success", icon: "text-success-icon" }
    }.each do |severity, classes|
      it "returns the expected classes for #{severity.inspect}" do
        expect(helper.notification_bell_classes(severity)).to eq(classes)
      end
    end
  end

  describe "#avatar_button_aria_label" do
    it "returns the plain label when there are no unread notifications" do
      expect(helper.avatar_button_aria_label(user)).to eq("User menu for #{user.full_name}")
    end

    it "includes count and severity phrase when unread > 0" do
      PasswordChangedNotifier.with(record: user).deliver(user)

      label = helper.avatar_button_aria_label(user)
      expect(label).to include("1 unread notification")
      expect(label).to include("a security alert")
    end

    it "uses the plural form when unread > 1" do
      3.times do |i|
        PasswordChangedNotifier.with(record: user, idempotency_key: "k_#{i}").deliver(user)
      end

      label = helper.avatar_button_aria_label(user)
      expect(label).to include("3 unread notifications")
    end
  end
end
