require "rails_helper"

# Reusable preferences row partial. Renders one row inside a preferences
# card: a colored icon tile on the left (10x10 rounded-xl), title +
# description in the middle, and a control (toggle / select / time input)
# on the right. Strict locals: `icon_name:`, `icon_color:`, `title:`,
# `description:`, `control:`. The `control:` is the rendered HTML for the
# right-side control element.
RSpec.describe "shared/_preferences_row", type: :view do
  def render_row(control: %(<input type="checkbox">).html_safe, **locals)
    render(
      partial: "shared/preferences_row",
      locals: locals.merge(control: control)
    )
  end

  it "renders the title in a heading-equivalent element" do
    render_row(
      icon_name: :bell,
      icon_color: :info,
      title: "Mentions",
      description: "When someone tags you."
    )
    expect(rendered).to have_text("Mentions")
  end

  it "renders the description text" do
    render_row(
      icon_name: :bell,
      icon_color: :info,
      title: "Mentions",
      description: "When someone tags you."
    )
    expect(rendered).to have_text("When someone tags you.")
  end

  it "renders the passed control HTML in the row" do
    render_row(
      icon_name: :bell,
      icon_color: :info,
      title: "Test",
      description: "Test",
      control: %(<input type="checkbox" data-test-control>).html_safe
    )
    expect(rendered).to have_css("input[data-test-control]")
  end

  describe "icon_color mapping" do
    %i[info success warning danger].each do |color|
      it "applies the bg-#{color}-surface + text-#{color}-icon tile classes when icon_color: :#{color}" do
        render_row(
          icon_name: :bell,
          icon_color: color,
          title: "Test",
          description: "Test"
        )
        expect(rendered).to have_css(
          "[data-preferences-row-icon].bg-#{color}-surface.text-#{color}-icon"
        )
      end
    end

    it "falls back to surface-sunken + text-heading when icon_color is unrecognized" do
      render_row(
        icon_name: :bell,
        icon_color: :slate,
        title: "Test",
        description: "Test"
      )
      expect(rendered).to have_css(
        "[data-preferences-row-icon].bg-surface-sunken.text-text-heading"
      )
    end
  end

  it "renders the icon tile with the rounded-xl shape from the sample" do
    render_row(
      icon_name: :bell,
      icon_color: :info,
      title: "Test",
      description: "Test"
    )
    expect(rendered).to have_css("[data-preferences-row-icon].w-10.h-10.rounded-xl")
  end

  it "renders an SVG icon inside the tile" do
    render_row(
      icon_name: :bell,
      icon_color: :info,
      title: "Test",
      description: "Test"
    )
    expect(rendered).to have_css("[data-preferences-row-icon] svg")
  end
end
