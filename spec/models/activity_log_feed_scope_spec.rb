require "rails_helper"

# An unclassified Trackable type falls out of the feed (#1154); this derives the
# includers so a new one fails here by name.
RSpec.describe "ActivityLog feed partitions" do
  let(:trackable_includers) do
    Dir[Rails.root.join("app/models/**/*.rb")].filter_map do |file|
      next unless File.read(file).match?(/^\s*include Trackable\b/)

      file.delete_prefix("#{Rails.root}/app/models/").delete_suffix(".rb").camelize
    end
  end

  # POSITIVE CONTROL — a scan that finds nothing would classify nothing and
  # pass. These are the models the partition claims to cover.
  it "sees the Trackable models it is partitioning" do
    expect(trackable_includers).to include("Workspace", "Membership", "Project", "Resource", "Invitation")
  end

  it "classifies every Trackable model into a partition" do
    classified = ActivityLog::WORKSPACE_LEVEL_TRACKABLES +
                 ActivityLog::PROJECT_LEVEL_TRACKABLES +
                 ActivityLog::POLYMORPHIC_TRACKABLES

    unclassified = trackable_includers - classified

    expect(unclassified).to be_empty, <<~MESSAGE
      These models record activity but no feed partition names them, so their rows
      are invisible on the workspace overview:

        #{unclassified.join("\n  ")}

      Add each to ActivityLog::WORKSPACE_LEVEL_TRACKABLES (any member may read it),
      to PROJECT_LEVEL_TRACKABLES (it follows its project's visibility), or to
      POLYMORPHIC_TRACKABLES with a clause in for_workspace_feed saying what it
      hangs off.
    MESSAGE
  end

  # The reverse: an entry that no longer records activity can never match.
  it "names no partition entry that is not a Trackable model" do
    classified = ActivityLog::WORKSPACE_LEVEL_TRACKABLES +
                 ActivityLog::PROJECT_LEVEL_TRACKABLES +
                 ActivityLog::POLYMORPHIC_TRACKABLES

    expect(classified - trackable_includers).to be_empty,
      "a feed partition names a model that does not include Trackable, so the clause is dead"
  end
end
