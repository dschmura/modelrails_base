require "rails_helper"

RSpec.describe MembershipPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    let(:other_membership) { create(:membership, workspace: workspace) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "allows update" do
      expect(described_class.new(user, other_membership).update?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(user, other_membership).destroy?).to be true
    end

    it "denies destroying self" do
      own_membership = workspace.memberships.kept.find_by(user: user)
      expect(described_class.new(user, own_membership).destroy?).to be false
    end

    it "allows reactivate" do
      expect(described_class.new(user, other_membership).reactivate?).to be true
    end

    it "allows transfer_ownership" do
      expect(described_class.new(user, other_membership).transfer_ownership?).to be true
    end
  end

  describe "for member" do
    let(:user) { create(:user) }
    let(:other_membership) { create(:membership, workspace: workspace) }
    before { create(:membership, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "denies update" do
      expect(described_class.new(user, other_membership).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, other_membership).destroy?).to be false
    end

    it "denies transfer_ownership" do
      expect(described_class.new(user, other_membership).transfer_ownership?).to be false
    end
  end

  describe "#destroy? — admin deactivates someone else" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let!(:admin_membership) { create(:membership, :admin, user: user, workspace: workspace) }
    let(:record) { create(:membership, user: other_user, workspace: workspace) }
    subject(:policy) { described_class.new(user, record) }

    it "permits admin to deactivate another member" do
      expect(policy.destroy?).to be(true)
    end

    it "denies when the workspace is discarded" do
      workspace.discard!
      record.reload
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#destroy? — user leaves own membership" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:record) { create(:membership, user: user, workspace: workspace) }
    let!(:owner_membership_other) { create(:membership, :owner, user: other_user, workspace: workspace) }
    subject(:policy) { described_class.new(user, record) }

    it "permits leaving when not last owner and not personal workspace" do
      expect(policy.destroy?).to be(true)
    end

    it "denies leaving the user's personal workspace" do
      user.update!(personal_workspace_id: workspace.id)
      expect(policy.destroy?).to be(false)
    end

    it "denies leaving when the user is the last owner" do
      owner_membership_other.discard!
      record.update!(role: Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" })
      expect(policy.destroy?).to be(false)
    end

    it "denies when the workspace is discarded" do
      workspace.discard!
      record.reload
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#destroy? — non-member" do
    let(:user) { create(:user) }
    let(:actor) { create(:user) }
    let(:record) { create(:membership, user: user, workspace: workspace) }
    subject(:policy) { described_class.new(actor, record) }

    it "denies non-members" do
      expect(policy.destroy?).to be(false)
    end
  end
end
