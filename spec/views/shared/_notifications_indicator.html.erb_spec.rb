require "rails_helper"

RSpec.describe "shared/_notifications_indicator.html.erb", type: :view do
  let(:render_indicator) do
    ->(summary:, surface: :avatar) do
      render partial: "shared/notifications_indicator", locals: { summary: summary, surface: surface }
    end
  end

  context "when summary[:severity] is nil (no unread)" do
    it "renders no dot element (a stable empty placeholder keeps the turbo-frame happy without painting anything)" do
      render_indicator.call(summary: { count: 0, severity: nil })
      expect(rendered).not_to include("rounded-full")
      expect(rendered).not_to include("aria-hidden")
    end
  end

  describe "severity colors" do
    it "uses bg-danger-strong + motion-safe:animate-pulse for :danger" do
      render_indicator.call(summary: { count: 1, severity: :danger })
      expect(rendered).to match(/bg-danger-strong/)
      expect(rendered).to match(/motion-safe:animate-pulse/)
    end

    it "uses bg-warning and does NOT pulse for :warning" do
      render_indicator.call(summary: { count: 1, severity: :warning })
      expect(rendered).to match(/bg-warning(\b|")/)
      expect(rendered).not_to match(/animate-pulse/)
    end

    it "uses bg-info and does NOT pulse for :info" do
      render_indicator.call(summary: { count: 1, severity: :info })
      expect(rendered).to match(/bg-info(\b|")/)
      expect(rendered).not_to match(/animate-pulse/)
    end
  end

  describe "structural classes" do
    before { render_indicator.call(summary: { count: 1, severity: :danger }) }

    it "is exactly w-2 h-2 (8px) — small enough to read as a dot, large enough to perceive at AAA luminance" do
      expect(rendered).to match(/\bw-2\b/)
      expect(rendered).to match(/\bh-2\b/)
    end

    it "is rounded-full" do
      expect(rendered).to match(/rounded-full/)
    end

    it "is absolutely positioned so the surrounding focusable button keeps its accessible name path clean (D1 lesson)" do
      expect(rendered).to match(/\babsolute\b/)
    end

    it "has aria-hidden=\"true\" — the dot is decorative; meaning lives in the user-menu Notifications row" do
      expect(rendered).to match(/aria-hidden="true"/)
    end

    it "has the drop-shadow halo for visibility on arbitrary backgrounds" do
      expect(rendered).to match(/drop-shadow/)
    end

    it "falls back to a visible mark in forced-colors mode (Windows High Contrast)" do
      expect(rendered).to match(/forced-colors:/)
    end

    it "has motion-safe transition for fade-out when count drops to zero" do
      expect(rendered).to match(/motion-safe:transition-opacity/)
    end
  end

  describe "surface positioning" do
    it "anchors at the avatar's bottom-right (matches D1 precedent for the bell glyph position)" do
      render_indicator.call(summary: { count: 1, severity: :danger }, surface: :avatar)
      expect(rendered).to match(/-bottom-0\.5/)
      expect(rendered).to match(/-right-0\.5/)
    end

    it "anchors at the hamburger button's top-right (matches the hamburger icon's visual centroid)" do
      render_indicator.call(summary: { count: 1, severity: :danger }, surface: :hamburger)
      expect(rendered).to match(/\btop-0\.5/)
      expect(rendered).to match(/\bright-0\.5/)
      expect(rendered).not_to match(/-bottom-0\.5/)
    end
  end
end
