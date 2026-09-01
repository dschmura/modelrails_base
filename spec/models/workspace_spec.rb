require "rails_helper"

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

  describe "logo" do
    it "generates initials from name" do
      workspace = build(:workspace, name: "Acme Corp")
      expect(workspace.initials).to eq("AC")
    end

    it "limits initials to 2 characters" do
      workspace = build(:workspace, name: "The Big Company Name")
      expect(workspace.initials).to eq("TB")
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

  describe "logo attachment" do
    let(:workspace) { create(:workspace) }

    # HEIC/HEIF included: it is the iPhone camera default, so rejecting it
    # bounces the most common source of a logo upload. Safe to accept — the
    # active_storage initializer records that both load and transform under
    # Vips.block_untrusted(true) after CVE-2026-66066, and Rails converts the
    # variant to PNG automatically because they are not web_image_content_types.
    it "accepts valid image content types" do
      %w[image/png image/jpeg image/gif image/webp image/heic image/heif].each do |content_type|
        workspace.logo.attach(io: StringIO.new("fake"), filename: "test.png", content_type: content_type)
        workspace.valid?
        expect(workspace.errors[:logo]).to be_empty, "Expected #{content_type} to be valid"
      end
    end

    it "rejects non-image content types" do
      workspace.logo.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo]).to be_present
    end

    it "rejects files over 5MB" do
      workspace.logo.attach(io: StringIO.new("x" * 6.megabytes), filename: "big.png", content_type: "image/png")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo]).to be_present
    end
  end

  describe "logo_original attachment" do
    let(:workspace) { create(:workspace) }

    it "rejects non-image content types" do
      workspace.logo_original.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo_original]).to be_present
    end

    it "rejects files over 10MB (original can be larger than cropped)" do
      workspace.logo_original.attach(io: StringIO.new("x" * 11.megabytes), filename: "big.png", content_type: "image/png")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo_original]).to be_present
    end
  end

  describe "logo_source" do
    it "defaults to initials" do
      workspace = create(:workspace)
      expect(workspace.logo_source).to eq("initials")
    end

    it "validates inclusion in upload and initials" do
      workspace = build(:workspace, logo_source: "upload")
      expect(workspace).to be_valid

      workspace.logo_source = "invalid"
      expect(workspace).not_to be_valid
    end
  end

  describe "#available_logo_sources" do
    it "returns upload and initials" do
      workspace = build(:workspace)
      expect(workspace.available_logo_sources).to eq(%w[upload initials])
    end
  end

  describe "primary_color (integer hue)" do
    it "defaults to 210 (blue)" do
      workspace = create(:workspace)
      expect(workspace.primary_color).to eq(210)
    end

    it "validates inclusion in 0..360" do
      workspace = build(:workspace, primary_color: 180)
      expect(workspace).to be_valid

      workspace.primary_color = -1
      expect(workspace).not_to be_valid

      workspace.primary_color = 361
      expect(workspace).not_to be_valid
    end

    it "allows nil" do
      workspace = build(:workspace, primary_color: nil)
      expect(workspace).to be_valid
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

  describe "#open_join?" do
    before { allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link]) }

    it "is true for an org workspace with join_policy 'open_link' when instance permits it" do
      workspace = build(:workspace, join_policy: "open_link", personal: false)
      expect(workspace).to be_open_join
    end

    it "is false on a personal workspace, regardless of policy (hard guard)" do
      # Build without validation so we can simulate a malformed row reaching the predicate.
      workspace = build(:workspace, personal: true)
      workspace.join_policy = "open_link"
      expect(workspace).not_to be_open_join
    end

    it "is false when the instance allowlist excludes :open_link" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      workspace = build(:workspace, personal: false)
      workspace.join_policy = "open_link"
      expect(workspace).not_to be_open_join
    end

    it "is false for invite policy" do
      workspace = build(:workspace, join_policy: "invite", personal: false)
      expect(workspace).not_to be_open_join
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

  # Single membership-grant entry point — extracted from Invitation so the
  # open-link self-join path can share the same lock + capacity + discarded-
  # reactivation + role-reconciliation logic.
  describe "#accepting_open_joins?" do
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }

    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    it "is true when the join policy is open and the workspace is admittable" do
      expect(workspace.accepting_open_joins?).to be(true)
    end

    it "is false when the join policy is not open" do
      workspace.update!(join_policy: "invite")
      expect(workspace.accepting_open_joins?).to be(false)
    end

    it "is false when the workspace is not admittable (archived/suspended)" do
      workspace.archive!
      expect(workspace.accepting_open_joins?).to be(false)
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

  describe "#admit" do
    let(:workspace) { create(:workspace, max_members: 3, personal: false) }
    let(:user) { create(:user) }
    let!(:owner_role) {
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
      }
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      }
    }

    it "creates a membership for a new user at the specified role" do
      expect {
        workspace.admit(user, role: member_role)
      }.to change(workspace.memberships, :count).by(1)

      expect(workspace.memberships.find_by!(user: user).role).to eq(member_role)
    end

    it "reactivates a discarded membership without overwriting its role" do
      # Seed the workspace with an Owner so deactivating doesn't violate
      # "must keep at least one owner" rules — and create a regular member
      # to deactivate as the test subject.
      other_owner = create(:user)
      workspace.memberships.create!(user: other_owner, role: owner_role)
      discarded = workspace.memberships.create!(user: user, role: member_role)
      discarded.deactivate!

      expect {
        workspace.admit(user, role: member_role)
      }.not_to change(workspace.memberships, :count)

      expect(discarded.reload).not_to be_discarded
    end

    it "reactivates a discarded membership with on_existing: :adopt (no granted_by rewrite, same as :raise)" do
      other_owner = create(:user)
      workspace.memberships.create!(user: other_owner, role: owner_role)
      discarded = workspace.memberships.create!(user: user, role: member_role)
      discarded.deactivate!

      result = nil
      expect {
        result = workspace.admit(user, role: member_role, granted_by: other_owner, on_existing: :adopt)
      }.not_to change(workspace.memberships, :count)

      expect(result).to eq(discarded)
      expect(discarded.reload).not_to be_discarded
      # Reactivation preserves the original grant's provenance: no new
      # `membership.created` audit row, and admit never mutates the caller's
      # instance. The granted_by admit sets on its OWN copy of the row is
      # transient notifier provenance (actor exclusion), not a rewrite.
      expect(discarded.granted_by).to be_nil
    end

    it "raises AtCapacity when the workspace is at capacity" do
      # Fill the workspace to max_members.
      workspace.update!(max_members: 1)
      workspace.memberships.create!(user: create(:user), role: owner_role)

      expect {
        workspace.admit(user, role: member_role)
      }.to raise_error(Workspace::AtCapacity)
    end

    context "when user is already a kept member" do
      before { workspace.memberships.create!(user: user, role: member_role) }

      it "raises AlreadyMember under :personal (duplicate-accept error)" do
        expect {
          workspace.admit(user, role: owner_role)
        }.to raise_error(Workspace::AlreadyMember)
      end

      it "adopts the existing membership untouched with on_existing: :adopt" do
        existing = workspace.memberships.find_by!(user: user)

        result = nil
        expect {
          result = workspace.admit(user, role: owner_role, on_existing: :adopt)
        }.not_to change(workspace.memberships, :count)

        expect(result).to eq(existing)
        # Adopt tolerates the member as-is: no role overwrite, even though the
        # admit call asked for a different role.
        expect(existing.reload.role).to eq(member_role)
      end

      context "under :shared posture" do
        before do
          allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
          allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
        end

        it "updates the role when it differs (placeholder reconciliation)" do
          expect {
            workspace.admit(user, role: owner_role)
          }.not_to raise_error

          expect(workspace.memberships.find_by!(user: user).role).to eq(owner_role)
        end

        it "no-ops when the role matches" do
          expect { workspace.admit(user, role: member_role) }.not_to raise_error
        end
      end
    end

    # Rails runs a row's commit callbacks on the LAST instance of it saved in
    # the transaction (run_commit_callbacks_on_first_saved_instances_in_transaction
    # is false), so the reconciling instance — not the one that did the INSERT —
    # is what the actor rule reads. The interleaving is real, not theoretical:
    # Signupable#commit_signup_atomically runs `user.save!` (→ User#onboard_workspace
    # → the :shared placeholder membership) and PendingClaims#claim! (→
    # Invitation#accept! → #admit) inside ONE transaction.
    context "when a second instance of the row saves in the same transaction" do
      # NOTE: users are created before `shared?` is stubbed on purpose — the
      # stub is scoped to admit's reconcile branch and must not reach
      # User#onboard_workspace, which reads TenancyConfig.onboarding.
      let!(:owner_a) { create(:user) }
      let!(:owner_b) { create(:user) }
      let!(:owner_a_membership) { workspace.memberships.create!(user: owner_a, role: owner_role) }
      let!(:owner_b_membership) { workspace.memberships.create!(user: owner_b, role: owner_role) }

      before do
        allow(TenancyConfig).to receive(:shared?).and_return(true)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
      end

      def recipients_of(notifier)
        Noticed::Notification.where(type: "#{notifier}::Notification").map(&:recipient)
      end

      it "keeps the granter out of the member-added fan-out" do
        ActiveRecord::Base.transaction do
          workspace.memberships.create!(user: user, role: member_role, self_join: :onboarding)
          workspace.admit(user, role: owner_role, granted_by: owner_a)
        end

        expect(recipients_of(WorkspaceMemberAddedNotifier)).to contain_exactly(user, owner_b)
      end

      it "keeps a chosen self-join's joiner out of the fan-out and still orients them" do
        ActiveRecord::Base.transaction do
          workspace.memberships.create!(user: user, role: member_role, self_join: :onboarding)
          workspace.admit(user, role: owner_role, self_join: true)
        end

        expect(recipients_of(WorkspaceMemberAddedNotifier)).to contain_exactly(owner_a, owner_b)
        expect(recipients_of(WorkspaceJoinedNotifier)).to contain_exactly(user)
      end

      it "carries the granter onto the instance on_existing: :adopt returns" do
        workspace.memberships.create!(user: user, role: member_role)

        result = workspace.admit(user, role: member_role, granted_by: owner_a, on_existing: :adopt)

        expect(result.granted_by).to eq(owner_a)
      end

      it "carries the self-join marker onto the instance on_existing: :adopt returns" do
        workspace.memberships.create!(user: user, role: member_role)

        result = workspace.admit(user, role: member_role, self_join: true, on_existing: :adopt)

        expect(result.self_join).to be true
      end
    end
  end

  describe "#at_capacity?" do
    it "is true when kept memberships have reached max_members" do
      workspace = create(:workspace, max_members: 1)
      create(:membership, workspace: workspace)

      expect(workspace.at_capacity?).to be true
    end

    it "is false below the limit" do
      workspace = create(:workspace, max_members: 2)
      create(:membership, workspace: workspace)

      expect(workspace.at_capacity?).to be false
    end

    it "does not count discarded memberships" do
      workspace = create(:workspace, max_members: 1)
      create(:membership, workspace: workspace).discard!

      expect(workspace.at_capacity?).to be false
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
end
