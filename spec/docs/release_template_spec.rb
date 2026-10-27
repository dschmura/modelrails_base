require "rails_helper"

RSpec.describe "the release pull request template" do
  let(:template) { Rails.root.join(".github/PULL_REQUEST_TEMPLATE/release.md").read }
  let(:guide) { Rails.root.join("app/docs/developer/releasing.md").read }

  it "records the commit reviewed on staging" do
    expect(template).to match(/reviewed on staging/i)
  end

  it "ships with bin/release, which merges only that commit" do
    expect(template).to include("bin/release ship <this PR> <the commit above>")
  end

  it "lists what was held back, so next can restore it after the merge-back" do
    expect(template).to match(/held back/i)
  end

  it "is filled in by bin/release cut, which the guide names" do
    expect(template).to include("<!-- bin/release cut fills this")
    expect(guide).to include("bin/release cut")
  end

  it "says how to switch a ruleset off in an emergency, and back on" do
    expect(guide).to include("enforcement=disabled").and include("bin/branch-rules")
  end
end
