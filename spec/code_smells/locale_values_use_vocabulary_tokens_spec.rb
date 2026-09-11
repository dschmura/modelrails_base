require "rails_helper"

# A fork renames the product's nouns in config/vocabulary.local.yml. That only
# holds if upstream strings say %{workspace}, never "workspace": every literal
# that lands upstream is a string the fork silently ships in the wrong word
# (the real fork did — its onboarding wizard still said "workspace" after it
# renamed to Event). Fork-owned locale files are exempt: a fork rewrites them.
RSpec.describe "Code smell: upstream-owned locale values use the vocabulary tokens" do
  fork_owned = %w[brand.en.yml pages.en.yml]
  # The literal is the word, not the noun. Keep this list a decision, not a fossil.
  allowed = {
    # "member" as a ROLE NAME is out of the vocabulary's scope, and this file has none for workspace/project yet.
  }

  def offenders_in(path, nouns, allowed)
    File.readlines(path).each_with_index.filter_map do |line, index|
      # Skip comment lines
      next if line.match?(/\A\s*#/)
      # Skip blank lines
      next if line.match?(/\A\s*\z/)
      # Skip key-only lines (the noun here is a key, not copy)
      next if line.match?(/\A\s*[\w.-]+:\s*(\||>[-+]?)?\s*\z/)

      # Extract value from key: value lines
      if line.match?(/\A\s*[\w.-]+:\s+(.+)\z/)
        scannable = Regexp.last_match(1)
      else
        # Block-scalar continuation or array entry - scan the whole line
        scannable = line
      end

      scannable = scannable.gsub(/%\{[^}]*\}/, "")
      hit = nouns.find { |noun| scannable.match?(/\b#{noun}s?\b/i) }
      next unless hit
      location = "#{path.basename}:#{index + 1}"
      next if allowed[location]
      "#{location}  (#{hit}) #{line.strip[0, 80]}"
    end
  end

  it "says %{workspace} / %{project} and never the bare word" do
    nouns = Vocabulary::NOUNS.map(&:to_s)
    offenders = Dir.glob(Rails.root.join("config/locales/en/*.yml"))
      .map { |f| Pathname.new(f) }
      .reject { |p| fork_owned.include?(p.basename.to_s) }
      .flat_map { |p| offenders_in(p, nouns, allowed) }

    expect(offenders).to be_empty,
      "Bare noun(s) in upstream-owned locale values — use the vocabulary token so a fork's rename holds:\n  #{offenders.join("\n  ")}"
  end

  # The check must be able to fail.
  it "reports a planted literal and block-scalar lines" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe.en.yml")
      path.write(%(en:\n  probe: "Create a workspace"\n  fine: "Create %{Workspace}"\n  workspaces:\n    body: |\n      Ask your workspace administrator.\n    ok: "Nothing here"\n))

      expect(offenders_in(path, %w[workspace project], {})).to contain_exactly(
        a_string_starting_with("probe.en.yml:2"),
        a_string_starting_with("probe.en.yml:6")
      )
    end
  end
end
