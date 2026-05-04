# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "last_known_browsers column" do
    it "exists on the users table with a JSON default of []" do
      expect(User.column_names).to include("last_known_browsers")
      column = User.columns_hash["last_known_browsers"]
      expect(column.null).to eq(false)
      # SQLite stores JSON as text; the runtime default for a fresh User is [].
      expect(User.new.last_known_browsers).to eq([])
    end
  end

  describe ".browser_digest (single source of truth)" do
    it 'produces a deterministic SHA256 of "{ua} {os}"' do
      expected = Digest::SHA256.hexdigest("agent macos")
      expect(User.browser_digest("agent", "macos")).to eq expected
    end
  end

  describe "#seen_browser? and #record_browser!" do
    let(:user) { create(:user) }
    let(:user_agent) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }
    let(:os) { "Macintosh" }

    it "returns false when the browser has not been recorded" do
      expect(user.seen_browser?(user_agent, os)).to be false
    end

    it "appends an entry with digest, first_seen_at, and last_seen_at" do
      freeze_time do
        user.record_browser!(user_agent, os)
        entry = user.reload.last_known_browsers.first
        expect(entry).to include(
          "digest" => Digest::SHA256.hexdigest("#{user_agent} #{os}"),
          "first_seen_at" => Time.current.iso8601,
          "last_seen_at"  => Time.current.iso8601
        )
      end
    end

    it "returns true after a previous record_browser!" do
      user.record_browser!(user_agent, os)
      expect(user.reload.seen_browser?(user_agent, os)).to be true
    end

    it "treats different (ua, os) pairs as distinct browsers" do
      user.record_browser!(user_agent, os)
      expect(user.reload.seen_browser?(user_agent, "Windows")).to be false
    end

    it "updates last_seen_at on re-record but keeps first_seen_at stable" do
      first_time = Time.zone.parse("2026-01-01 12:00:00")
      later      = Time.zone.parse("2026-01-02 09:30:00")

      travel_to(first_time) do
        user.record_browser!(user_agent, os)
      end

      travel_to(later) do
        user.record_browser!(user_agent, os)
      end

      entry = user.reload.last_known_browsers.first
      expect(user.reload.last_known_browsers.size).to eq 1
      expect(entry["first_seen_at"]).to eq first_time.iso8601
      expect(entry["last_seen_at"]).to eq later.iso8601
    end
  end
end
