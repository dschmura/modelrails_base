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
end
