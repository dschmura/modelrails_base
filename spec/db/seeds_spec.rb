require "rails_helper"

# Exercises the :shared (Single-tenant) bootstrap branch of db/seeds.rb. The
# production branch logs a password-set link for out-of-band delivery, since
# email infra may not be ready on first boot — so the log must give the
# operator everything they need: the URL, how long it stays valid, and where
# the workspace lives.
RSpec.describe "db/seeds.rb :shared bootstrap", type: :request do
  let(:env_vars) do
    {
      "TENANCY_SHARED_WORKSPACE_SLUG" => "acme",
      "TENANCY_SHARED_WORKSPACE_NAME" => "Acme Inc",
      "TENANCY_OWNER_EMAIL" => "owner@acme.test",
      "APP_HOST" => "acme.example.com"
    }
  end

  around do |example|
    originals = env_vars.transform_values { |_| :__unset__ }
    env_vars.each { |k, v| originals[k] = ENV[k]; ENV[k] = v }
    example.run
    originals.each { |k, v| v == :__unset__ ? ENV.delete(k) : ENV[k] = v }
  end

  before do
    allow(TenancyConfig).to receive(:shared?).and_return(true)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
  end

  it "logs the password-set URL, its expiry duration, and the workspace URL" do
    logged = []
    allow(Rails.logger).to receive(:info) { |msg| logged << msg }

    Rails.application.load_seed

    tenancy_line = logged.find { |m| m.to_s.include?("[tenancy]") }
    expect(tenancy_line).to be_present

    owner = User.find_by!(email_address: "owner@acme.test")
    expect(tenancy_line).to include(owner.password_reset_token_expires_in.inspect) # e.g. "15 minutes"
    expect(tenancy_line).to include("/workspaces/acme") # operator's destination
  end
end
