require "rails_helper"

RSpec.describe GravatarService do
  describe ".check" do
    let(:email) { "user@example.com" }
    let(:hash) { Digest::SHA256.hexdigest(email.strip.downcase) }
    let(:gravatar_uri) { "https://www.gravatar.com/avatar/#{hash}?d=404" }

    it "returns true when Gravatar exists" do
      stub_request(:head, gravatar_uri).to_return(status: 200)
      expect(described_class.check(email)).to be true
    end

    it "returns false when Gravatar does not exist" do
      stub_request(:head, gravatar_uri).to_return(status: 404)
      expect(described_class.check(email)).to be false
    end

    it "returns false on network error" do
      stub_request(:head, gravatar_uri).to_timeout
      expect(described_class.check(email)).to be false
    end

    it "normalizes email before hashing" do
      normalized_hash = Digest::SHA256.hexdigest("user@example.com")
      stub_request(:head, "https://www.gravatar.com/avatar/#{normalized_hash}?d=404")
        .to_return(status: 200)
      expect(described_class.check("  User@Example.COM  ")).to be true
    end
  end
end
