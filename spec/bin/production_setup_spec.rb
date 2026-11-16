# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/production-setup")

RSpec.describe ProductionSetup do
  let(:output) { StringIO.new }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @root.join("bin").mkpath
      @root.join("config/credentials").mkpath
      ProductionSetup::STEPS.each { |step| stub_step(step) }
      example.run
    end
  end

  def calls = @root.join("calls.log").exist? ? @root.join("calls.log").read.split : []

  def stub_step(step, exit_code: 0)
    script = @root.join(step)
    script.write("#!/bin/sh\necho #{step} >> #{@root.join('calls.log')}\nexit #{exit_code}\n")
    script.chmod(0o755)
  end

  def stored_login(text)
    key = SecureRandom.hex(16)
    @root.join("config/credentials/production.key").write(key)
    ActiveSupport::EncryptedFile.new(content_path: @root.join("config/credentials/production.yml.enc"),
                                     key_path: @root.join("config/credentials/production.key"),
                                     env_key: "UNUSED_IN_SPEC", raise_if_missing_key: true).write(text)
  end

  def run_setup = described_class.new(root: @root.to_s, env: {}, output:).run

  it "runs mail, encryption, then fnox, in that order" do
    expect(run_setup).to eq(0)
    expect(calls).to eq(%w[bin/mail-setup bin/encryption-setup bin/fnox-setup])
  end

  it "skips mail when a login is already stored, and says so" do
    stored_login("smtp:\n  user_name: u\n  password: p\n")

    run_setup

    expect(calls).to eq(%w[bin/encryption-setup bin/fnox-setup])
    expect(output.string).to include("bin/mail-setup")
  end

  it "runs mail when the credentials hold no login" do
    stored_login("secret_key_base: abc\n")

    run_setup

    expect(calls.first).to eq("bin/mail-setup")
  end

  it "stops at the first failure and names the step to rerun" do
    stub_step("bin/encryption-setup", exit_code: 1)

    expect(run_setup).to eq(1)
    expect(calls).to eq(%w[bin/mail-setup bin/encryption-setup])
    expect(output.string).to include("bin/encryption-setup")
    expect(output.string).not_to include("Commit")
  end

  it "ends with what to commit and what to back up, once" do
    run_setup

    expect(output.string.scan("Commit").size).to eq(1)
    expect(output.string).to include("config/credentials/production.yml.enc", "fnox.toml",
                                      "config/credentials/production.key", "~/.config/fnox/age.txt",
                                      "bin/rails deploy:check", "http://localhost:3000/docs/developer/quickstart")
  end
end
