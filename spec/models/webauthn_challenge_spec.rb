require "rails_helper"

RSpec.describe WebauthnChallenge do
  it "consumes a stored challenge exactly once" do
    WebauthnChallenge.store(challenge: "abc", purpose: "authentication")
    expect(WebauthnChallenge.consume!("abc", purpose: "authentication")).to be_present
    expect(WebauthnChallenge.consume!("abc", purpose: "authentication")).to be_nil # replay rejected
  end

  it "rejects an expired challenge" do
    WebauthnChallenge.store(challenge: "old", purpose: "authentication")
    WebauthnChallenge.find_by(challenge: "old").update_column(:expires_at, 1.minute.ago)
    expect(WebauthnChallenge.consume!("old", purpose: "authentication")).to be_nil
  end

  it "rejects a challenge consumed for the wrong purpose" do
    WebauthnChallenge.store(challenge: "reg", purpose: "registration")
    expect(WebauthnChallenge.consume!("reg", purpose: "authentication")).to be_nil
  end
end
