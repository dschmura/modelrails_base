require "rails_helper"
require "rake"

RSpec.describe "Tenancy rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  describe "tenancy:owner_setup_link" do
    let(:owner) { create(:user, email_address: "owner@acme.test") }

    around do |example|
      original = ENV["APP_HOST"]
      ENV["APP_HOST"] = "acme.example.com"
      example.run
      original.nil? ? ENV.delete("APP_HOST") : ENV["APP_HOST"] = original
    end

    def run_task(*args)
      Rake::Task["tenancy:owner_setup_link"].reenable
      captured = StringIO.new
      original = $stdout
      $stdout = captured
      Rake::Task["tenancy:owner_setup_link"].invoke(*args)
      captured.string
    ensure
      $stdout = original
    end

    it "prints a link on the configured host, valid for the token lifetime" do
      owner

      output = run_task(owner.email_address)

      expect(output).to include("acme.example.com")
      expect(output).to include(owner.password_reset_token_expires_in.inspect) # e.g. "15 minutes"
    end

    it "mints a usable token — the printed link resolves back to the owner" do
      owner

      output = run_task(owner.email_address)

      token = output[%r{/passwords/([^/]+)/edit}, 1]
      expect(token).to be_present
      expect(User.find_by_password_reset_token(token)).to eq(owner)
    end

    it "falls back to TENANCY_OWNER_EMAIL when no email arg is given" do
      owner
      ENV["TENANCY_OWNER_EMAIL"] = owner.email_address

      output = run_task

      expect(output).to include(owner.email_address)
    ensure
      ENV.delete("TENANCY_OWNER_EMAIL")
    end
  end
end
