require "rails_helper"

RSpec.describe "Sessions new-device detection", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  describe "POST /session — successful sign-in" do
    it "fires SignInFromNewDeviceNotifier on the first sign-in from a browser" do
      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }
      }.to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }.by(1)
    end

    it "records the browser fingerprint on the user" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }

      expect(user.reload.last_known_browsers).not_to be_empty
      entry = user.last_known_browsers.first
      expect(entry).to include("digest", "first_seen_at", "last_seen_at")
    end

    it "does NOT re-fire the notifier on a subsequent sign-in from the same browser" do
      ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15"
      # First sign-in primes the fingerprint.
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => ua }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => ua }
      }.not_to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }
    end

    it "fires the notifier when the user signs in from a different browser" do
      first_ua  = "Mozilla/5.0 (Macintosh) Safari"
      second_ua = "Mozilla/5.0 (Windows NT 10.0) Chrome/120"

      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => first_ua }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => second_ua }
      }.to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }.by(1)
    end

    # Security regression guard: prior to folding the browser digest into the
    # idempotency_key, two distinct devices signing in within the same minute
    # would collapse on the dedup index — the second alert would be silently
    # swallowed. That's a real attack surface (phisher signs in seconds after
    # the legit user). Lock this in with a fully-realistic request flow that
    # does NOT use travel/time-helpers.
    it "fires for two distinct devices signing in within the same minute" do
      first_ua  = "Mozilla/5.0 (Macintosh) Safari"
      second_ua = "Mozilla/5.0 (Windows NT 10.0) Chrome/120"

      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => first_ua }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => second_ua }
      }.to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }.by(1)

      events = Noticed::Event.where(type: "SignInFromNewDeviceNotifier")
      expect(events.count).to eq 2
      expect(events.pluck(:idempotency_key).uniq.size).to eq 2
    end

    it "does not fire on a failed sign-in attempt" do
      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "wrongpassword"
        }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh)" }
      }.not_to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }
    end
  end
end
