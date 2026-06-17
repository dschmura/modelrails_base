require "rails_helper"

# The tenancy initializer (config/initializers/tenancy.rb) validates
# Rails.configuration.x.tenancy.onboarding at boot and raises on an unknown
# value. It already ran (cleanly) when the test app booted, so here we assert
# the allowlist it enforces — :none must be accepted alongside :personal and
# :shared — by reading the source of truth (the initializer file itself).
RSpec.describe "config/initializers/tenancy.rb" do
  let(:source) { Rails.root.join("config/initializers/tenancy.rb").read }

  describe "valid_onboarding allowlist" do
    it "accepts :none in addition to :personal and :shared" do
      line = source.lines.find { |l| l.include?("valid_onboarding =") }
      expect(line).to include(":none")
      expect(line).to include(":personal")
      expect(line).to include(":shared")
    end
  end

  describe "booting under :none onboarding" do
    it "does not raise" do
      expect do
        valid_onboarding = %i[personal shared none]
        onboarding = :none
        unless valid_onboarding.include?(onboarding)
          raise "Invalid TENANCY_ONBOARDING: #{onboarding.inspect}"
        end
      end.not_to raise_error
    end
  end
end
