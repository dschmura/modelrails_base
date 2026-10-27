require "rails_helper"
require Rails.root.join("lib/release_changelog")

RSpec.describe ReleaseChangelog do
  let(:changelog) do
    <<~MD
      # Changelog

      ## [Unreleased]

      ### Added

      - First feature.

      ### Fixed

      - A bug.

      ### Added

      - Second feature.

      ## v2.0.0 — Earlier

      - Old.
    MD
  end

  describe ".cut" do
    subject(:cut) { described_class.cut(changelog, "2026.10.27") }

    it "names the release and starts a fresh, empty [Unreleased] above it" do
      expect(cut).to start_with("# Changelog\n\n## [Unreleased]\n\n## v2026.10.27\n\n")
    end

    it "folds repeated subsections into one each, in first-appearance order" do
      section = cut[/## v2026\.10\.27\n(.*?)## v2\.0\.0/m, 1]

      expect(section.scan(/^### .+/)).to eq([ "### Added", "### Fixed" ])
      expect(section).to include("### Added\n\n- First feature.\n- Second feature.\n")
    end

    it "leaves earlier releases alone" do
      expect(cut).to end_with("## v2.0.0 — Earlier\n\n- Old.\n")
    end

    it "refuses an [Unreleased] with nothing in it" do
      empty = "# Changelog\n\n## [Unreleased]\n\n## v2.0.0\n\n- Old.\n"

      expect { described_class.cut(empty, "2026.10.27") }.to raise_error(ReleaseChangelog::Error, /nothing/)
    end
  end

  describe ".prepared_name and .section" do
    let(:prepared) { described_class.cut(changelog, "2026.10.27-2") }

    it "names the release cut below [Unreleased], and returns its section" do
      expect(described_class.prepared_name(prepared)).to eq("2026.10.27-2")
      expect(described_class.section(prepared, "2026.10.27-2")).to start_with("### Added\n\n- First feature.")
    end

    it "names nothing when only older releases follow [Unreleased]" do
      expect(described_class.prepared_name(changelog)).to be_nil
    end
  end
end
