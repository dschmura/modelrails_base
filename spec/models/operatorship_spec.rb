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
  end

  it "keeps both audit actions behind the security retention floor" do
    expect(ActivityLog::SECURITY_ACTIONS).to include("operatorship.granted", "operatorship.revoked")
  end
end
