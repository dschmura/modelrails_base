require "rails_helper"

RSpec.describe Project, type: :model do
  let(:workspace) { create(:workspace) }
  let(:project) { create(:project, workspace: workspace) }

  describe "#status" do
    it "is :active, then :archived, with :discarded taking precedence" do
      expect(project.status).to eq(:active)
      project.archive!
      expect(project.status).to eq(:archived)
      project.discard!
      expect(project.status).to eq(:discarded)
    end
  end

  describe "guards (via the workspace's suspended state)" do
    before { workspace.suspend! }

    it "blocks archive!" do
      expect { project.archive! }.to raise_error(Suspendable::SuspendedError)
      expect(project.reload.archived_at).to be_nil
    end

    it "blocks unarchive!" do
      workspace.unsuspend!
      project.archive!
      workspace.suspend!
      expect { project.unarchive! }.to raise_error(Suspendable::SuspendedError)
    end

    it "blocks discard!" do
      expect { project.discard! }.to raise_error(Suspendable::SuspendedError)
      expect(project.reload).not_to be_discarded
    end
  end

  describe "idempotency" do
    it "archives once across repeat calls" do
      project.archive!
      original = project.reload.archived_at
      expect { travel_to(1.hour.from_now) { project.archive! } }
        .not_to change { ActivityLog.count }
      expect(project.reload.archived_at).to eq(original)
    end
  end
end
