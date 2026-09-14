require "rails_helper"

RSpec.describe "Operations policies" do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:member) { create(:user) }
  let(:workspace) { create(:workspace) }

  describe Operations::WorkspacePolicy do
    it "opens index/show/new/create/suspend/unsuspend to operators only" do
      policy = described_class.new(operator, workspace)
      expect(policy.index?).to be true
      expect(policy.show?).to be true
      expect(policy.new?).to be true
      expect(policy.create?).to be true
      expect(policy.suspend?).to be true
      expect(policy.unsuspend?).to be true

      denied = described_class.new(member, workspace)
      expect(denied.index?).to be false
      expect(denied.show?).to be false
      expect(denied.create?).to be false
      expect(denied.suspend?).to be false
    end

    it "denies a nil user" do
      expect(described_class.new(nil, workspace).index?).to be false
    end

    it "does not read Current.workspace" do
      Current.workspace = nil
      expect(described_class.new(operator, workspace).show?).to be true
    end

    it "does not descend from ApplicationPolicy" do
      expect(described_class.ancestors).not_to include(ApplicationPolicy)
    end
  end

  describe Operations::UserPolicy do
    it "opens index/show/unlock/suspend to operators only" do
      policy = described_class.new(operator, member)
      expect(policy.index?).to be true
      expect(policy.show?).to be true
      expect(policy.unlock?).to be true
      expect(policy.suspend?).to be true
      expect(described_class.new(member, member).show?).to be false
    end
  end

  describe Operations::ActivityLogPolicy do
    it "opens index to operators only" do
      expect(described_class.new(operator, ActivityLog).index?).to be true
      expect(described_class.new(member, ActivityLog).index?).to be false
    end
  end

  describe Operations::OperatorshipPolicy do
    it "opens index/create/destroy to operators only" do
      expect(described_class.new(operator, Operatorship).index?).to be true
      expect(described_class.new(operator, Operatorship).create?).to be true
      expect(described_class.new(operator, Operatorship.new).destroy?).to be true
      expect(described_class.new(member, Operatorship).create?).to be false
    end
  end
end
