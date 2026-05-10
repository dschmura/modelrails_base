require "rails_helper"

# Reusable preferences card partial. Used by the notifications preferences
# page (and future user-preferences sections). Renders a rounded-2xl
# surface-raised card with a heading + optional description + block content.
# Strict locals: `title:` required, `description: nil` optional.
RSpec.describe "shared/_preferences_card", type: :view do
  def render_card(content: "row content", **locals)
    render(layout: "shared/preferences_card", locals: locals) { content }
  end

  it "renders the title in a heading element" do
    render_card(title: "Notification Types")
    expect(rendered).to have_css("h2", text: "Notification Types")
  end

  it "renders the yielded block content" do
    render_card(title: "Test", content: "<div class='my-row'>row body</div>".html_safe)
    expect(rendered).to have_css(".my-row", text: "row body")
  end

  it "renders the optional description when provided" do
    render_card(title: "Test", description: "Manage how you get notified.")
    expect(rendered).to have_text("Manage how you get notified.")
  end

  it "omits the description element entirely when description is nil" do
    render_card(title: "Test")
    expect(rendered).not_to have_css("[data-preferences-card-description]")
  end

  it "uses the rounded-2xl card surface classes from the sample design" do
    render_card(title: "Test")
    expect(rendered).to have_css(
      "section.rounded-2xl.bg-surface-raised.border.border-border.shadow-sm"
    )
  end

  it "uses semantic aria-labelledby for screen readers" do
    render_card(title: "Test Heading")
    expect(rendered).to have_css("section[aria-labelledby]")
    labelledby_id = Capybara.string(rendered).find("section")["aria-labelledby"]
    expect(rendered).to have_css("h2##{labelledby_id}", text: "Test Heading")
  end
end
