require "rails_helper"

RSpec.describe ActivityLog, "ledger filters" do
  describe "KINDS" do
    # The Kind filter's options come from this list; the sentences come from
    # the locale tree. They must name the same set or an option renders a
    # missing-translation marker (dev) or raises (test).
    it "matches the action families the locale tree knows" do
      expect(described_class::KINDS).to match_array(I18n.t("activity.actions").keys.map(&:to_s))
    end
  end

  describe ".of_kind" do
    it "filters on the stored action prefix" do
      workspace = create(:workspace)
      create(:project, workspace: workspace)

      kinds = described_class.of_kind("project").pluck(:action)
      expect(kinds).to all(start_with("project."))
      expect(kinds).not_to be_empty
      expect(described_class.of_kind("membership").pluck(:action)).to all(start_with("membership."))
    end
  end

  describe ".involving" do
    it "matches rows where the user is the actor, the trackable, or the member of a tracked membership" do
      actor = create(:user)
      subject_user = create(:user)
      workspace = create(:workspace)
      membership = create(:membership, user: subject_user, workspace: workspace)

      session = actor.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.session = session
      begin
        membership.update!(role: Role.system_default!("admin"))
      ensure
        Current.session = nil
      end
      described_class.record_security_event!(action: "user.unlocked", user: subject_user, actor: actor, visibility: "admin")

      expect(described_class.involving(actor).where(actor_id: actor.id)).to exist
      expect(described_class.involving(subject_user).where(trackable: subject_user)).to exist
      expect(described_class.involving(subject_user).where(trackable: membership)).to exist
      expect(described_class.involving(create(:user)).where(trackable: membership)).not_to exist
    end
  end

  describe ".within and .oldest_first" do
    it "bounds by created_at and can reverse the feed order" do
      workspace = create(:workspace)
      old = create(:project, workspace: workspace).activities.first
      # ActivityLog#readonly? blocks instance-level update_column too (it's
      # persisted?-gated, not save-path-specific) — go relation-level, same
      # door the retention sweep job uses (spec/code_smells/activity_log_immutability_spec.rb).
      described_class.where(id: old.id).update_all(created_at: 40.days.ago)
      old.reload
      recent = create(:project, workspace: workspace).activities.first

      scoped = described_class.for_operations_feed.within(30.days.ago, Time.current)
      expect(scoped).to include(recent)
      expect(scoped).not_to include(old)
      expect(described_class.for_operations_feed.oldest_first.first).to eq(old)
    end
  end

  describe ".at_instance_level" do
    it "keeps only rows with no workspace" do
      grantee = create(:user)
      Operatorship.grant!(user: grantee)
      expect(described_class.at_instance_level.pluck(:workspace_id).uniq).to eq([ nil ])
      expect(described_class.at_instance_level.where(action: "operatorship.granted")).to exist
    end
  end
end
