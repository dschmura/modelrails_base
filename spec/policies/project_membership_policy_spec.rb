require "rails_helper"

RSpec.describe ProjectMembershipPolicy do
  let(:workspace) { create(:workspace) }
  let(:creator_user) { create(:user) }
  let(:editor_user) { create(:user) }
  let(:project) { create(:project, workspace: workspace, created_by: creator_user) }

  before do
    Current.workspace = workspace
    create(:membership, :owner, user: creator_user, workspace: workspace)
    create(:membership, user: editor_user, workspace: workspace)
    create(:project_membership, :creator, project: project, user: creator_user)
  end

  let!(:editor_pm) { create(:project_membership, project: project, user: editor_user) }

  describe "for project creator" do
    it "allows create" do
      expect(described_class.new(creator_user, editor_pm).create?).to be true
    end

    it "allows update on editor" do
      expect(described_class.new(creator_user, editor_pm).update?).to be true
    end

    it "allows destroy on editor" do
      expect(described_class.new(creator_user, editor_pm).destroy?).to be true
    end

    it "denies destroying creator membership" do
      creator_pm = project.project_memberships.find_by(user: creator_user)
      expect(described_class.new(creator_user, creator_pm).destroy?).to be false
    end
  end

  describe "for project editor" do
    it "denies create" do
      expect(described_class.new(editor_user, editor_pm).create?).to be false
    end

    it "allows toggle_pin on own membership" do
      expect(described_class.new(editor_user, editor_pm).toggle_pin?).to be true
    end

    it "denies toggle_pin on others' membership" do
      creator_pm = project.project_memberships.find_by(user: creator_user)
      expect(described_class.new(editor_user, creator_pm).toggle_pin?).to be false
    end
  end

  # The `project` resolver has two branches: read the record's own project when
  # the record carries one, else fall back to Current.project. index? authorizes
  # against the class (no instance), so it exercises the fallback branch.
  describe "index? when the record is the class (Current.project fallback)" do
    before { Current.project = project }

    it "allows a project member" do
      expect(described_class.new(creator_user, ProjectMembership).index?).to be true
    end

    it "denies a workspace member who is not on the project" do
      outsider = create(:user)
      create(:membership, user: outsider, workspace: workspace)
      expect(described_class.new(outsider, ProjectMembership).index?).to be false
    end
  end
end
