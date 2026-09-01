# frozen_string_literal: true

require "rails_helper"

# The open-link self-join paths have no granter: the joining user is the actor.
# So WorkspaceMemberAddedNotifier must exclude them (nobody is notified about
# their own action) and WorkspaceJoinedNotifier is what orients them instead —
# otherwise a self-joiner reads "Grace joined Ada's Workspace" about herself.
RSpec.describe "Open-link self-join notifications", type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

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

  # `let!` throughout: the User factory's onboarding callback creates a personal
  # workspace + membership per user, and a lazy reference would run that inside
  # the example under test.
  let!(:owner) { create(:user) }
  let!(:joiner) { create(:user) }
  let!(:owner_membership) { create(:membership, user: owner, workspace: workspace, role: owner_role) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  def member_added_recipients
    Noticed::Notification.where(type: "WorkspaceMemberAddedNotifier::Notification").map(&:recipient)
  end

  def joined_notifications_for(user)
    Noticed::Notification.where(recipient: user, type: "WorkspaceJoinedNotifier::Notification")
  end

  # Drain only the Noticed pipeline: a bare drain would also run the user
  # factory's CheckGravatarJob.
  def drain_noticed_jobs
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
  end

  describe "a fresh self-join" do
    it "does not notify the self-joiner about their own join" do
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(member_added_recipients).not_to include(joiner)
    end

    it "still notifies the workspace owners that someone joined" do
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(member_added_recipients).to contain_exactly(owner)
    end

    it "sends the self-joiner exactly one orientation notification" do
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(joiner).count).to eq 1
    end

    it "orients them with the workspace name and points at the workspace" do
      workspace.admit(joiner, role: member_role, self_join: true)
      notification = joined_notifications_for(joiner).sole

      expect(notification.message).to eq(
        I18n.t("notifications.workspace_joined.message", workspace: workspace.name)
      )
      expect(notification.url).to eq(Rails.application.routes.url_helpers.workspace_path(workspace))
    end

    it "does not notify the owners about the joiner's own orientation" do
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(owner).count).to eq 0
    end

    it "sends no email at all — the joiner is already in the app, the owners are digest-only" do
      workspace.admit(joiner, role: member_role, self_join: true)
      drain_noticed_jobs

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "honours the in-app preference for the workspace_activity category" do
      prefs = create(:user_preferences, user: joiner)
      types = prefs.notification_preferences.deep_dup
      types["notification_types"]["workspace_activity"] = false
      prefs.update!(notification_preferences: types)

      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(joiner).count).to eq 0
    end

    # The provenance question: nobody granted an open-link join. Recording the
    # joiner as their own granter would make a self-join indistinguishable from
    # an admin grant in the audit trail.
    it "records no grant provenance on the membership.created activity row" do
      workspace.admit(joiner, role: member_role, self_join: true)
      membership = workspace.memberships.find_by!(user: joiner)
      entry = ActivityLog.where(action: "membership.created", trackable: membership).last

      expect(entry.metadata).not_to have_key("granted_by")
    end
  end

  describe "a removed member self-joining again" do
    let!(:membership) { create(:membership, user: joiner, workspace: workspace, role: member_role) }

    before do
      membership.deactivate!
      Noticed::Notification.delete_all
      Noticed::Event.delete_all
    end

    it "excludes the self-joiner from member-added but still notifies the owners" do
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(member_added_recipients).to contain_exactly(owner)
    end

    it "sends the self-joiner exactly one orientation notification" do
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(joiner).count).to eq 1
    end
  end

  # Not in scope, and it must stay that way: an invitee is not the actor.
  describe "the invited-member path (unchanged)" do
    it "keeps the added user in member-added and raises no orientation notification" do
      workspace.admit(joiner, role: member_role, granted_by: owner)

      expect(member_added_recipients).to contain_exactly(joiner)
      expect(joined_notifications_for(joiner).count).to eq 0
    end
  end
end
