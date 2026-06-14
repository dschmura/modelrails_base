require "rails_helper"

RSpec.describe ResourcePolicy do
  let(:workspace) { create(:workspace) }
  let(:creator_user) { create(:user) }
  let(:editor_user) { create(:user) }
  let(:viewer_user) { create(:user) }
  let(:non_member) { create(:user) }
  let(:project) { create(:project, workspace: workspace, created_by: creator_user) }
  let(:resource) { create(:resource, project: project, created_by: editor_user) }

  before do
    Current.workspace = workspace
    create(:membership, :owner, user: creator_user, workspace: workspace)
    create(:membership, user: editor_user, workspace: workspace)
    create(:membership, user: viewer_user, workspace: workspace)
    create(:membership, user: non_member, workspace: workspace)
    create(:project_membership, :creator, project: project, user: creator_user)
    create(:project_membership, project: project, user: editor_user)
    create(:project_membership, :viewer, project: project, user: viewer_user)
  end

  describe "for editor (resource creator)" do
    it "allows show" do
      expect(described_class.new(editor_user, resource).show?).to be true
    end

    it "allows create" do
      expect(described_class.new(editor_user, resource).create?).to be true
    end

    it "allows update own resource" do
      expect(described_class.new(editor_user, resource).update?).to be true
    end

    it "allows destroy own resource" do
      expect(described_class.new(editor_user, resource).destroy?).to be true
    end

    it "allows reposition" do
      expect(described_class.new(editor_user, resource).reposition?).to be true
    end
  end

  describe "for viewer" do
    it "allows show" do
      expect(described_class.new(viewer_user, resource).show?).to be true
    end

    it "denies create" do
      expect(described_class.new(viewer_user, resource).create?).to be false
    end

    it "denies update" do
      expect(described_class.new(viewer_user, resource).update?).to be false
    end

    it "denies reposition" do
      expect(described_class.new(viewer_user, resource).reposition?).to be false
    end
  end

  describe "for project creator" do
    it "allows update anyone's resource" do
      expect(described_class.new(creator_user, resource).update?).to be true
    end

    it "allows destroy anyone's resource" do
      expect(described_class.new(creator_user, resource).destroy?).to be true
    end
  end

  describe "for non-project-member" do
    it "denies show" do
      expect(described_class.new(non_member, resource).show?).to be false
    end
  end

  describe "workspace owner can destroy" do
    let(:ws_owner) { create(:user) }
    before { create(:membership, :owner, user: ws_owner, workspace: workspace) }

    it "allows destroy via manage_workspace" do
      expect(described_class.new(ws_owner, resource).destroy?).to be true
    end
  end

  # project_membership resolves the project from the record when it carries one,
  # else from Current.project. index?/create? authorize against the class (no
  # instance), which exercises the Current.project fallback branch.
  describe "when the record is the class (Current.project fallback)" do
    before { Current.project = project }

    it "allows a project member to index" do
      expect(described_class.new(editor_user, Resource).index?).to be true
    end

    it "denies a workspace member who is not on the project" do
      expect(described_class.new(non_member, Resource).index?).to be false
    end
  end
end
