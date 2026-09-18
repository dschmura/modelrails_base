# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TableComponent, type: :component do
  def render_table(**opts, &block)
    render_inline(described_class.new(caption: "All widgets", **opts)) do |t|
      t.with_header { "<th scope=\"col\">Name</th>".html_safe }
      t.with_body { "<tr><td>Widget</td></tr>".html_safe }
      block&.call(t)
    end
  end

  it "renders a table with a visually hidden caption by default" do
    render_table
    expect(page).to have_css("table caption.sr-only", text: "All widgets")
    expect(page).to have_css("thead tr th[scope=col]", text: "Name")
    expect(page).to have_css("tbody tr td", text: "Widget")
  end

  it "shows the caption when asked" do
    render_table(caption_visible: true)
    expect(page).to have_css("table caption:not(.sr-only)", text: "All widgets")
  end

  it "requires a caption — the table's accessible name is not optional" do
    expect { render_inline(described_class.new(caption: "")) }.to raise_error(ArgumentError, /caption/)
  end

  it "exposes the size on the wrapper and rejects unknown sizes" do
    render_table(size: :compact)
    expect(page).to have_css("div[data-size=compact] table")
    expect { described_class.new(caption: "x", size: :huge) }.to raise_error(ArgumentError, /size/)
  end

  it "renders the footer slot after the table, inside the bordered wrapper" do
    render_table { |t| t.with_footer { "Showing 1–1 of 1" } }
    expect(page).to have_css("div.rounded-lg > table + div[data-slot=footer]", text: "Showing 1–1 of 1")
  end

  it "keeps the header cell classes on the shared constant so sortable headers match plain ones" do
    expect(UI::TableComponent::TH).to include("h-11")
    expect(UI::TableComponent::TH).to include("text-left")
  end

  it "merges a caller-supplied data: hash instead of letting it clobber data-size" do
    render_table(data: { controller: "x" })
    expect(page).to have_css("div[data-size=default][data-controller=x]")
  end
end
