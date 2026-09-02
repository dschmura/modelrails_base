require "rails_helper"

RSpec.describe Membership, type: :model do
  describe "#owner?" do
    it "is true when the role is the owner role" do
      expect(build(:membership, :owner).owner?).to be true
    end

    it "is false for non-owner roles" do
      expect(build(:membership).owner?).to be false
    end

    it "answers role identity only — a discarded owner membership is still owner?" do
      membership = create(:membership, :owner)
      membership.discard!

      expect(membership.owner?).to be true
    end
  end

  # SEC-1: a role change is a privilege event — audit it readably (role slugs,
  # not the mutable role_id FK) and in the admin-only feed.
  describe "role-change audit trail" do
    def with_session(user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.session = session
      Current.workspace = @workspace
      yield
    ensure
      Current.session = nil
      Current.workspace = nil
    end

    it "records the role slugs by value and routes the event to the admin feed" do
      @workspace = create(:workspace)
      actor = create(:user)
      create(:membership, :owner, user: actor, workspace: @workspace)
      target = create(:membership, user: create(:user), workspace: @workspace)

      with_session(actor) do
        target.change_role!(Role.system_default!("admin"))
      end

      log = ActivityLog.where(trackable: target, action: "membership.updated").order(:id).last
      expect(log.metadata["changes"]["role"]).to eq([ "member", "admin" ])
      expect(log.visibility).to eq("admin")
      expect(log.actor).to eq(actor)
    end
  end

  describe "schema" do
    it "has a last_accessed_at datetime column" do
      expect(Membership.columns_hash["last_accessed_at"].sql_type_metadata.type).to eq(:datetime)
    end

    it "has a composite index on [user_id, last_accessed_at]" do
      indexes = ActiveRecord::Base.connection.indexes("memberships")
      index = indexes.find { |i| i.columns == [ "user_id", "last_accessed_at" ] }
      expect(index).to be_present, "Expected composite index on (user_id, last_accessed_at)"
    end
  end

  describe "validations" do
    it "requires a user" do
      membership = build(:membership, user: nil)
      expect(membership).not_to be_valid
    end

    it "requires a workspace" do
      membership = build(:membership, workspace: nil)
      expect(membership).not_to be_valid
    end

    it "requires a role" do
      membership = build(:membership, role: nil)
      expect(membership).not_to be_valid
    end

    it "enforces one membership per user per workspace" do
      membership = create(:membership)
      duplicate = build(:membership, user: membership.user, workspace: membership.workspace)
      expect(duplicate).not_to be_valid
    end

    it "enforces uniqueness at the DATABASE level too (the concurrency backstop)" do
      membership = create(:membership)
      duplicate = build(:membership, user: membership.user, workspace: membership.workspace)

      # Bypass the app-level uniqueness validation on purpose. Under concurrent
      # admits, two transactions can both pass the model validation before
      # either commits — the unique index on (user_id, workspace_id) is what
      # actually prevents a duplicate membership row, making a double-claim of a
      # join-link/invitation token harmless. This guards against the index being
      # dropped and the invariant silently degrading to app-validation-only.
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "Discardable" do
    let(:membership) { create(:membership) }

    it "can be discarded" do
      membership.discard!
      expect(membership).to be_discarded
    end
  end

  describe "associations" do
    let(:membership) { create(:membership) }

    it "belongs to a user" do
      expect(membership.user).to be_a(User)
    end

    it "belongs to a workspace" do
      expect(membership.workspace).to be_a(Workspace)
    end

    it "belongs to a role" do
      expect(membership.role).to be_a(Role)
    end
  end

  describe "role change" do
    let(:membership) { create(:membership) }
    let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }

    it "changes role" do
      membership.change_role!(admin_role)
      expect(membership.reload.role).to eq(admin_role)
    end
  end

  describe "deactivation" do
    let(:workspace) { create(:workspace) }
    let(:membership) { create(:membership, :owner, workspace: workspace) }

    it "deactivates a member" do
      create(:membership, :owner, workspace: workspace)
      membership.deactivate!
      expect(membership.reload).to be_discarded
    end

    it "prevents deactivating the last owner" do
      expect { membership.deactivate! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # Race-safety net for last-owner check. Pre-flight validate_not_last_owner!
    # runs against the workspace snapshot before discard; under concurrency two
    # owner-deactivations can both observe count==2 and proceed, leaving the
    # workspace ownerless. The post-discard invariant re-checks inside the
    # transaction (after our own discard), so a true race trips it.
    it "rolls back the deactivation if it would leave the workspace ownerless" do
      owner_a = create(:membership, :owner, workspace: workspace)
      owner_b = create(:membership, :owner, workspace: workspace)
      owner_a.discard!  # workspace now has 1 kept owner: owner_b

      # Bypass pre-flight to simulate a racer whose validate_not_last_owner!
      # passed against stale state.
      allow(owner_b).to receive(:validate_not_last_owner!)

      expect { owner_b.deactivate! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(owner_b.reload).not_to be_discarded
      expect(
        workspace.memberships.kept.joins(:role).where(roles: { slug: "owner" })
      ).to exist
    end
  end

  describe "reactivation" do
    let(:membership) { create(:membership) }

    it "reactivates a deactivated member" do
      membership.discard!
      membership.reactivate!
      expect(membership.reload).not_to be_discarded
    end

    # Pins the deliberate admission-asymmetry documented on reactivate!: an
    # existing member of an ARCHIVED workspace can still be reactivated, even
    # though Workspace#admit blocks NEW admission into archived workspaces. If a
    # future refactor adds an admittable?/archived? guard to reactivate!, this
    # fails and forces that decision back into the open.
    it "reactivates a member even when the workspace is archived" do
      membership.discard!
      membership.workspace.archive!

      expect { membership.reactivate! }.not_to raise_error
      expect(membership.reload).not_to be_discarded
    end
  end

  # `granted_by` and `self_join` are mutually exclusive: nobody granted a
  # self-join. Before the guard, passing both silently let self_join win the
  # actor selection while granted_by still landed in the membership.created
  # audit row — a row naming a granter for something the same row records as
  # ungranted. Both entry points refuse it.
  describe "exclusive grant provenance" do
    let(:workspace) { create(:workspace, personal: false) }
    let(:granter) { create(:user) }
    let(:member_role) do
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end

    it "refuses a Workspace#admit claiming both a granter and a self-join" do
      expect {
        workspace.admit(create(:user), role: member_role, granted_by: granter, self_join: true)
      }.to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "refuses the same combination on #reactivate!" do
      membership = create(:membership, workspace: workspace, role: member_role)
      membership.discard!

      expect {
        membership.reactivate!(granted_by: granter, self_join: true)
      }.to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "creates nothing when it refuses" do
      expect {
        expect {
          workspace.admit(create(:user), role: member_role, granted_by: granter, self_join: true)
        }.to raise_error(ArgumentError)
      }.not_to change(workspace.memberships, :count)
    end

    it "still accepts either one on its own" do
      expect { workspace.admit(create(:user), role: member_role, granted_by: granter) }.not_to raise_error
      expect { workspace.admit(create(:user), role: member_role, self_join: true) }.not_to raise_error
    end

    # The two entry-point guards only see callers that go through them.
    # User#join_shared_workspace creates a membership directly, and the
    # actor-stance fence is satisfied by EITHER marker — so a site naming both
    # reads as "declared" and reaches the row. The rule belongs on the model,
    # where no construction path can route around it.
    context "as a model invariant" do
      it "refuses both markers on a direct create!, which no entry-point guard sees" do
        expect {
          workspace.memberships.create!(
            user: create(:user), role: member_role, granted_by: granter, self_join: true
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /mutually exclusive/)
      end

      it "creates nothing when the direct create! is refused" do
        expect {
          expect {
            workspace.memberships.create!(
              user: create(:user), role: member_role, granted_by: granter, self_join: true
            )
          }.to raise_error(ActiveRecord::RecordInvalid)
        }.not_to change(workspace.memberships, :count)
      end

      it "refuses a self_join grade outside the declared set" do
        expect {
          workspace.memberships.create!(user: create(:user), role: member_role, self_join: :onboard)
        }.to raise_error(ActiveRecord::RecordInvalid, /self_join/)
      end

      it "accepts every declared grade" do
        [ nil, false, true, :onboarding ].each do |grade|
          membership = build(:membership, workspace: workspace, role: member_role, user: create(:user))
          membership.self_join = grade

          expect(membership).to be_valid, "grade #{grade.inspect} was rejected"
        end
      end
    end

    # chosen_self_join? gates the orientation notice, and it runs in an
    # after_create_commit — i.e. on paths that skipped validation. Asking
    # "is it the chosen grade" (inclusion) rather than "is it anything but
    # :onboarding" (exclusion) means a grade nobody taught it about stays
    # silent instead of mailing someone.
    it "does not treat an unrecognised grade as a chosen self-join" do
      create(:membership, :owner, workspace: workspace)
      joiner = create(:user)
      membership = workspace.memberships.build(user: joiner, role: member_role)
      membership.self_join = :onboard
      membership.save!(validate: false)

      expect(
        Noticed::Notification.where(recipient: joiner,
                                    type: "WorkspaceJoinedNotifier::Notification").count
      ).to eq 0
    end
  end

  describe "max_members enforcement" do
    it "prevents exceeding max_members" do
      # The workspace factory does not auto-create memberships.
      workspace = create(:workspace, max_members: 2)
      create(:membership, :owner, workspace: workspace)
      create(:membership, workspace: workspace)
      third = build(:membership, workspace: workspace)
      expect(third).not_to be_valid
      expect(third.errors[:base]).to be_present
    end

    it "acquires a lock on the workspace during capacity check" do
      workspace = create(:workspace, max_members: 5)
      membership = build(:membership, workspace: workspace)
      expect(workspace).to receive(:lock!).and_call_original
      membership.save
    end

    # Race-safety net: panel review flagged that the pre-flight validator's
    # workspace.lock! is a no-op across SQLite connections (per-connection
    # locking), so two concurrent invitation accepts could both pass count==N
    # and INSERT members N+1 + N+2. The post-create invariant runs inside the
    # create transaction with the row already inserted; SQLite's writer lock
    # serializes INSERTs, so by the time we COUNT we see the actual committed
    # state. Over-capacity → raise → roll back.
    it "rolls back the create when a racing transaction has filled capacity" do
      workspace = create(:workspace, max_members: 2)
      role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      2.times { create(:membership, workspace: workspace) }

      user = create(:user)
      membership = Membership.new(workspace: workspace, user: user, role: role)

      # save!(validate: false) bypasses the pre-flight validator, simulating a
      # racing transaction whose validator passed against stale state. The
      # after_create invariant must catch the violation and roll back.
      expect { membership.save!(validate: false) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Membership.where(workspace: workspace, user: user)).not_to exist
    end
  end

  describe "scopes" do
    let(:workspace) { create(:workspace) }
    let!(:alice_membership) { create(:membership, :owner, workspace: workspace) }
    let!(:bob_membership) { create(:membership, :admin, workspace: workspace) }
    let!(:carol_membership) { create(:membership, workspace: workspace) }

    # Emails are pinned alongside names: .search also matches email_address,
    # and the factory's Faker email can randomly contain another member's
    # first name (e.g. "alice.baker@..."), making the exclusion assertions
    # flake (issue #467).
    before do
      alice_membership.user.update!(first_name: "Alice", last_name: "Anderson", email_address: "alice.anderson@example.test")
      bob_membership.user.update!(first_name: "Bob", last_name: "Baker", email_address: "bob.baker@example.test")
      carol_membership.user.update!(first_name: "Carol", last_name: "Clark", email_address: "carol.clark@example.test")
    end

    describe ".filter_by_role" do
      it "filters by role slug" do
        results = workspace.memberships.filter_by_role("owner")
        expect(results).to include(alice_membership)
        expect(results).not_to include(bob_membership)
      end

      it "returns all when role is blank" do
        expect(workspace.memberships.filter_by_role("")).to match_array(workspace.memberships)
        expect(workspace.memberships.filter_by_role(nil)).to match_array(workspace.memberships)
      end
    end

    describe ".filter_by_status" do
      before { carol_membership.discard! }

      it "filters active members" do
        results = workspace.memberships.filter_by_status("active")
        expect(results).to include(alice_membership, bob_membership)
        expect(results).not_to include(carol_membership)
      end

      it "filters deactivated members" do
        results = workspace.memberships.filter_by_status("deactivated")
        expect(results).to include(carol_membership)
        expect(results).not_to include(alice_membership)
      end

      it "returns all when status is blank" do
        expect(workspace.memberships.filter_by_status("")).to match_array(workspace.memberships)
      end
    end
  end

  # G (SEC-1 follow-up): membership.created previously carried empty metadata —
  # no role, no granter. The grant itself is the privilege event.
  describe "creation audit metadata" do
    it "records the granted role slug" do
      membership = create(:membership, :owner)

      entry = ActivityLog.where(action: "membership.created", trackable: membership).last
      expect(entry).to be_present
      expect(entry.metadata["role"]).to eq("owner")
    end
  end

  describe "ownership transfer" do
    let(:workspace) { create(:workspace) }
    let(:owner_membership) { create(:membership, :owner, workspace: workspace) }
    let(:target_membership) { create(:membership, workspace: workspace) }

    it "promotes the target to owner" do
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      owner_membership.transfer_ownership_to!(target_membership)
      expect(target_membership.reload.role).to eq(owner_role)
    end

    it "demotes the current owner to admin" do
      admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }
      owner_membership.transfer_ownership_to!(target_membership)
      expect(owner_membership.reload.role).to eq(admin_role)
    end

    # G (SEC-1 follow-up): the demote is a callback-skipping CAS update_all
    # (race-safety, by design) — which also skipped Trackable. A privilege
    # demotion must still reach the audit trail, explicitly.
    it "audits the demotion at admin visibility despite the callback-skipping CAS" do
      owner_membership.transfer_ownership_to!(target_membership)

      entry = ActivityLog.where(action: "membership.updated", trackable: owner_membership).last
      expect(entry).to be_present
      expect(entry.visibility).to eq("admin")
      expect(entry.metadata.dig("changes", "role")).to eq([ "owner", "admin" ])
    end

    # Race-safety: panel review flagged that two concurrent transfers from
    # the same owner could leave the workspace with two owners (both target
    # promotions succeed, demote-self is idempotent). Demote must be an
    # atomic conditional update guarded by current role; if a racer already
    # demoted us, abort *before* promoting target.
    it "raises and leaves target unpromoted if current role is no longer owner" do
      admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }
      # Out-of-band demote simulates a racing transfer that already won;
      # stub reload so the in-memory role stays "owner" (modelling a stale
      # snapshot read on a different connection).
      Membership.where(id: owner_membership.id).update_all(role_id: admin_role.id)
      allow(owner_membership).to receive(:reload) { owner_membership }

      expect {
        owner_membership.transfer_ownership_to!(target_membership)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(target_membership.reload.role.slug).not_to eq("owner")
    end
  end

  # Locks in the self-exclusion semantic of the predicate that gates the
  # WorkspaceMemberAddedNotifier `after_create_commit` callback. The predicate
  # name (`workspace_has_other_owners?`) must reflect that we're asking about
  # owners *other than this membership* — without that exclusion, the very
  # first owner being seeded for a fresh workspace would self-trigger a
  # "new member joined" notification with itself as the audience.
  #
  # Predicate is private (matches Rails conventions for callback gates); we
  # exercise it via `send` rather than expose the method publicly just for
  # tests.
  describe "#workspace_has_other_owners? (self-exclusion semantic)" do
    let(:workspace) { create(:workspace) }

    it "returns false when this is the only owner-role membership in the workspace" do
      sole_owner = create(:membership, :owner, workspace: workspace)
      expect(sole_owner.send(:workspace_has_other_owners?)).to be false
    end

    it "returns true when another owner-role membership exists in the workspace" do
      first_owner = create(:membership, :owner, workspace: workspace)
      create(:membership, :owner, workspace: workspace)
      expect(first_owner.send(:workspace_has_other_owners?)).to be true
    end

    it "returns true for a non-owner membership when another owner-role membership exists in the workspace" do
      # The predicate is a workspace-scoped question — "are there other
      # owners in this workspace?" — not "is THIS membership not the lone
      # owner?". A non-owner member added to a workspace that already has
      # an owner returns true (the gate fires the notifier).
      create(:membership, :owner, workspace: workspace)
      member_membership = create(:membership, workspace: workspace)
      expect(member_membership.send(:workspace_has_other_owners?)).to be true
    end

    it "returns false when no other owner exists even with an admin sibling" do
      sole_owner = create(:membership, :owner, workspace: workspace)
      create(:membership, :admin, workspace: workspace)
      expect(sole_owner.send(:workspace_has_other_owners?)).to be false
    end

    it "ignores discarded owner memberships" do
      first_owner = create(:membership, :owner, workspace: workspace)
      second_owner = create(:membership, :owner, workspace: workspace)
      second_owner.discard!
      expect(first_owner.send(:workspace_has_other_owners?)).to be false
    end

    it "ignores owners from other workspaces" do
      sole_in_target = create(:membership, :owner, workspace: workspace)
      other_workspace = create(:workspace)
      create(:membership, :owner, workspace: other_workspace)
      expect(sole_in_target.send(:workspace_has_other_owners?)).to be false
    end
  end

  describe ".other_kept_owners" do
    let(:workspace) { create(:workspace) }

    it "returns kept owner-role memberships in the workspace excluding the given membership id" do
      first_owner = create(:membership, :owner, workspace: workspace)
      second_owner = create(:membership, :owner, workspace: workspace)

      expect(Membership.other_kept_owners(workspace.id, excluding: first_owner.id))
        .to contain_exactly(second_owner)
    end

    it "excludes discarded owners, non-owner roles, and owners of other workspaces" do
      owner = create(:membership, :owner, workspace: workspace)
      create(:membership, :owner, workspace: workspace).discard!
      create(:membership, :admin, workspace: workspace)
      create(:membership, :owner, workspace: create(:workspace))

      expect(Membership.other_kept_owners(workspace.id, excluding: owner.id)).to be_empty
    end
  end

  # Wiring coverage: drive the model state change and assert the notifier
  # actually fires. The notifiers themselves are specced in spec/notifiers/;
  # without these, the after_*_commit registrations could be deleted and the
  # suite would stay green.
  describe "notification wiring" do
    let(:owner) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }
    let(:member) { create(:user) }

    describe "member added (after_create_commit)" do
      it "notifies the added user and the existing owner" do
        membership = create(:membership, user: member, workspace: workspace)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event).to be_present
        expect(event.record).to eq(membership)
        expect(event.notifications.map(&:recipient)).to contain_exactly(member, owner)
      end

      it "does not notify when seeding a workspace's first owner" do
        fresh_workspace = create(:workspace)
        expect {
          create(:membership, :owner, user: member, workspace: fresh_workspace)
        }.not_to change { Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").count }
      end

      it "excludes the actor who performed the add" do
        workspace.admit(member, role: Role.system_default!("member"), granted_by: owner)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end
    end

    # #933: removal was the one membership transition that notified nobody.
    # Covered here rather than in the notifier spec because these pin the
    # CALLBACK wiring — the actor arriving as an argument, the direction of the
    # discarded_at change, and the write surviving a broken notifier.
    describe "member removed (after_update_commit)" do
      let!(:membership) { create(:membership, user: member, workspace: workspace) }

      it "hands the notifier the actor the caller named, without reading Current" do
        membership.deactivate!(removed_by: owner)

        event = Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier").last
        expect(event).to be_present
        expect(event.record).to eq(membership)
        expect(event.reload.params[:actor]).to eq(owner)
      end

      it "leaves the actor nil when the caller names none" do
        membership.deactivate!

        event = Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier").last
        expect(event.reload.params[:actor]).to be_nil
      end

      it "does not reuse an earlier actor when a later removal names none" do
        membership.deactivate!(removed_by: owner)
        membership.reactivate!(granted_by: owner)
        # Past the one-minute idempotency bucket, so the second removal is a
        # new event rather than a dedup drop of the first.
        travel_to(2.minutes.from_now) { membership.deactivate! }

        event = Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier").order(:created_at).last
        expect(event.reload.params[:actor]).to be_nil
      end

      # Same best-effort posture the rest of the notification wiring has: the
      # business write is not hostage to the fan-out.
      it "still removes the member when the notifier raises" do
        allow(WorkspaceMemberRemovedNotifier).to receive(:with).and_raise(StandardError, "boom")

        expect { membership.deactivate!(removed_by: owner) }.not_to raise_error
        expect(membership.reload).to be_discarded
      end
    end

    # Re-admission is an undiscard, not a create, so after_create_commit never
    # fires — a previously removed member came silently back with zero
    # notifications. Covered here rather than in the notifier spec because the
    # bug was in the callback wiring.
    describe "member re-admitted (after_update_commit)" do
      include ActiveJob::TestHelper

      let!(:membership) { create(:membership, user: member, workspace: workspace) }

      before do
        membership.deactivate!
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
        ActionMailer::Base.deliveries.clear
        clear_enqueued_jobs
      end

      it "notifies the re-admitted member and the owners on Membership#reactivate!" do
        expect {
          membership.reactivate!
        }.to change { Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").count }.by(1)

        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event.record).to eq(membership)
        expect(event.notifications.map(&:recipient)).to contain_exactly(member, owner)
      end

      it "excludes the actor who performed the re-admission" do
        membership.reactivate!(granted_by: owner)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      it "notifies through Workspace#admit's undiscard branch too, minus the actor" do
        workspace.admit(member, role: Role.system_default!("member"), granted_by: owner)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event).to be_present
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      # WorkspaceMemberAddedNotifier's email, not WelcomeNotifier's — that one
      # is the account's day-one notice and has no email leg at all.
      it "sends the re-admitted member WorkspaceMemberAddedNotifier's email, as a fresh add would" do
        perform_enqueued_jobs(only: Noticed::EventJob) { membership.reactivate! }
        perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
        perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

        expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([ member.email_address ])
      end

      it "does not notify on deactivation" do
        membership.reactivate!
        Noticed::Event.delete_all
        expect {
          membership.deactivate!
        }.not_to change { Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").count }
      end

      # track_creation is the only writer of grant provenance, and a
      # re-admission is an UPDATE, so re-granting a previously removed member
      # recorded who did it nowhere: `changes: {discarded_at: [...]}` and an
      # actor that, on the invitation path, is the invitee themselves.
      describe "grant provenance on the audit row" do
        def reactivation_row
          ActivityLog.where(action: "membership.updated", trackable: membership).last
        end

        before { ActivityLog.where(trackable: membership).delete_all }

        it "records the granter on the re-admission row" do
          membership.reactivate!(granted_by: owner)

          expect(reactivation_row.metadata["granted_by"]).to eq(owner.id)
        end

        it "records the granter when the re-admission comes through Workspace#admit" do
          workspace.admit(member, role: Role.system_default!("member"), granted_by: owner)

          expect(reactivation_row.metadata["granted_by"]).to eq(owner.id)
        end

        it "still records the changed columns alongside it" do
          membership.reactivate!(granted_by: owner)

          expect(reactivation_row.metadata["changes"]).to have_key("discarded_at")
        end

        it "claims no granter for a re-admission that had none" do
          membership.reactivate!

          expect(reactivation_row.metadata).not_to have_key("granted_by")
        end

        it "claims no granter for an ordinary update that is not a re-admission" do
          membership.reactivate!
          ActivityLog.where(trackable: membership).delete_all
          membership.granted_by = owner
          membership.update!(role: Role.system_default!("admin"))

          expect(reactivation_row.metadata).not_to have_key("granted_by")
        end
      end
    end

    describe "role changed (after_update_commit)" do
      let!(:membership) { create(:membership, user: member, workspace: workspace) }
      let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }

      it "notifies the member when their role changes" do
        expect {
          membership.change_role!(admin_role)
        }.to change { Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      it "does not notify on a save that leaves the role unchanged" do
        expect {
          membership.update!(last_accessed_at: Time.current)
        }.not_to change { Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").count }
      end

      it "transfer_ownership_to! notifies the promoted member, not the demoted initiator" do
        expect {
          owner_membership.transfer_ownership_to!(membership)
        }.to change { Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end
    end
  end
end
