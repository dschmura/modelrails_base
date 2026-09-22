require "rails_helper"

# The overview feed decides what a member may read by partitioning rows on
# their trackable type (#1154). A type in neither partition falls OUT of the
# feed — the safe default for a leak fix, but silent, so a fork that adds a
# Trackable model would quietly lose its rows from the feed and never be told.
#
# This is the telling. It derives the population from the models themselves
# rather than restating a list, so the day a sixth includer lands it fails
# here naming it.
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

  # The other direction: a partition naming a model that no longer records
  # activity is a clause that can never match.
  it "names no partition entry that is not a Trackable model" do
    classified = ActivityLog::WORKSPACE_LEVEL_TRACKABLES +
                 ActivityLog::PROJECT_LEVEL_TRACKABLES +
                 ActivityLog::POLYMORPHIC_TRACKABLES

    expect(classified - trackable_includers).to be_empty,
      "a feed partition names a model that does not include Trackable, so the clause is dead"
  end
end
