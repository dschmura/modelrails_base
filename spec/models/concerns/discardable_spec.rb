require "rails_helper"

RSpec.describe Discardable, type: :model do
  # Use Workspace as the host model (includes Discardable)
  let(:record) { create(:workspace) }

  describe "#discard!" do
    it "sets discarded_at to current time" do
      freeze_time do
        record.discard!
        expect(record.discarded_at).to eq(Time.current)
      end
    end
  end

  describe "#undiscard!" do
    it "clears discarded_at" do
      record.discard!
      record.undiscard!
      expect(record.discarded_at).to be_nil
    end
  end

  describe "scopes" do
    let!(:kept_record) { create(:workspace) }
    let!(:discarded_record) { create(:workspace).tap(&:discard!) }

    it "kept excludes discarded" do
      expect(Workspace.kept).to include(kept_record)
      expect(Workspace.kept).not_to include(discarded_record)
    end

    it "discarded includes only discarded" do
      expect(Workspace.discarded).to include(discarded_record)
      expect(Workspace.discarded).not_to include(kept_record)
    end
  end
end
