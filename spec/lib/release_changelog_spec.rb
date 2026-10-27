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

  describe ".name_release" do
    subject(:named) { described_class.name_release(changelog, "2026.10.27") }

    it "names the release and starts a fresh, empty [Unreleased] above it" do
      expect(named).to start_with("# Changelog\n\n## [Unreleased]\n\n## v2026.10.27\n\n")
    end

    it "folds repeated subsections into one each, in first-appearance order" do
      section = named[/## v2026\.10\.27\n(.*?)## v2\.0\.0/m, 1]

      expect(section.scan(/^### .+/)).to eq([ "### Added", "### Fixed" ])
      expect(section).to include("### Added\n\n- First feature.\n- Second feature.\n")
    end

    it "leaves earlier releases alone" do
      expect(named).to end_with("## v2.0.0 — Earlier\n\n- Old.\n")
    end

    it "files an entry above every subsection under Changed" do
      loose = "# Changelog\n\n## [Unreleased]\n\n- Loose entry.\n\n### Added\n\n- A.\n\n## v1\n"

      expect(described_class.name_release(loose, "N")).to include("### Changed\n\n- Loose entry.\n")
    end

    it "drops subsections that have no entries" do
      sparse = "# Changelog\n\n## [Unreleased]\n\n### Added\n\n### Fixed\n\n- A bug.\n\n## v1\n"

      expect(described_class.name_release(sparse, "N")).not_to include("### Added")
    end

    it "refuses an [Unreleased] with nothing in it, headings or not" do
      [ "# Changelog\n\n## [Unreleased]\n\n## v2.0.0\n",
        "# Changelog\n\n## [Unreleased]\n\n### Added\n\n### Fixed\n\n## v2.0.0\n" ].each do |empty|
        expect { described_class.name_release(empty, "2026.10.27") }.to raise_error(ReleaseChangelog::Error, /nothing/)
      end
    end
  end

  describe ".named_release and .section" do
    let(:named) { described_class.name_release(changelog, "2026.10.27-2") }

    it "returns the release named below [Unreleased], and its section" do
      expect(described_class.named_release(named)).to eq("2026.10.27-2")
      expect(described_class.section(named, "2026.10.27-2")).to start_with("### Added\n\n- First feature.")
    end

    it "returns nothing when only older releases follow [Unreleased]" do
      expect(described_class.named_release(changelog)).to be_nil
    end
  end

  describe ".names" do
    it "offers the day, then -2, -3 and onward" do
      expect(described_class.names(Date.new(2026, 10, 27)).first(3)).to eq(%w[2026.10.27 2026.10.27-2 2026.10.27-3])
    end

    it "offers only names its own pattern matches" do
      expect(described_class.names(Date.new(2026, 1, 2)).first(2)).to all(match(/\A#{described_class::NAME}\z/))
    end
  end

  it "keeps fold out of the interface bin/release uses" do
    expect(described_class).not_to respond_to(:fold)
  end
end
