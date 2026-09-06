require "rails_helper"

# The core's examples; each trait's live beside it under spec/models/workspace/.
RSpec.describe Workspace, type: :model do
  describe "validations" do
    it "requires a name" do
      workspace = build(:workspace, name: nil)
      expect(workspace).not_to be_valid
      expect(workspace.errors[:name]).to be_present
    end

    it "auto-deduplicates slugs for same name" do
      first = create(:workspace, name: "Acme Corp")
      second = create(:workspace, name: "Acme Corp")
      expect(first.slug).to eq("acme-corp")
      expect(second.slug).to eq("acme-corp-1")
    end

    it "rejects duplicate slugs at validation level" do
      create(:workspace, name: "Acme Corp")
      duplicate = build(:workspace, name: "Different Name")
      duplicate.slug = "acme-corp"
      expect(duplicate).not_to be_valid
    end
  end

  describe "slug generation" do
    it "generates slug from name" do
      workspace = create(:workspace, name: "Acme Corp")
      expect(workspace.slug).to eq("acme-corp")
    end

    it "uses slug for to_param" do
      workspace = create(:workspace, name: "Acme Corp")
      expect(workspace.to_param).to eq("acme-corp")
    end

    it "generates a fallback slug for non-Latin names" do
      workspace = create(:workspace, name: "日本語の名前")
      expect(workspace.slug).to be_present
      expect(workspace.slug).not_to be_blank
    end
  end

  describe "plan enum" do
    it "defaults to free" do
      workspace = Workspace.new
      expect(workspace.plan).to eq("free")
    end

    it "supports pro and enterprise" do
      expect(build(:workspace, plan: "pro")).to be_valid
      expect(build(:workspace, plan: "enterprise")).to be_valid
    end
  end

  describe "settings defaults" do
    it "defaults max_members to 5" do
      expect(Workspace.new.max_members).to eq(5)
    end

    it "defaults max_projects to 3" do
      expect(Workspace.new.max_projects).to eq(3)
    end
  end

  describe "Discardable" do
    let(:workspace) { create(:workspace) }

    it "can be discarded" do
      workspace.discard!
      expect(workspace).to be_discarded
    end

    it "is excluded from kept scope when discarded" do
      workspace.discard!
      expect(Workspace.kept).not_to include(workspace)
    end

    it "can be undiscarded" do
      workspace.discard!
      workspace.undiscard!
      expect(workspace).not_to be_discarded
    end
  end

  describe "#effective_roles" do
    it "returns system defaults and workspace-specific roles" do
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true }
      end
      workspace = create(:workspace)
      custom_role = Role.create!(name: "Custom", slug: "custom", workspace: workspace)
      roles = workspace.effective_roles
      expect(roles).to include(owner_role)
      expect(roles).to include(custom_role)
    end
  end

  describe "#owners" do
    let(:workspace) { create(:workspace) }
    let(:owner_role) do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
    end
    let(:member_role) do
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end

    it "returns all kept users with owner role for the workspace" do
      owner_a = create(:user)
      owner_b = create(:user)
      member  = create(:user)
      create(:membership, user: owner_a, workspace: workspace, role: owner_role)
      create(:membership, user: owner_b, workspace: workspace, role: owner_role)
      create(:membership, user: member,  workspace: workspace, role: member_role)

      expect(workspace.owners).to match_array([ owner_a, owner_b ])
    end

    it "excludes discarded owner memberships" do
      owner_a = create(:user)
      owner_b = create(:user)
      create(:membership, user: owner_a, workspace: workspace, role: owner_role)
      m2 = create(:membership, user: owner_b, workspace: workspace, role: owner_role)
      m2.discard!

      expect(workspace.owners).to match_array([ owner_a ])
    end

    it "returns an empty collection when the workspace has no owner-role memberships" do
      member = create(:user)
      create(:membership, user: member, workspace: workspace, role: member_role)
      expect(workspace.owners).to be_empty
    end

    it "returns fresh data even when a stale association is loaded" do
      first = create(:membership, user: create(:user), workspace: workspace, role: owner_role)
      second = create(:membership, user: create(:user), workspace: workspace, role: owner_role)
      workspace.memberships.load
      Membership.find(second.id).discard!

      expect(workspace.owners).to contain_exactly(first.user)
    end
  end

  describe "cascade discard" do
    it "cascades discard to projects" do
      workspace = create(:workspace)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: user)

      workspace.discard!
      expect(project.reload).to be_discarded
    end
  end

  describe "name length" do
    it "limits name to 255 characters" do
      workspace = build(:workspace, name: "a" * 256)
      expect(workspace).not_to be_valid
    end
  end

  describe "max_members and max_projects validation" do
    it "requires max_members to be positive" do
      workspace = build(:workspace, max_members: 0)
      expect(workspace).not_to be_valid
    end

    it "requires max_projects to be positive" do
      workspace = build(:workspace, max_projects: 0)
      expect(workspace).not_to be_valid
    end
  end

  describe "join_policy" do
    it "defaults to 'invite'" do
      workspace = create(:workspace)
      expect(workspace.join_policy).to eq("invite")
      expect(workspace).to be_invite
    end

    it "can be set to 'open_link' when the instance permits it" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      workspace = build(:workspace, join_policy: "open_link", personal: false)
      expect(workspace).to be_valid
      expect(workspace).to be_open_link
    end
  end

  describe "personal-workspace hard guard validation" do
    it "rejects join_policy 'open_link' on a personal workspace" do
      workspace = build(:workspace, personal: true, join_policy: "open_link")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:join_policy]).to be_present
    end

    it "permits join_policy 'invite' on a personal workspace" do
      workspace = build(:workspace, personal: true, join_policy: "invite")
      expect(workspace).to be_valid
    end
  end

  describe "instance allowlist validation" do
    it "rejects setting join_policy to a strategy the instance doesn't permit" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      workspace = build(:workspace, personal: false, join_policy: "open_link")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:join_policy]).to include(/not permitted/i)
    end

    it "permits setting join_policy to a strategy in the allowlist" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      workspace = build(:workspace, personal: false, join_policy: "open_link")
      expect(workspace).to be_valid
    end
  end

  describe "typed admission errors" do
    it "are standalone StandardErrors, not ActiveRecord::RecordInvalid subclasses" do
      [ Workspace::AlreadyMember, Workspace::AtCapacity, Workspace::NotAdmittableError ].each do |klass|
        expect(klass.ancestors).to include(StandardError)
        expect(klass.ancestors).not_to include(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe "#create_project" do
    let(:workspace) { create(:workspace, personal: false) }
    let(:creator) { create(:user) }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      }
    }

    before { workspace.memberships.create!(user: creator, role: member_role) }

    it "creates the project and its creator membership atomically" do
      project = nil
      expect {
        project = workspace.create_project({ name: "Atlas" }, creator: creator)
      }.to change(workspace.projects, :count).by(1)

      expect(project).to be_persisted
      expect(project.created_by).to eq(creator)
      expect(project.project_memberships.find_by!(user: creator).role).to eq("creator")
    end

    it "returns the unpersisted project with errors when attributes are invalid" do
      project = nil
      expect {
        project = workspace.create_project({ name: "" }, creator: creator)
      }.not_to change(workspace.projects, :count)

      expect(project).not_to be_persisted
      expect(project.errors[:name]).to be_present
      expect(ProjectMembership.count).to eq(0)
    end

    it "rolls back the project INSERT when the creator membership cannot be created" do
      outsider = create(:user)

      expect {
        expect {
          workspace.create_project({ name: "Atlas" }, creator: outsider)
        }.to raise_error(ActiveRecord::RecordInvalid)
      }.not_to change(workspace.projects, :count)
    end

    it "raises SuspendedError on a suspended workspace and creates nothing" do
      workspace.suspend!

      expect {
        expect {
          workspace.create_project({ name: "Atlas" }, creator: creator)
        }.to raise_error(Suspendable::SuspendedError)
      }.not_to change(workspace.projects, :count)
    end

    # #688 decision pins — the lifecycle semantics are deliberate, not gaps.

    it "accepts new projects in an ARCHIVED workspace (archive stops new PEOPLE; existing work continues)" do
      workspace.archive!

      project = workspace.create_project({ name: "Atlas" }, creator: creator)

      expect(project).to be_persisted
    end

    it "still creates model-level under a DISCARDED workspace (HTTP is guarded by workspaces.kept; the model deliberately is not)" do
      workspace.discard!

      project = workspace.create_project({ name: "Atlas" }, creator: creator)

      expect(project).to be_persisted
      expect(project.discarded_at).to be_nil
    end

    it "discloses suspension (SuspendedError) where #admit deliberately does not (NotAdmittableError)" do
      workspace.suspend!

      expect { workspace.create_project({ name: "Atlas" }, creator: creator) }
        .to raise_error(Suspendable::SuspendedError)
      expect { workspace.admit(create(:user), role: member_role) }
        .to raise_error(Workspace::NotAdmittableError)
    end

    it "works in a personal workspace" do
      personal = create(:workspace, personal: true)
      personal.memberships.create!(user: creator, role: member_role)

      project = personal.create_project({ name: "Atlas" }, creator: creator)

      expect(project).to be_persisted
    end

    it "returns the unpersisted project with errors when creator is nil (no half-written state)" do
      project = nil
      expect {
        project = workspace.create_project({ name: "Atlas" }, creator: nil)
      }.not_to change(workspace.projects, :count)

      expect(project).not_to be_persisted
      expect(project.errors[:created_by]).to be_present
    end

    describe "capacity boundary" do
      let(:workspace) { create(:workspace, personal: false, max_projects: 2) }

      it "creates at one below max, refuses AT max, and a discard frees the slot" do
        workspace.create_project({ name: "One" }, creator: creator)
        at_one_below = workspace.create_project({ name: "Two" }, creator: creator)
        expect(at_one_below).to be_persisted

        at_max = workspace.create_project({ name: "Three" }, creator: creator)
        expect(at_max).not_to be_persisted
        expect(at_max.errors[:base]).to be_present

        at_one_below.discard!
        freed = workspace.create_project({ name: "Four" }, creator: creator)
        expect(freed).to be_persisted
      end
    end
  end

  # #676: workspace INSERT + owner membership commit or roll back TOGETHER —
  # the two-write controller shape could strand a committed, ownerless
  # workspace (no membership → unreachable and undeletable through the UI)
  # when the owner-role lookup raised after the commit.
  describe ".create_owned" do
    let(:user) { create(:user) }

    it "creates the workspace with its owner membership" do
      workspace = Workspace.create_owned({ name: "Acme" }, owner: user)

      expect(workspace).to be_persisted
      membership = workspace.memberships.sole
      expect(membership.user).to eq(user)
      expect(membership.role.slug).to eq("owner")
    end

    it "resolves the owner role through the self-healing Role.system_default!, not find_by!" do
      allow(Role).to receive(:system_default!).and_call_original

      Workspace.create_owned({ name: "Acme" }, owner: user)

      expect(Role).to have_received(:system_default!).with("owner").at_least(:once)
    end

    it "rolls back the workspace INSERT when the owner membership cannot be created" do
      allow(Role).to receive(:system_default!).and_raise(ActiveRecord::RecordNotFound)

      expect {
        expect { Workspace.create_owned({ name: "Acme" }, owner: user) }
          .to raise_error(ActiveRecord::RecordNotFound)
      }.not_to change(Workspace, :count)
    end

    it "returns the unsaved workspace with errors on validation failure (form re-render contract)" do
      workspace = Workspace.create_owned({ name: nil }, owner: user)

      expect(workspace).not_to be_persisted
      expect(workspace.errors[:name]).to be_present
    end
  end
  # #921. Every tracked write in a workspace leaves an activity_logs row
  # pointing at it, and the FK refuses the DELETE. Before this, the only
  # workspaces that could be hard-destroyed were ones nobody had ever done
  # anything in — and "Delete permanently" is a user-facing action.
  describe "hard destroy with an audit trail" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }

    # Trackable reads Current for the actor and the workspace; set both the way
    # the request cycle does, then put them back.
    def with_current(user, workspace)
      Current.session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.workspace = workspace
      yield
    ensure
      Current.session = nil
      Current.workspace = nil
    end

    it "destroys the workspace's own activity trail with it" do
      with_current(user, workspace) { create(:membership, user: user, workspace: workspace) }
      expect(ActivityLog.for_workspace(workspace)).to be_any

      expect { workspace.destroy! }.not_to raise_error
      expect(ActivityLog.where(workspace_id: workspace.id)).to be_empty
    end

    # The retention floor's rows are written by ActivityLog.record_security_event!,
    # which hardcodes `workspace_id: nil` and is the single writer for every
    # SECURITY_ACTIONS row in both tiers. So no security row is workspace-scoped
    # and a workspace destroy cannot reach one. This pins that, because the day
    # a security row gains a workspace_id is the day `dependent: :destroy`
    # starts eating credential evidence silently.
    it "leaves account-security rows alone, since none of them are workspace-scoped" do
      ActivityLog.record_security_event!(action: "user.password_changed", user: user)
      with_current(user, workspace) { create(:membership, user: user, workspace: workspace) }

      expect { workspace.destroy! }.not_to raise_error
      expect(ActivityLog.where(action: "user.password_changed").count).to eq(1)
    end
  end
end
