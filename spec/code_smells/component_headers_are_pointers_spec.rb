# frozen_string_literal: true

require "rails_helper"

# Every vendored UI::* component's class-level comment is the three-line pointer
# to docs/components/<name>.md in the modelrails_ui gem; the prose lives there
# (modelrails_ui 0.16.0). The detector is inlined because the gem is
# development-only and is not loaded in the test group.
RSpec.describe "Component headers are pointers" do
  # A `let`, not a bare constant — a describe-level constant lands on Object
  # and can collide across parallel workers (#607); `header_block`/`pointer?`
  # are helper defs, so `let` is the sanctioned form.
  let(:doc_parent) do
    { "accordion_item" => "accordion", "list_group_item" => "list_group",
      "menubar_menu" => "menubar", "tabs_item" => "tabs",
      "card_content" => "card", "card_description" => "card", "card_footer" => "card",
      "card_header" => "card", "card_title" => "card" }.freeze
  end

  # Contiguous `#` runs within lines[from...to], as Ranges.
  def comment_blocks(lines, from, to)
    ranges = []
    start = nil
    (from...to).each do |idx|
      if lines[idx].match?(/\A\s*#/)
        start ||= idx
      elsif start
        ranges << (start...idx)
        start = nil
      end
    end
    ranges << (start...to) if start
    ranges
  end

  def header_block(lines)
    i = lines.index { |l| l.match?(/\A\s*class\s+\S/) } or return []

    # A header can be severed from the class line by constants or a blank line
    # in between (e.g. card_title's header, then LEVELS/DEFAULT_LEVEL, then the
    # class), and an in-class doc comment right below `class` (e.g. range's
    # constant rationale) can otherwise out-length the real header above. An
    # already-migrated pointer block anywhere in the module-to-class region
    # wins outright, mirroring the gem's `locate`.
    mod_idx = lines[0...i].rindex { |l| l.match?(/\A\s*module\s+\S/) }
    region_start = mod_idx ? mod_idx + 1 : 0
    marked = comment_blocks(lines, region_start, i).find { |r| lines[r].any? { |l| l.include?("docs/components/") } }
    return lines[marked] if marked

    up_start = i
    up_start -= 1 while up_start.positive? && lines[up_start - 1].match?(/\A\s*#/)
    up = lines[up_start...i]
    up = [] if up.any? { |l| l.include?("frozen_string_literal") }
    down_end = i + 1
    down_end += 1 while down_end < lines.size && lines[down_end].match?(/\A\s*#/)
    down = lines[(i + 1)...down_end]
    up.size >= down.size ? up : down
  end

  def pointer?(name, lines)
    block = header_block(lines)
    block.size.between?(1, 3) && block.any? { |l| l.include?("docs/components/#{doc_parent.fetch(name, name)}.md") }
  end

  it "keeps every vendored UI component's class comment to the three-line doc pointer" do
    offenders = Dir.glob(Rails.root.join("app/components/ui/*_component.rb")).reject do |file|
      pointer?(File.basename(file, "_component.rb"), File.readlines(file))
    end

    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to be_empty,
      "Grew back into prose — the reference lives in the gem's docs/components/<name>.md:\n  #{offenders.join("\n  ")}"
  end

  it "fails on a header that is prose (positive control)" do
    prose = [ "module UI\n", "  # # Kbd\n", "  #\n", "  # Long paragraph.\n", "  # ## Use when\n", "  # - always\n", "  class KbdComponent\n", "  end\n", "end\n" ]
    expect(pointer?("kbd", prose)).to be(false)
    pointer = [ "module UI\n", "  # Renders a key.\n", "  # See docs/components/kbd.md in the modelrails_ui gem.\n", "  class KbdComponent\n", "  end\n", "end\n" ]
    expect(pointer?("kbd", pointer)).to be(true)
  end

  it "keeps no markdown-heading comment in any vendored component" do
    # A nested `#` inside a commented code sample is not a heading — every real
    # header title/section line has exactly one space after the comment marker
    # (`# # Title`, `# ## Use when`), so the space is literal here.
    offenders = Dir.glob(Rails.root.join("app/components/ui/*_component.rb")).select do |file|
      File.readlines(file).any? { |l| l.match?(/\A\s*# ##?\s+\S/) }
    end

    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to be_empty,
      "A markdown heading comment survived migration: #{offenders.join("\n  ")}"
  end
end
