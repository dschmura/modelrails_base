require "rails_helper"

RSpec.describe LifecycleHelper, type: :helper do
  # The vocabulary rule: "suspended"/"discarded" are internal names only.
  # This helper is the sole legal display path for lifecycle state.
  it "maps every status symbol to its user-facing label" do
    workspace = create(:workspace)
    expect(helper.lifecycle_status_label(workspace)).to eq("Active")

    workspace.archive!
    expect(helper.lifecycle_status_label(workspace)).to eq("Archived")

    workspace.suspend!
    expect(helper.lifecycle_status_label(workspace)).to eq("Locked")

    workspace.unsuspend!
    workspace.discard!
    expect(helper.lifecycle_status_label(workspace)).to eq("Deleted")
  end

  it "defines all four lifecycle_status keys (no titleize fallback possible)" do
    %w[active archived suspended discarded].each do |status|
      expect(I18n.exists?("lifecycle_status.#{status}")).to be(true),
        "missing lifecycle_status.#{status} — labels must come from I18n, never status.to_s"
    end
  end

  it "no view or helper titleizes/humanizes a lifecycle status (vocabulary leak guard)" do
    offenders = Dir[Rails.root.join("app/{views,helpers}/**/*.{erb,rb}")].filter_map do |file|
      content = File.read(file)
      file if content.match?(/status\s*(\)|\.to_s)?\s*\.\s*(titleize|humanize)/)
    end
    expect(offenders).to be_empty,
      "lifecycle labels must render via lifecycle_status_label, never " \
      "status titleize/humanize (leaks 'Suspended'/'Discarded'): #{offenders.join(", ")}"
  end
end
