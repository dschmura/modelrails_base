# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/fork-shaped-specs")

RSpec.describe ForkShapedSpecs do
  let(:output) { StringIO.new }

  it "picks every spec file that names deploy.yml, and nothing else" do
    files = described_class.spec_files(Rails.root.to_s)

    expect(files).to include("spec/bin/deploy_setup_spec.rb", "spec/docs/deploy_card_and_switches_spec.rb", "spec/bin/fork_spec.rb")
    expect(files).to all(end_with("_spec.rb"))
  end

  it "does nothing in a fork, whose own suite already runs in a fork's shape" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".fork.yml"), "name: acme\n")

      expect(described_class.new(root: dir, output:).run).to eq(0)
      expect(output.string).to include("This is a fork")
    end
  end

  it "makes a fork of the committed tree the way the quickstart does" do
    Dir.mktmpdir do |dir|
      fork = described_class.new(root: Rails.root.to_s, output:).make_fork(dir)
      deploy = File.read(File.join(fork, "config/deploy.yml"))

      expect(File.read(File.join(fork, ".fork.yml"))).to include("name: acme_shop")
      expect(deploy).to include("service: acme_shop", %(ENV.fetch("KAMAL_HOST")), "RAILS_HOST: app.acme-garden.com", "user: deploy")
      expect(deploy).not_to include("# RAILS_HOST: app.yourdomain.com")
    end
  end

  it "shares gems installed under vendor/bundle without leaving bin/fork an unclean tree" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, "root")
      system(CleanGitEnv::HASH, "git", "clone", "-q", Rails.root.to_s, root, exception: true)
      FileUtils.mkdir_p(File.join(root, "vendor/bundle"))

      fork = described_class.new(root:, output:).make_fork(File.join(dir, "forks").tap { FileUtils.mkdir_p(it) })

      expect(File.symlink?(File.join(fork, "vendor/bundle"))).to be(true)
      expect(File).to exist(File.join(fork, ".fork.yml"))
    end
  end
end
