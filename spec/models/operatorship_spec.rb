require "rails_helper"

RSpec.describe Operatorship do
  let(:user) { create(:user) }
  let(:granter) { create(:user) }

  describe ".grant!" do
    it "creates a kept operatorship and a STRICT admin-tier audit row in one transaction" do
      # Force before the block: both are lazy lets, and creating a user fires
      # onboarding callbacks that write their own activity rows (R5).
      user
      granter

      expect {
        described_class.grant!(user: user, granted_by: granter)
      }.to change(described_class.kept, :count).by(1)
        .and change(ActivityLog, :count).by(1)

      row = ActivityLog.order(:id).last
      expect(row.action).to eq("operatorship.granted")
      expect(row.actor).to eq(granter)
      expect(row.trackable).to eq(user)
      expect(row.workspace_id).to be_nil
      expect(row.visibility).to eq("admin")
    end

    it "rolls back the operatorship when the audit row cannot be written" do
      user
      granter
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { described_class.grant!(user: user, granted_by: granter) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(described_class.count).to eq(0)
    end

    it "refuses a second kept operatorship for the same user at the database" do
      described_class.grant!(user: user)

      expect { described_class.grant!(user: user) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new grant after a revoke" do
      described_class.grant!(user: user).revoke!

      expect { described_class.grant!(user: user) }.to change(described_class.kept, :count).by(1)
    end
  end

  describe "#revoke!" do
    it "discards the row and writes the revoked audit row with the revoker as actor" do
      operatorship = described_class.grant!(user: user)
      granter # force before the block: same lazy-let onboarding issue as R5.

      expect { operatorship.revoke!(revoked_by: granter) }.to change(ActivityLog, :count).by(1)
      expect(operatorship.reload).to be_discarded
      row = ActivityLog.order(:id).last
      expect(row.action).to eq("operatorship.revoked")
      expect(row.actor).to eq(granter)
      expect(row.visibility).to eq("admin")
    end

    it "rolls back the discard when the audit row cannot be written" do
      operatorship = described_class.grant!(user: user)
      granter # force before the stub: same lazy-let onboarding issue as R5.
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { operatorship.revoke!(revoked_by: granter) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(operatorship.reload).to be_kept
    end

    it "is idempotent: a second revoke! writes no audit row and leaves discarded_at unchanged" do
      operatorship = described_class.grant!(user: user)
      operatorship.revoke!(revoked_by: granter)
      discarded_at = operatorship.reload.discarded_at

      result = nil
      expect {
        result = operatorship.revoke!(revoked_by: granter)
      }.not_to change(ActivityLog, :count)

      expect(operatorship.reload.discarded_at).to eq(discarded_at)
      expect(result).to be(false)
    end
  end

  it "keeps both audit actions behind the security retention floor" do
    expect(ActivityLog::SECURITY_ACTIONS).to include("operatorship.granted", "operatorship.revoked")
  end

  describe "#revoke_unless_last!" do
    it "revokes and returns true when another kept operatorship remains" do
      operatorship = described_class.grant!(user: user)
      described_class.grant!(user: create(:user))

      expect(operatorship.revoke_unless_last!(revoked_by: granter)).to be(true)
      expect(operatorship.reload).to be_discarded
    end

    it "refuses and returns false when it is the last kept operatorship, writing no audit row" do
      operatorship = described_class.grant!(user: user)
      granter # force before the block: same lazy-let onboarding issue as R5.

      expect {
        expect(operatorship.revoke_unless_last!(revoked_by: granter)).to be(false)
      }.not_to change(ActivityLog, :count)
      expect(operatorship.reload).to be_kept
    end

    it "returns false without writing a second audit row for an already-discarded operatorship" do
      operatorship = described_class.grant!(user: user)
      described_class.grant!(user: create(:user))
      operatorship.revoke!(revoked_by: granter)
      discarded_at = operatorship.reload.discarded_at

      expect {
        expect(operatorship.revoke_unless_last!(revoked_by: granter)).to be(false)
      }.not_to change(ActivityLog, :count)
      expect(operatorship.reload.discarded_at).to eq(discarded_at)
    end

    # Sequential stand-in for the concurrent case this guard exists for
    # (two operators revoking two DIFFERENT rows in the same window): SQLite's
    # writer lock (BEGIN IMMEDIATE, /docs/developer/architecture) serializes
    # any real race into some sequential order, so proving the invariant holds
    # across every sequential order proves it for the concurrent case too.
    it "never lets kept operators reach zero when two different rows are both revoked" do
      first = described_class.grant!(user: user)
      second = described_class.grant!(user: create(:user))

      expect(first.revoke_unless_last!(revoked_by: granter)).to be(true)
      expect(second.revoke_unless_last!(revoked_by: granter)).to be(false)

      expect(described_class.kept.count).to eq(1)
      expect(second.reload).to be_kept
    end
  end
end
