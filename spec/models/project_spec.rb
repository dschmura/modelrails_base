require "rails_helper"

RSpec.describe Project, type: :model do
  describe "validations" do
    it "requires a name" do
      project = build(:project, name: nil)
      expect(project).not_to be_valid
    end

    it "requires a workspace" do
      project = build(:project, workspace: nil)
      expect(project).not_to be_valid
    end

    it "requires a created_by user" do
      project = build(:project, created_by: nil)
      expect(project).not_to be_valid
    end
  end

  describe "slug generation" do
    it "generates slug from name" do
      project = create(:project, name: "My Project")
      expect(project.slug).to eq("my-project")
    end

    it "auto-deduplicates slugs within workspace" do
      workspace = create(:workspace)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      first = create(:project, name: "Alpha", workspace: workspace, created_by: user)
      second = create(:project, name: "Alpha", workspace: workspace, created_by: user)
      expect(first.slug).to eq("alpha")
      expect(second.slug).to eq("alpha-1")
    end

    it "allows same slug in different workspaces" do
      first = create(:project, name: "Alpha")
      second = create(:project, name: "Alpha")
      expect(first.slug).to eq("alpha")
      expect(second.slug).to eq("alpha")
    end

    it "uses slug for to_param" do
      project = create(:project, name: "My Project")
      expect(project.to_param).to eq("my-project")
    end

    describe "slug generation for non-Latin names" do
      it "generates a fallback slug" do
        workspace = create(:workspace)
        user = create(:user)
        create(:membership, user: user, workspace: workspace)
        project = create(:project, name: "日本語のプロジェクト", workspace: workspace, created_by: user)
        expect(project.slug).to be_present
        expect(project.slug).not_to be_blank
      end
    end
  end

  describe "Discardable" do
    let(:project) { create(:project) }

    it "can be discarded" do
      project.discard!
      expect(project).to be_discarded
    end

    it "is excluded from kept scope" do
      project.discard!
      expect(Project.kept).not_to include(project)
    end
  end

  describe "initials" do
    it "generates initials from name" do
      project = build(:project, name: "Design Sprint")
      expect(project.initials).to eq("DS")
    end
  end

  describe "name length" do
    it "limits name to 255 characters" do
      project = build(:project, name: "a" * 256)
      expect(project).not_to be_valid
    end
  end

  describe "max_projects enforcement" do
    it "validates workspace has capacity" do
      workspace = create(:workspace, max_projects: 1)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      create(:project, workspace: workspace, created_by: user)
      second = build(:project, workspace: workspace, created_by: user)
      expect(second).not_to be_valid
      expect(second.errors[:base]).to be_present
    end

    it "acquires a lock on the workspace during capacity check" do
      workspace = create(:workspace, max_projects: 2)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      project = build(:project, workspace: workspace, created_by: user)
      expect(workspace).to receive(:lock!).and_call_original
      project.save
    end
  end

  describe "tool enablement" do
    it "returns false and empty tools list on an unsaved project (nil enabled_tools)" do
      project = build(:project)
      expect(project.tool_enabled?(:docs)).to be(false)
      expect(project.tools).to eq([])
    end

    it "defaults a new project's enabled_tools to the registry defaults" do
      project = create(:project)
      expect(project.enabled_tools).to eq(ProjectTools::Registry.default_keys)
      expect(project.tool_enabled?(:docs)).to be(true)
    end

    it "does not override an explicitly-set enabled_tools" do
      project = create(:project, enabled_tools: [])
      expect(project.enabled_tools).to eq([])
      expect(project.tool_enabled?(:docs)).to be(false)
    end

    it "#tools returns implemented + enabled registry tools" do
      project = create(:project)
      expect(project.tools.map(&:key)).to eq([ :docs ])

      project.update!(enabled_tools: [])
      expect(project.tools).to be_empty
    end
  end

  describe "clientside access" do
    it "#client? is true for a user with a kept client access" do
      access = create(:client_access)
      expect(access.project.client?(access.user)).to be(true)
    end

    it "#client? is false for a user without client access" do
      project = create(:project, clientside_enabled: true)
      expect(project.client?(create(:user))).to be(false)
    end

    it "#client? is false for a user with a discarded client access" do
      access = create(:client_access)
      access.discard!
      expect(access.project.client?(access.user)).to be(false)
    end
  end

  describe "factory" do
    # #688: the factory mirrors Workspace#create_project's invariant — a
    # project always carries its creator's project_membership.
    it "creates the creator's project membership (the post-#660 production invariant)" do
      project = create(:project)
      expect(project.project_memberships.sole.user).to eq(project.created_by)
      expect(project.project_memberships.sole.role).to eq("creator")
    end

    it "ensures created_by is a workspace member (creators are members in production)" do
      workspace = create(:workspace)
      project = create(:project, workspace: workspace)
      expect(workspace.memberships.kept.exists?(user: project.created_by)).to be(true)
    end

    it "does not duplicate memberships when created_by is already a member" do
      workspace = create(:workspace)
      member = create(:user)
      create(:membership, user: member, workspace: workspace)

      expect { create(:project, workspace: workspace, created_by: member) }
        .not_to change(workspace.memberships, :count)
    end
  end

  describe "#client_visible_resources" do
    it "returns only kept, published, shared resources" do
      project = create(:project)
      visible = create(:resource, project: project, status: "published", shared_with_client: true)
      create(:resource, project: project, status: "draft", shared_with_client: true)
      create(:resource, project: project, status: "published", shared_with_client: false)
      expect(project.client_visible_resources).to eq([ visible ])
    end
  end

  # SEC-8: logo was the one attachment among five without validations.
  describe "logo attachment" do
    let(:project) { create(:project) }

    it "rejects non-image content types" do
      project.logo.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(project).not_to be_valid
      expect(project.errors[:logo]).to be_present
    end

    it "rejects files over 5MB" do
      project.logo.attach(io: StringIO.new("x" * 6.megabytes), filename: "big.png", content_type: "image/png")
      expect(project).not_to be_valid
      expect(project.errors[:logo]).to be_present
    end

    it "accepts a valid image" do
      project.logo.attach(io: StringIO.new("fake"), filename: "logo.png", content_type: "image/png")
      project.valid?
      expect(project.errors[:logo]).to be_empty
    end
  end
end
