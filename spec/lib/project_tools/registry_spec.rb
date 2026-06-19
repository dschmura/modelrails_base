require "rails_helper"

RSpec.describe ProjectTools::Registry do
  # The registry holds module-level state populated at boot; save/restore it so
  # examples that register extra tools don't leak into the rest of the suite.
  around do |example|
    original = described_class.all.dup
    example.run
    described_class.all.replace(original)
  end

  it "ships docs as an implemented, default-on tool" do
    docs = described_class.find(:docs)
    expect(docs).to be_present
    expect(docs.implemented?).to be(true)
    expect(docs.default_enabled?).to be(true)
    expect(docs.path_helper).to eq(:workspace_project_resources_path)
  end

  it "exposes default_keys as strings for implemented default-on tools" do
    expect(described_class.default_keys).to include("docs")
    expect(described_class.default_keys).to all(be_a(String))
  end

  it "refuses to register an implemented tool with no path_helper" do
    expect {
      described_class.register(key: :broken, path_helper: nil, implemented: true)
    }.to raise_error(ArgumentError, /path_helper/)
  end

  it "treats only implemented tools as toggleable" do
    described_class.register(key: :future, default_enabled: false, implemented: false)
    expect(described_class.toggleable.map(&:key)).not_to include(:future)
  end

  it "resolves a tool's name from i18n" do
    expect(described_class.find(:docs).name).to eq("Docs & Files")
  end

  it "falls back to a humanized key when no locale entry exists" do
    described_class.register(key: :time_tracking, path_helper: :workspace_project_resources_path)
    tool = described_class.find(:time_tracking)
    expect(tool.name).to eq("Time tracking")
  end
end
