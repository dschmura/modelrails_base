require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe RequiredProductionConfigCatalog do
  let(:header) { "# Describes what production needs. Values go in credentials, deploy.yml or fnox; never here." }
  let(:local_entry) do
    {
      "home" => "credentials", "required" => "optional", "secret" => true,
      "purpose" => "Charges cards", "where" => "Stripe dashboard", "set_with" => "credentials:edit",
      "step" => 4, "example" => "<from Stripe → Developers → API keys>"
    }
  end

  def with_fork_root(local: nil, raw_local: nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.cp(Rails.root.join("config/required_production_config.yml"), File.join(dir, "config"))
      path = File.join(dir, "config/required_production_config.local.yml")
      File.write(path, raw_local || { "inputs" => local }.to_yaml) if local || raw_local
      yield Pathname(dir)
    end
  end

  it "loads the template entries" do
    catalog = described_class.load(root: Rails.root)

    expect(catalog.entries.map(&:key)).to include("RAILS_HOST", "smtp.password", "RAILS_MASTER_KEY")
    expect(catalog.entries.map(&:source).uniq).to eq([ :template ])
    expect(catalog.exclusions).to eq({})
  end

  it "appends a fork's local entries" do
    with_fork_root(local: { "stripe.secret_key" => local_entry }) do |root|
      last = described_class.load(root: root).entries.last

      expect(last.key).to eq("stripe.secret_key")
      expect(last.source).to eq(:local)
    end
  end

  it "rejects an unknown field, naming file and key" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("value" => "sk_live_1") }) do |root|
      expect { described_class.load(root: root) }
        .to raise_error(described_class::Invalid, /required_production_config\.local\.yml.*stripe\.secret_key.*value/)
    end
  end

  it "rejects a secret credential whose example isn't a placeholder" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("example" => "sk_live_51H") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key/)
    end
  end

  it "rejects a non-secret credential whose example isn't a placeholder" do
    with_fork_root(local: { "stripe.account" => local_entry.merge("secret" => false, "example" => "acct_123") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.account/)
    end
  end

  it "rejects a local entry that redefines a template key" do
    with_fork_root(local: { "RAILS_HOST" => local_entry.merge("home" => "env") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /RAILS_HOST/)
    end
  end

  it "rejects owner_rule in a local entry" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("owner_rule" => "host") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key.*owner_rule/)
    end
  end

  it "rejects a value outside the schema's vocabulary" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("home" => "vault") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key.*home/)
    end
  end

  it "accepts the conditional forms of required" do
    conditional = local_entry.merge("required" => { "when_env_set" => "STRIPE_ON" })

    with_fork_root(local: { "stripe.secret_key" => conditional }) do |root|
      expect(described_class.load(root: root).entries.last.required).to eq({ "when_env_set" => "STRIPE_ON" })
    end
  end

  it "reports a YAML syntax error as Invalid" do
    with_fork_root(raw_local: "inputs: [unclosed") do |root|
      expect { described_class.load(root: root) }
        .to raise_error(described_class::Invalid, /required_production_config\.local\.yml/)
    end
  end

  it "merges exclusions from both files" do
    with_fork_root(raw_local: { "exclusions" => { "STRIPE_DEBUG" => "Dev only" } }.to_yaml) do |root|
      expect(described_class.load(root: root).exclusions).to eq({ "STRIPE_DEBUG" => "Dev only" })
    end
  end

  it "puts each input in the quickstart step that handles it" do
    steps = described_class.load(root: Rails.root).entries.group_by { |entry| entry.home }
                           .transform_values { |entries| entries.map(&:step).uniq.sort }

    expect(steps.fetch("credentials")).to eq([ 4 ])
    expect(steps.fetch("kamal_secret")).to eq([ 4 ])
    expect(steps.fetch("env")).to eq([ 4, 6 ])
  end

  it "names where each env input is set, and says something specific about its value" do
    env = described_class.load(root: Rails.root).entries.select { |entry| entry.home == "env" }

    expect(env.map(&:set_with).uniq).to eq([ "config/deploy.yml → env.clear" ])
    expect(env.map(&:where).uniq.size).to eq(env.size)
  end

  it "starts the template file with the header line" do
    expect(File.foreach(Rails.root.join("config/required_production_config.yml")).first.chomp).to eq(header)
  end
end
