require "rails_helper"
require "tmpdir"

RSpec.describe ReleaseFlow::Config do
  let(:root) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.rm_rf(root) }

  it "names this repository's branches and workflows when there's no .release_flow.yml" do
    config = described_class.load(root.to_s)

    expect(config).to have_attributes(integration_branch: "next", production_branch: "main",
                                      ci_workflow: "ci.yml", staging_workflow: "deploy.yml",
                                      guide: "/docs/developer/releasing", template: nil)
  end

  it "takes what .release_flow.yml sets and keeps the defaults for the rest" do
    root.join(".release_flow.yml").write("integration_branch: develop\nci_workflow: test.yml\n")

    expect(described_class.load(root.to_s)).to have_attributes(integration_branch: "develop", ci_workflow: "test.yml",
                                                               production_branch: "main")
  end

  it "refuses a setting it doesn't know, naming the ones it does, so a typo can't be ignored" do
    root.join(".release_flow.yml").write("intergration_branch: develop\n")

    expect { described_class.load(root.to_s) }
      .to raise_error(ReleaseFlow::Error, /intergration_branch.*integration_branch/m)
  end
end
