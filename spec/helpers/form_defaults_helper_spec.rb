require "rails_helper"

RSpec.describe FormDefaultsHelper do
  def form_tag_of(html)
    Nokogiri::HTML.fragment(html).at_css("form")
  end

  it "renders novalidate on a form_with that says nothing about it" do
    form = form_tag_of(helper.form_with(url: "/somewhere") { "" })

    expect(form["novalidate"]).to be_present
  end

  # The caller's html options merge last, so an explicit opt-out wins -- and
  # the caller's other html options survive the merge.
  it "lets a form opt back into native validation, keeping its other html options" do
    form = form_tag_of(helper.form_with(url: "/somewhere", html: { novalidate: false, data: { role: "probe" } }) { "" })

    expect(form["novalidate"]).to be_nil
    expect(form["data-role"]).to eq("probe")
  end
end
