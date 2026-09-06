require "rails_helper"

RSpec.describe Invitation, type: :model do
  describe "validations" do
    it "requires an invitable" do
      invitation = build(:invitation, invitable: nil)
      expect(invitation).not_to be_valid
    end

    it "requires a role" do
      invitation = build(:invitation, role: nil)
      expect(invitation).not_to be_valid
    end

    it "requires an invited_by user" do
      invitation = build(:invitation, invited_by: nil)
      expect(invitation).not_to be_valid
    end

    it "requires expires_at" do
      invitation = build(:invitation, expires_at: nil)
      expect(invitation).not_to be_valid
    end
  end

  describe "token generation" do
    it "generates a token before create" do
      invitation = create(:invitation)
      expect(invitation.token).to be_present
    end

    it "generates unique tokens" do
      inv1 = create(:invitation)
      inv2 = create(:invitation)
      expect(inv1.token).not_to eq(inv2.token)
    end
  end

  describe "scopes" do
    it "returns pending invitations" do
      pending_inv = create(:invitation)
      create(:invitation, :accepted)
      expect(Invitation.acceptable).to contain_exactly(pending_inv)
    end

    it "excludes expired from the acceptable scope" do
      create(:invitation, :expired)
      expect(Invitation.acceptable).to be_empty
    end

    # #452: the enum generates BOTH a `pending` scope and a `pending?`
    # predicate, and overriding only the scope to also require an unexpired
    # `expires_at` made the two disagree — an expired invitation was `pending?`
    # but absent from `Invitation.pending`. Anyone reasoning "in the scope iff
    # the predicate" wrote a subtle bug. The extra constraint now lives under
    # its own name, which mirrors the `acceptable?` predicate exactly.
    describe "class- and instance-level agreement" do
      let!(:expired) { create(:invitation, :expired) }

      it "keeps the enum-generated pending scope in step with pending?" do
        expect(expired).to be_pending
        expect(Invitation.pending).to include(expired)
      end

      it "mirrors acceptable? with the acceptable scope" do
        expect(expired).not_to be_acceptable
        expect(Invitation.acceptable).not_to include(expired)

        open_invite = create(:invitation)
        expect(open_invite).to be_acceptable
        expect(Invitation.acceptable).to include(open_invite)
      end

      it "keeps has_invitee? the exact complement of magic_link? (PR 4)" do
        emailed = create(:invitation)
        bearer = create(:invitation, :magic_link)
        expect(emailed.has_invitee?).to eq(!emailed.magic_link?)
        expect(bearer.has_invitee?).to eq(!bearer.magic_link?)
      end
    end
  end

  describe "Invitation::NotAcceptable" do
    it "is a standalone StandardError (not an ActiveRecord::RecordInvalid)" do
      expect(Invitation::NotAcceptable.ancestors).to include(StandardError)
      expect(Invitation::NotAcceptable.ancestors).not_to include(ActiveRecord::RecordInvalid)
    end
  end

  describe "#accept! raise behavior" do
    let(:user) { create(:user) }

    it "raises Invitation::NotAcceptable when invitation is already accepted" do
      invitation = create(:invitation, :accepted)
      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
    end

    it "raises Invitation::NotAcceptable when invitation is expired" do
      invitation = create(:invitation, :expired)
      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
    end

    it "raises Invitation::NotAcceptable when invitation is declined" do
      invitation = create(:invitation, :declined)
      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
    end

    it "does NOT raise NotAcceptable on a valid pending invitation" do
      invitation = create(:invitation)
      expect {
        invitation.accept!(user)
      }.not_to raise_error
    end

    # G (SEC-1 follow-up): the invitation flow — the most common grant path —
    # logged membership.created with empty metadata and only the accepting
    # invitee as actor. The granter and granted role now ride as metadata
    # (the actor stays the invitee: they performed the accept).
    it "audits the granted membership with role and granter" do
      invitation = create(:invitation)
      invitation.accept!(user)

      membership = invitation.invitable.memberships.find_by(user: user)
      entry = ActivityLog.where(action: "membership.created", trackable: membership).last
      expect(entry).to be_present
      expect(entry.metadata["role"]).to eq(invitation.role.slug)
      expect(entry.metadata["granted_by"]).to eq(invitation.invited_by_id)
    end

    it "raises Invitation::NotAcceptable when the target workspace is suspended (workspace invitation)" do
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace)
      workspace.suspend!
      # Force user creation outside the expect block — onboarding callbacks
      # create their own membership, which would confound the count.
      user

      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
        .and change(Membership, :count).by(0)
    end

    it "raises Invitation::NotAcceptable when the target workspace is suspended (project invitation)" do
      workspace = create(:workspace)
      owner = create(:user)
      create(:membership, :owner, user: owner, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: owner)
      viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
      invitation = project.invitations.create!(
        email: "project-invitee@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
      workspace.suspend!
      # Force user creation outside the expect block — onboarding callbacks
      # create their own membership, which would confound the count.
      user

      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
        .and change(Membership, :count).by(0)
    end
  end

  describe "#accept!" do
    let(:workspace) { create(:workspace) }
    let!(:invitation) { create(:invitation, invitable: workspace) }
    let!(:user) { create(:user) }

    it "creates a membership" do
      expect { invitation.accept!(user) }.to change(Membership, :count).by(1)
    end

    it "prevents double-accept" do
      invitation = create(:invitation, invitable: create(:workspace))
      user = create(:user)
      invitation.accept!(user)
      expect { invitation.accept!(create(:user)) }.to raise_error(Invitation::NotAcceptable)
    end

    it "sets accepted status" do
      invitation.accept!(user)
      expect(invitation.reload.status).to eq("accepted")
      expect(invitation.accepted_by).to eq(user)
      expect(invitation.accepted_at).to be_present
    end

    it "assigns the invitation's role to the membership" do
      invitation.accept!(user)
      membership = workspace.memberships.find_by(user: user)
      expect(membership.role).to eq(invitation.role)
    end

    it "raises if user is already a member" do
      create(:membership, user: user, workspace: workspace)
      expect { invitation.accept!(user) }.to raise_error(Workspace::AlreadyMember)
    end
  end

  describe "#accept! reactivates discarded workspace membership" do
    it "reactivates discarded membership on workspace re-invite" do
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace)
      user = create(:user)
      old_membership = create(:membership, user: user, workspace: workspace)
      other_owner = create(:user)
      create(:membership, :owner, user: other_owner, workspace: workspace)
      old_membership.deactivate!

      invitation.accept!(user)
      expect(old_membership.reload).not_to be_discarded
    end
  end

  # Regression: capacity is enforced through the invitation acceptance path.
  # Membership-level capacity is also tested in spec/models/membership_spec.rb,
  # but the accept! flow goes through Invitation#accept_workspace_invitation!
  # which acquires workspace.lock! BEFORE checking the count (line 111 vs 118).
  # This test locks in that the lock-then-check sequence prevents over-capacity
  # acceptances, even on engines (e.g., PostgreSQL) where row-level locks are
  # the only serialization mechanism. SQLite's BEGIN IMMEDIATE provides
  # additional database-wide write serialization, but this test asserts the
  # business rule independent of engine.
  describe "#accept! capacity enforcement (regression)" do
    it "rejects acceptance when workspace is at max_members" do
      workspace = create(:workspace, max_members: 2)
      create(:membership, :owner, workspace: workspace)
      create(:membership, workspace: workspace)
      invitation = create(:invitation, invitable: workspace)
      user = create(:user)

      expect { invitation.accept!(user) }
        .to raise_error(Workspace::AtCapacity)

      expect(workspace.memberships.kept.count).to eq(2)
      expect(invitation.reload).to be_pending
    end

    it "rejects project-invitation acceptance when workspace is at capacity" do
      workspace = create(:workspace, max_members: 2)
      owner_membership = create(:membership, :owner, workspace: workspace)
      create(:membership, workspace: workspace)
      # Reuse the owner as the project's created_by to avoid the project factory's
      # after_create membership backfill (which would push the workspace over cap
      # before our invitation acceptance even runs — see spec/factories/projects.rb).
      project = create(:project, workspace: workspace, created_by: owner_membership.user)
      invitation = create(:invitation, invitable: project, project_role: "editor")
      user = create(:user)

      # Same typed error as the workspace path: capacity is enforced inside
      # Workspace#admit for every admission flow.
      expect { invitation.accept!(user) }
        .to raise_error(Workspace::AtCapacity)

      expect(workspace.memberships.kept.count).to eq(2)
      expect(invitation.reload).to be_pending
    end
  end

  describe "#decline!" do
    let(:invitation) { create(:invitation) }

    it "sets declined status" do
      invitation.decline!
      expect(invitation.reload.status).to eq("declined")
      expect(invitation.declined_at).to be_present
    end
  end

  describe "#revoke!" do
    let(:invitation) { create(:invitation) }

    it "sets revoked status" do
      invitation.revoke!
      expect(invitation.reload.status).to eq("revoked")
      expect(invitation.revoked_at).to be_present
    end
  end

  describe "#decline! guard" do
    it "prevents declining an already accepted invitation" do
      invitation = create(:invitation, invitable: create(:workspace))
      user = create(:user)
      invitation.accept!(user)
      expect { invitation.decline! }.to raise_error(ActiveRecord::RecordInvalid) { |e|
        expect(e.record.errors.details[:base]).to include(error: :already_processed)
      }
    end
  end

  describe "#revoke! guard" do
    it "prevents revoking an already declined invitation" do
      invitation = create(:invitation)
      invitation.decline!
      expect { invitation.revoke! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # #675: the guards must re-read state INSIDE the transaction (accept!'s
  # lock! shape) — a stale in-memory pending? passing the guard would write
  # revoked/declined OVER a committed acceptance, leaving a revoked invitation
  # with a live membership and an audit trail that lies.
  describe "check-then-act races (#675)" do
    let(:invitation) { create(:invitation, invitable: create(:workspace)) }

    it "revoke! on a stale instance cannot overwrite a committed acceptance" do
      stale = Invitation.find(invitation.id)
      invitation.accept!(create(:user))

      expect { stale.revoke! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(invitation.reload.status).to eq("accepted")
    end

    it "decline! on a stale instance cannot overwrite a committed acceptance" do
      stale = Invitation.find(invitation.id)
      invitation.accept!(create(:user))

      expect { stale.decline! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(invitation.reload.status).to eq("accepted")
    end

    it "resend! refuses a non-pending invitation instead of rotating its token" do
      invitation.accept!(create(:user))
      original_token = invitation.reload.token

      expect { invitation.resend! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(invitation.reload.token).to eq(original_token)
    end
  end

  describe "#resend!" do
    let(:invitation) { create(:invitation) }

    it "regenerates the token" do
      old_token = invitation.token
      invitation.resend!
      expect(invitation.reload.token).not_to eq(old_token)
    end

    it "resets the expiry" do
      invitation.update!(expires_at: 1.day.from_now)
      invitation.resend!
      expect(invitation.reload.expires_at).to be > 6.days.from_now
    end
  end

  describe "#expired?" do
    it "returns true when past expires_at" do
      invitation = build(:invitation, expires_at: 1.hour.ago)
      expect(invitation).to be_expired
    end

    it "returns false when before expires_at" do
      invitation = build(:invitation, expires_at: 1.hour.from_now)
      expect(invitation).not_to be_expired
    end
  end

  describe "#magic_link?" do
    it "returns true when email is nil" do
      invitation = build(:invitation, :magic_link)
      expect(invitation).to be_magic_link
    end

    it "returns false when email is present" do
      invitation = build(:invitation)
      expect(invitation).not_to be_magic_link
    end
  end

  describe "#accept! for project invitation" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    let(:invitation) do
      project.invitations.create!(
        email: "project-invitee@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
    end

    it "creates workspace membership and project membership" do
      invitee = create(:user, email_address: "project-invitee@example.com")
      invitation.accept!(invitee)
      expect(workspace.memberships.kept.exists?(user: invitee)).to be true
      expect(project.project_memberships.exists?(user: invitee)).to be true
    end

    # Regression: this path once hand-rolled the membership grant and dropped
    # granted_by, so the most common project-invite grant audited no granter
    # (granted_by is non-persisted by design — the audit row is where the
    # provenance lives, so it is also where the regression is pinned).
    it "audits the granted workspace membership with role and granter" do
      invitee = create(:user, email_address: "project-invitee@example.com")
      invitation.accept!(invitee)

      membership = workspace.memberships.find_by!(user: invitee)
      entry = ActivityLog.where(action: "membership.created", trackable: membership).last
      expect(entry).to be_present
      expect(entry.metadata["role"]).to eq(invitation.role.slug)
      expect(entry.metadata["granted_by"]).to eq(owner.id)
    end

    it "assigns the correct project role" do
      invitee = create(:user, email_address: "project-invitee2@example.com")
      invitation2 = project.invitations.create!(
        email: "project-invitee2@example.com",
        role: viewer_role,
        project_role: "viewer",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
      invitation2.accept!(invitee)
      pm = project.project_memberships.find_by(user: invitee)
      expect(pm).to be_viewer
    end

    it "raises NotAcceptable for a discarded project" do
      project.discard!
      invitee = create(:user)
      expect { invitation.accept!(invitee) }.to raise_error(Invitation::NotAcceptable)
    end
  end

  describe "project_role validation" do
    it "accepts editor" do
      inv = build(:invitation, project_role: "editor")
      inv.valid?
      expect(inv.errors[:project_role]).to be_empty
    end

    it "accepts viewer" do
      inv = build(:invitation, project_role: "viewer")
      inv.valid?
      expect(inv.errors[:project_role]).to be_empty
    end

    it "rejects creator" do
      inv = build(:invitation, project_role: "creator")
      expect(inv).not_to be_valid
      expect(inv.errors[:project_role]).to be_present
    end

    it "accepts nil (for workspace invitations)" do
      inv = build(:invitation, project_role: nil)
      inv.valid?
      expect(inv.errors[:project_role]).to be_empty
    end
  end

  describe "#accept! when user is already a project member" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    let(:invitation) do
      project.invitations.create!(
        email: "already-member@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
    end

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
    end

    it "raises when user is already a project member" do
      existing_user = create(:user, email_address: "already-member@example.com")
      create(:membership, user: existing_user, workspace: workspace)
      create(:project_membership, project: project, user: existing_user)

      expect { invitation.accept!(existing_user) }.to raise_error(ActiveRecord::RecordInvalid) { |e|
        expect(e.record.errors.details[:base]).to include(error: :already_project_member)
      }
    end
  end

  describe "#accept! reactivates discarded workspace membership for project invitation" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }

    before { create(:membership, :owner, user: owner, workspace: workspace) }

    it "reactivates the discarded membership" do
      user = create(:user)
      ws_membership = create(:membership, user: user, workspace: workspace)
      other_owner = create(:membership, :owner, workspace: workspace)
      ws_membership.deactivate!

      invitation = project.invitations.create!(
        email: user.email_address,
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )

      invitation.accept!(user)
      expect(ws_membership.reload).not_to be_discarded
      expect(project.project_memberships.exists?(user: user)).to be true
    end
  end

  describe "email normalization" do
    let(:workspace) { create(:workspace) }

    it "stores the canonical form of the address" do
      invitation = create(:invitation, invitable: workspace, email: "Invitee@Example.COM")
      expect(invitation.email).to eq("invitee@example.com")
    end

    it "accepts an address padded with whitespace" do
      invitation = build(:invitation, invitable: workspace, email: " invitee@example.com ")
      expect(invitation).to be_valid
      expect(invitation.email).to eq("invitee@example.com")
    end

    it "stores an IDN domain in its punycode form, matching User" do
      invitation = create(:invitation, invitable: workspace, email: "user@bücher.de")
      expect(invitation.email).to eq("user@xn--bcher-kva.de")
    end
  end

  describe ".bulk_invite!" do
    let(:workspace) { create(:workspace) }
    let(:role) { workspace.effective_roles.first }
    let(:inviter) { create(:user) }

    before do
      create(:membership, :owner, user: inviter, workspace: workspace)
    end

    # Users are stored through EmailNormalizer (IDN domains punycoded), so the
    # dedupe key must be the same normalization — not a bare downcase.
    describe "dedupe against normalized storage" do
      it "skips an existing member typed in the Unicode form of a punycoded address" do
        member = create(:user, email_address: "user@bücher.de")
        create(:membership, user: member, workspace: workspace)

        result = Invitation.bulk_invite!(
          workspace: workspace, emails: [ "user@bücher.de" ], role: role, invited_by: inviter
        )

        expect(result).to include(sent: 0, skipped: 1)
        expect(workspace.invitations.count).to eq(0)
      end

      it "skips a pending invitation typed in the other form of the same IDN address" do
        create(:invitation, invitable: workspace, email: "user@bücher.de", invited_by: inviter)

        result = Invitation.bulk_invite!(
          workspace: workspace, emails: [ "user@xn--bcher-kva.de" ], role: role, invited_by: inviter
        )

        expect(result).to include(sent: 0, skipped: 1)
        expect(workspace.invitations.count).to eq(1)
      end
    end

    it "creates invitations for valid emails and returns counts" do
      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "alice@example.com", "bob@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(2)
      expect(result[:skipped]).to eq(0)
      expect(workspace.invitations.count).to eq(2)
    end

    # C8: the raw textarea string is bulk_invite!'s to parse — both invite
    # forms hand it over verbatim instead of duplicating the split/strip.
    describe "raw-string email list" do
      it "splits on newlines and commas, stripping whitespace" do
        result = Invitation.bulk_invite!(
          workspace: workspace,
          emails: "alice@example.com, bob@example.com\n  carol@example.com  ",
          role: role,
          invited_by: inviter
        )

        expect(result[:sent]).to eq(3)
        expect(result[:skipped]).to eq(0)
        expect(workspace.invitations.pluck(:email))
          .to contain_exactly("alice@example.com", "bob@example.com", "carol@example.com")
      end

      it "ignores blank entries from stray separators" do
        result = Invitation.bulk_invite!(
          workspace: workspace,
          emails: ",\n alice@example.com ,,\n\n",
          role: role,
          invited_by: inviter
        )

        expect(result[:sent]).to eq(1)
        expect(result[:skipped]).to eq(0)
      end

      it "treats an all-separator string as an empty list" do
        result = Invitation.bulk_invite!(
          workspace: workspace,
          emails: " ,\n, ",
          role: role,
          invited_by: inviter
        )

        expect(result).to eq(sent: 0, skipped: 0, over_limit: false)
      end
    end

    it "skips invalid email formats" do
      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "not-an-email", "valid@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "skips emails that are already workspace members" do
      existing_user = create(:user, email_address: "member@example.com")
      create(:membership, user: existing_user, workspace: workspace)

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "member@example.com", "new@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "skips emails with pending invitations" do
      workspace.invitations.create!(
        email: "pending@example.com",
        role: role,
        invited_by: inviter,
        expires_at: 7.days.from_now
      )

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "pending@example.com", "new@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "queues invitation mailers" do
      expect {
        Invitation.bulk_invite!(
          workspace: workspace,
          emails: [ "alice@example.com" ],
          role: role,
          invited_by: inviter
        )
      }.to have_enqueued_mail(InvitationMailer, :invite)
    end

    it "skips an email whose pending invitation was created concurrently instead of aborting the batch" do
      # The lost race: create the row for real, then stub THIS call's
      # `acceptable` preload to miss it — simulating a commit that lands
      # after the preload reads but before create! — so the real row still
      # trips the pending_live unique index in create!, for real.
      workspace.invitations.create!(
        email: "raced@example.com", role: role, invited_by: inviter,
        expires_at: 7.days.from_now
      )
      invitations = workspace.invitations
      allow(workspace).to receive(:invitations).and_return(invitations)
      allow(invitations).to receive(:acceptable).and_return(Invitation.none)

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "raced@example.com", "fresh@example.com" ],
        role: role, invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
      expect(Invitation.where(email: "raced@example.com").count).to eq(1)
    end
  end

  describe "email format validation" do
    it "rejects malformed email" do
      inv = build(:invitation, email: "not-an-email")
      expect(inv).not_to be_valid
      expect(inv.errors[:email]).to be_present
    end

    it "accepts valid email" do
      inv = build(:invitation, email: "valid@example.com")
      inv.valid?
      expect(inv.errors[:email]).to be_empty
    end

    it "accepts nil email (magic links)" do
      inv = build(:invitation, email: nil)
      inv.valid?
      expect(inv.errors[:email]).to be_empty
    end
  end
  describe "#resolved_workspace" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }

    it "returns the invitable when invitable is a Workspace" do
      invitation = create(:invitation, invitable: workspace)
      expect(invitation.resolved_workspace).to eq(workspace)
    end

    it "returns the project's workspace when invitable is a Project" do
      create(:membership, :owner, user: owner, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: owner)
      invitation = create(:invitation, invitable: project, project_role: "editor")
      expect(invitation.resolved_workspace).to eq(workspace)
    end
  end
  describe "#acceptable?" do
    it "returns true for a pending, non-expired invitation" do
      invitation = build(:invitation)
      expect(invitation.acceptable?).to be true
    end

    it "returns false for an expired invitation" do
      invitation = build(:invitation, :expired)
      expect(invitation.acceptable?).to be false
    end

    it "returns false for an accepted invitation" do
      invitation = build(:invitation, :accepted)
      expect(invitation.acceptable?).to be false
    end

    it "returns false for a declined invitation" do
      invitation = build(:invitation, :declined)
      expect(invitation.acceptable?).to be false
    end

    it "returns false for a revoked invitation" do
      invitation = build(:invitation, :revoked)
      expect(invitation.acceptable?).to be false
    end
  end

  describe "#expires_in_hours" do
    # Use ceil so "expires in 1 hour" reads naturally at T-30min instead of "0
    # hours" — the user-facing copy is hours-remaining, not floor of hours.
    it "ceils a fractional remaining window to the next whole hour" do
      freeze_time do
        invitation = build(:invitation, expires_at: 90.minutes.from_now)
        expect(invitation.expires_in_hours).to eq(2)
      end
    end

    it "ceils a sub-hour remaining window to 1" do
      freeze_time do
        invitation = build(:invitation, expires_at: 30.minutes.from_now)
        expect(invitation.expires_in_hours).to eq(1)
      end
    end

    it "returns the exact number when the window is exactly an integer hour" do
      freeze_time do
        invitation = build(:invitation, expires_at: 24.hours.from_now)
        expect(invitation.expires_in_hours).to eq(24)
      end
    end

    it "returns 0 when the invitation is exactly at expiry" do
      freeze_time do
        invitation = build(:invitation, expires_at: Time.current)
        expect(invitation.expires_in_hours).to eq(0)
      end
    end

    it "returns 0 when the invitation has already expired" do
      freeze_time do
        invitation = build(:invitation, expires_at: 5.minutes.ago)
        expect(invitation.expires_in_hours).to eq(0)
      end
    end
  end

  # Shared consumption core used by both the session-based (Signupable) and
  # column-based (Authentication#claim_pending_invitation!) acceptance paths.
  describe ".consume!" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }

    it "accepts the matching invitation and returns it" do
      invitation = create(:invitation, invitable: workspace)

      result = Invitation.consume!(token: invitation.token, user: user)

      expect(result).to eq(invitation)
      expect(invitation.reload).to be_accepted
      expect(workspace.memberships.kept.exists?(user: user)).to be true
    end

    it "returns nil when the token is blank" do
      expect(Invitation.consume!(token: nil, user: user)).to be_nil
      expect(Invitation.consume!(token: "", user: user)).to be_nil
    end

    it "returns nil when no invitation matches the token" do
      expect(Invitation.consume!(token: "does-not-exist", user: user)).to be_nil
    end

    it "raises Invitation::NotAcceptable when the invitation is no longer acceptable" do
      invitation = create(:invitation, :accepted, invitable: workspace)

      expect {
        Invitation.consume!(token: invitation.token, user: user)
      }.to raise_error(Invitation::NotAcceptable)
    end

    context "with expected_email (email-match guard)" do
      it "accepts when the proven email matches the invitation email (case-insensitive)" do
        invitation = create(:invitation, invitable: workspace, email: "Invitee@Example.com")
        matching = create(:user, email_address: "invitee@example.com")

        result = Invitation.consume!(token: invitation.token, user: matching, expected_email: matching.email_address)

        expect(result).to eq(invitation)
        expect(invitation.reload).to be_accepted
      end

      it "raises EmailMismatch when the proven email differs from the invitation email" do
        invitation = create(:invitation, invitable: workspace, email: "invitee@example.com")
        other = create(:user, email_address: "someone-else@example.com")

        expect {
          Invitation.consume!(token: invitation.token, user: other, expected_email: other.email_address)
        }.to raise_error(Invitation::EmailMismatch)

        expect(invitation.reload).to be_pending
        expect(workspace.memberships.kept.exists?(user: other)).to be false
      end

      it "is a kind of NotAcceptable so existing boundary rescues still catch it" do
        expect(Invitation::EmailMismatch.ancestors).to include(Invitation::NotAcceptable)
      end

      it "consumes a magic-link invitation (nil email) regardless of expected_email" do
        invitation = create(:invitation, :magic_link, invitable: workspace)
        anyone = create(:user, email_address: "anyone@example.com")

        result = Invitation.consume!(token: invitation.token, user: anyone, expected_email: anyone.email_address)

        expect(result).to eq(invitation)
        expect(invitation.reload).to be_accepted
      end

      it "skips the guard when expected_email is not provided (direct callers)" do
        invitation = create(:invitation, invitable: workspace, email: "invitee@example.com")
        # user's email differs, but no expected_email is passed → no guard
        result = Invitation.consume!(token: invitation.token, user: user)

        expect(result).to eq(invitation)
      end
    end
  end

  describe "client invitations" do
    let!(:owner_role) do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"; r.permissions = { manage_workspace: true }
      end
    end
    let(:project) { create(:project, clientside_enabled: true) }
    let(:inviter) { create(:user) }

    it "is a client invite when company_name is present" do
      inv = build(:invitation, :client, invitable: project)
      expect(inv.client_invite?).to be(true)
      expect(inv).to be_valid
    end

    it "allows a nil role only for client invites" do
      member = build(:invitation, role: nil, company_name: nil)
      expect(member).not_to be_valid
      expect(member.errors[:role]).to be_present
    end

    it ".invite_client! creates the invite and enqueues the client mailer" do
      expect {
        Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                  company_name: "BigCo", invited_by: inviter)
      }.to have_enqueued_mail(InvitationMailer, :invite_client)
      inv = Invitation.last
      expect(inv.client_invite?).to be(true)
      expect(inv.role).to be_nil
      expect(inv.invitable).to eq(project)
    end

    it "accept! creates a ClientAccess and stamps onboarded_at" do
      inv = Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      client = create(:user, :with_zero_workspaces, email_address: "dana@bigco.com")
      expect { inv.accept!(client) }.to change { project.client_accesses.kept.count }.by(1)
      expect(project.client?(client)).to be(true)
      expect(client.reload.onboarded?).to be(true)
      expect(inv.reload).to be_accepted
    end

    it "consume! still guards against a mismatched email (bearer protection)" do
      inv = Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      other = create(:user, :with_zero_workspaces, email_address: "evil@example.com")
      expect { Invitation.consume!(token: inv.token, user: other, expected_email: other.email_address) }
        .to raise_error(Invitation::EmailMismatch)
    end

    it "accept! raises NotAcceptable when Clientside is disabled (undiscard bypass)" do
      inv = Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      client = create(:user, :with_zero_workspaces, email_address: "dana@bigco.com")
      project.client_accesses.create!(user: client, company_name: "BigCo").discard!
      project.update!(clientside_enabled: false)

      expect { inv.accept!(client) }.to raise_error(Invitation::NotAcceptable, /clientside is disabled/i)
    end

    it "accept! still succeeds when Clientside is enabled (happy path)" do
      inv = Invitation.invite_client!(project: project, email: "happy@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      client = create(:user, :with_zero_workspaces, email_address: "happy@bigco.com")
      expect { inv.accept!(client) }.to change { project.client_accesses.kept.count }.by(1)
      expect(inv.reload).to be_accepted
    end

    it "is invalid when invitable is a Workspace, not a Project" do
      inv = build(:invitation, :client, invitable: create(:workspace))
      expect(inv).not_to be_valid
      expect(inv.errors[:base]).to be_present
    end

    it "accept! for a client invitation to a discarded project raises NotAcceptable and creates no ClientAccess" do
      inv = Invitation.invite_client!(project: project, email: "dana@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      client = create(:user, :with_zero_workspaces, email_address: "dana@bigco.com")
      project.discard!

      expect { inv.accept!(client) }.to raise_error(Invitation::NotAcceptable)
      expect(ClientAccess.where(user: client, project: project)).to be_empty
    end

    # Closes the admission matrix for the CLIENT (project-invitable) vector: the
    # single accept! choke-point guard (unless resolved_workspace&.admittable?)
    # resolves the workspace THROUGH the project, so a new client invitation into
    # an archived (or deleted) workspace is blocked — new admission requires an
    # active workspace, even though archived KEEPS existing client access.
    it "accept! for a client invitation whose workspace is archived raises NotAcceptable and creates no ClientAccess" do
      inv = Invitation.invite_client!(project: project, email: "arch@bigco.com",
                                      company_name: "BigCo", invited_by: inviter)
      client = create(:user, :with_zero_workspaces, email_address: "arch@bigco.com")
      project.workspace.archive!

      expect { inv.accept!(client) }.to raise_error(Invitation::NotAcceptable)
      expect(ClientAccess.where(user: client, project: project)).to be_empty
    end
  end

  # Reshape 1 reconciliation: under :shared posture, User#onboard_workspace
  # pre-creates a Member membership at signup. The invitation flow must then
  # adopt the invitation's role rather than treating the existing membership
  # as a duplicate-accept error. Solo-default (:personal) semantics unchanged.
  describe "#accept! reconciles role under :shared posture" do
    let!(:shared_workspace) { create(:workspace, slug: "acme", personal: false) }
    let!(:admin_role) {
      Role.find_or_create_by!(slug: "admin", workspace_id: nil) do |r|
        r.name = "Admin"
        r.permissions = { manage_members: true, manage_projects: true, manage_settings: true }
      end
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      end
    }
    let(:inviter) { create(:user) }

    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
    end

    it "promotes the placeholder Member to the invitation's Admin role" do
      invitee = create(:user, email_address: "newbie@example.com")
      # Callback created a Member membership; verify state before reconciliation.
      placeholder = shared_workspace.memberships.find_by!(user: invitee)
      expect(placeholder.role).to eq(member_role)

      invitation = create(:invitation,
                          invitable: shared_workspace,
                          role: admin_role,
                          email: "newbie@example.com",
                          invited_by: inviter)

      expect {
        invitation.accept!(invitee)
      }.not_to raise_error

      expect(shared_workspace.memberships.where(user: invitee).count).to eq(1)
      expect(placeholder.reload.role).to eq(admin_role)
    end

    it "no-ops when the invitation's role matches the placeholder Member role" do
      invitee = create(:user, email_address: "samerole@example.com")
      invitation = create(:invitation,
                          invitable: shared_workspace,
                          role: member_role,
                          email: "samerole@example.com",
                          invited_by: inviter)

      expect { invitation.accept!(invitee) }.not_to raise_error
      expect(shared_workspace.memberships.where(user: invitee).count).to eq(1)
    end
  end

  describe "member-invite role requirement (regression for client-variant change)" do
    it "still requires a role for a normal (non-client) workspace invite" do
      inv = build(:invitation, company_name: nil, role: nil)
      expect(inv).not_to be_valid
      expect(inv.errors[:role]).to be_present
    end

    it "accepts a member invite with a role and creates a membership" do
      workspace = create(:workspace)
      role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      inv = create(:invitation, invitable: workspace, role: role, company_name: nil)
      user = create(:user, :with_zero_workspaces)
      expect { inv.accept!(user) }.to change { workspace.memberships.kept.count }.by(1)
    end
  end

  # Wiring coverage: drive accept!/decline! and assert the notifier fires.
  # The notifiers themselves are specced in spec/notifiers/; without these,
  # the after_update_commit registrations could be deleted and the suite
  # would stay green.
  describe "notification wiring" do
    let(:workspace) { create(:workspace) }
    let(:inviter) { create(:user) }
    let(:invitation) { create(:invitation, invitable: workspace, invited_by: inviter, email: "invitee@example.com") }

    def recipients_of(notifier_type)
      Noticed::Notification.where(type: "#{notifier_type}::Notification").map(&:recipient)
    end

    describe "accepted (after_update_commit)" do
      it "notifies the inviter when someone else accepts" do
        acceptor = create(:user)
        expect {
          invitation.accept!(acceptor)
        }.to change { Noticed::Event.where(type: "WorkspaceInvitationAcceptedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceInvitationAcceptedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ inviter ])
      end

      it "does not notify when the inviter accepts their own invitation" do
        expect {
          invitation.accept!(inviter)
        }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationAcceptedNotifier").count }
      end
    end

    # Actor exclusion across the two notifiers that fire on one acceptance.
    # Before this, an owner-inviter got BOTH "Alan joined" and "alan@…
    # accepted your invitation" for the same event.
    describe "accepted — actor exclusion across both notifiers" do
      include ActiveJob::TestHelper

      it "gives an owner-inviter only the acceptance notice, and the invitee the member-added one" do
        ada = create(:user)
        create(:membership, :owner, user: ada, workspace: workspace)
        alan = create(:user)
        alan_email = alan.email_address
        invite = create(:invitation, invitable: workspace, invited_by: ada, email: alan_email)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
        ActionMailer::Base.deliveries.clear
        clear_enqueued_jobs

        invite.accept!(alan)
        perform_enqueued_jobs(only: Noticed::EventJob)
        perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
        perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

        expect(recipients_of("WorkspaceMemberAddedNotifier")).to eq([ alan ])
        expect(recipients_of("WorkspaceInvitationAcceptedNotifier")).to eq([ ada ])
        # The invitee still gets the welcome email; the inviter gets no email
        # for an event she performed herself.
        expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([ alan_email ])
      end

      it "keeps owners notified and the inviter thanked when a non-owner admin invited" do
        ada = create(:user)
        create(:membership, :owner, user: ada, workspace: workspace)
        edith = create(:user)
        create(:membership, :admin, user: edith, workspace: workspace)
        barb = create(:user)
        invite = create(:invitation, invitable: workspace, invited_by: edith, email: barb.email_address)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all

        invite.accept!(barb)

        expect(recipients_of("WorkspaceMemberAddedNotifier")).to contain_exactly(barb, ada)
        expect(recipients_of("WorkspaceInvitationAcceptedNotifier")).to eq([ edith ])
      end
    end

    describe "declined (after_update_commit)" do
      it "notifies the inviter" do
        expect {
          invitation.decline!
        }.to change { Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ inviter ])
      end

      it "does not notify when the declined invitation was addressed to the inviter" do
        self_invitation = create(:invitation, invitable: workspace, invited_by: inviter, email: inviter.email_address)
        expect {
          self_invitation.decline!
        }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier").count }
      end
    end
  end

  describe "activity workspace attribution" do
    it "records the invitation's resolved workspace even when Current.workspace is a different workspace" do
      workspace = create(:workspace)
      other_workspace = create(:workspace)
      Current.workspace = other_workspace

      invitation = create(:invitation, invitable: workspace)

      log = ActivityLog.where(trackable: invitation, action: "invitation.created").last
      expect(log.workspace).to eq(workspace)
    ensure
      Current.workspace = nil
    end

    it "records the project's workspace for a project invitation" do
      project = create(:project)
      Current.workspace = create(:workspace)

      invitation = create(:invitation, invitable: project)

      log = ActivityLog.where(trackable: invitation, action: "invitation.created").last
      expect(log.workspace).to eq(project.workspace)
    ensure
      Current.workspace = nil
    end
  end

  describe "block confirmation token (#951)" do
    let(:invitation) { create(:invitation) }

    it "round-trips while the invitation is pending" do
      token = invitation.generate_token_for(:block_confirmation)
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to eq(invitation)
    end

    it "dies when the status changes, however it changes" do
      token = invitation.generate_token_for(:block_confirmation)
      invitation.decline!
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to be_nil
    end

    it "survives a resend, which rotates the invitation token but not the invitation" do
      token = invitation.generate_token_for(:block_confirmation)
      invitation.resend!
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to eq(invitation)
    end

    it "expires with the invitation's own lifetime" do
      token = invitation.generate_token_for(:block_confirmation)
      travel_to(Invitation::BLOCK_TOKEN_LIFETIME.from_now + 1.minute) do
        expect(Invitation.find_by_token_for(:block_confirmation, token)).to be_nil
      end
    end
  end
end
