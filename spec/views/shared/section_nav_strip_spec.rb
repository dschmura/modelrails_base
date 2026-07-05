require "rails_helper"

RSpec.describe "shared/_section_nav_strip", type: :view do
  let(:items) do
    [
      { label: "Profile", href: "/a", icon: :user_circle, active: false },
      { label: "Members", href: "/b", icon: :user_group, active: true }
    ]
  end

  it "renders a labeled nav with an sr-only heading and aria-current on the active item" do
    render partial: "shared/section_nav_strip", locals: { items: items, heading: "Workspace settings" }
    expect(rendered).to have_css("nav[aria-labelledby] h2.sr-only", text: "Workspace settings")
    expect(rendered).to have_css("nav a[aria-current='page']", text: "Members")
    expect(rendered).to have_no_css("[role='tab']")  # links, not tabs
  end

  it "renders nothing when there are no items" do
    render partial: "shared/section_nav_strip", locals: { items: [], heading: "Workspace settings" }
    expect(rendered.strip).to be_empty
  end
end
