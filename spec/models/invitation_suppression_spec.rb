require "rails_helper"

RSpec.describe "Invitation suppression schema", type: :model do
  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }

  def raw_invitation!(email:, invitable: workspace, invited_by: inviter, suppressed_at: nil)
    inv = build(:invitation, email: email, invitable: invitable, invited_by: invited_by)
    inv.suppressed_at = suppressed_at
    inv.save!(validate: false)
    inv
  end

  describe "invitation_blocks uniqueness (P1 — reaches the index, not the validation)" do
    it "rejects a duplicate (email, inviter) pair at the database" do
      InvitationBlock.insert_all!([ { inviter_id: inviter.id, email: "dup@example.com",
                                      created_at: Time.current, updated_at: Time.current } ])
      expect {
        InvitationBlock.insert_all!([ { inviter_id: inviter.id, email: "dup@example.com",
                                        created_at: Time.current, updated_at: Time.current } ])
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "pending_live slot (P2)" do
    it "rejects two live pending invitations for the same (email, invitable)" do
      raw_invitation!(email: "live@example.com")
      expect { raw_invitation!(email: "live@example.com", invited_by: create(:user)) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "admits the pair when one row is suppressed" do
      raw_invitation!(email: "ghosted@example.com", suppressed_at: Time.current)
      expect { raw_invitation!(email: "ghosted@example.com", invited_by: create(:user)) }
        .not_to raise_error
    end
  end

  describe "pending_ghosts slot (P3)" do
    it "rejects two ghosts for the same (email, invitable, inviter)" do
      raw_invitation!(email: "g@example.com", suppressed_at: Time.current)
      expect { raw_invitation!(email: "g@example.com", suppressed_at: Time.current) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "admits a second ghost from a different inviter" do
      raw_invitation!(email: "g2@example.com", suppressed_at: Time.current)
      expect {
        raw_invitation!(email: "g2@example.com", suppressed_at: Time.current,
                        invited_by: create(:user))
      }.not_to raise_error
    end
  end

  describe "planner uses pending_live (P4 — the scoped query implies the predicate)" do
    it "names index_invitations_pending_live" do
      pending "unsuppressed scope lands in the suppression task"
      plan = Invitation.pending.unsuppressed
                       .where(email: "x@example.com", invitable_type: "Workspace", invitable_id: workspace.id)
                       .explain.inspect
      expect(plan).to include("index_invitations_pending_live")
    end
  end
end
