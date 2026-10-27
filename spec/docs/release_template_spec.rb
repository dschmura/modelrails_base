require "rails_helper"

RSpec.describe "the release pull request template" do
  let(:template) { Rails.root.join(".github/PULL_REQUEST_TEMPLATE/release.md").read }
  let(:guide) { Rails.root.join("app/docs/developer/releasing.md").read }

  it "records the commit reviewed on staging" do
    expect(template).to match(/reviewed on staging/i)
  end

  it "ships only that commit, so a push after review cannot reach production unseen" do
    expect(template).to include("--match-head-commit")
  end

  it "lists what was held back, so next can restore it after the merge-back" do
    expect(template).to match(/held back/i)
  end

  it "is how the releasing guide opens a release" do
    expect(guide).to include("--body-file .github/PULL_REQUEST_TEMPLATE/release.md")
  end

  it "says how to switch a ruleset off in an emergency, and back on" do
    expect(guide).to include("enforcement=disabled").and include("bin/branch-rules")
  end
end
