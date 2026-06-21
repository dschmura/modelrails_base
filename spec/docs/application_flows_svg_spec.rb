require "rails_helper"
require "nokogiri"

# The wireframes carry meaning, so each flow <svg> must be well-formed, named
# for assistive tech, and free of anything the markdowndocs sanitizer would
# strip. Visual correctness is checked in the browser; this guards the contract.
RSpec.describe "app/docs/application-flows.md wireframes" do
  let(:source) { File.read(Rails.root.join("app/docs/application-flows.md")) }
  # Each top-level <svg>…</svg> block (flows are not nested).
  let(:svg_blocks) { source.scan(/<svg\b.*?<\/svg>/m) }

  it "has at least the five flow diagrams" do
    expect(svg_blocks.size).to be >= 5
  end

  it "every flow svg is well-formed XML" do
    svg_blocks.each do |svg|
      doc = Nokogiri::XML(svg) { |c| c.strict }
      expect(doc.errors).to be_empty, "malformed SVG: #{doc.errors.first}"
    end
  end

  it "every flow svg is role=img with a non-empty aria-label" do
    svg_blocks.each do |svg|
      root = Nokogiri::XML(svg).root
      expect(root["role"]).to eq("img")
      expect(root["aria-label"].to_s.strip).not_to be_empty
    end
  end

  it "contains no scripts, event handlers, or external refs (sanitizer-safe)" do
    svg_blocks.each do |svg|
      expect(svg).not_to match(/<script/i)
      expect(svg).not_to match(/\son\w+=/i)            # onclick, onload, …
      expect(svg).not_to match(/href\s*=\s*["'](?!#)/i) # only internal #frag refs allowed
    end
  end

  # Source validity is necessary but NOT sufficient: a blank line inside an
  # inline <svg> ends its CommonMark HTML block, and a following chunk whose
  # first line isn't a lone tag becomes a <p> — which closes the <svg> in
  # HTML5 foreign content and orphans every later element (invisible). Only the
  # RENDERED DOM proves the screens actually nest inside their <svg>.
  describe "as rendered through markdowndocs (not just the source)" do
    let(:rendered) do
      body = source.sub(/\A---\n.*?\n---\n/m, "") # drop YAML front matter
      Markdowndocs::MarkdownRenderer.render(body)
    end
    let(:doc) { Nokogiri::HTML5.fragment(rendered) }

    it "nests each flow's drawing elements inside its <svg> (no foreign-content breakout)" do
      svgs = doc.css("svg")
      expect(svgs.size).to be >= 5
      svgs.each do |svg|
        expect(svg.css("rect, circle, text, line").size).to be > 1,
          "svg #{svg['viewBox'].inspect} rendered with no nested screens — CommonMark/HTML5 breakout"
      end
    end

    it "leaves no drawing element orphaned outside an <svg>" do
      orphans = doc.css("rect, circle, line").reject { |n| n.ancestors("svg").any? }
      expect(orphans.size).to eq(0),
        "#{orphans.size} drawing elements rendered outside any <svg> (breakout bug)"
    end
  end
end
