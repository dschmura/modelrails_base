# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::RangeComponent, type: :component do
  it "renders a native range input with min/max/step" do
    render_inline(described_class.new(min: 0, max: 10, step: 2))

    expect(page).to have_css("input[type='range'][min='0'][max='10'][step='2']")
  end

  it "emits the value when supplied" do
    render_inline(described_class.new(value: 7))

    expect(page).to have_css("input[type='range'][value='7']")
  end

  it "omits the value when nil" do
    render_inline(described_class.new)

    expect(page).not_to have_css("input[type='range'][value]")
  end

  # AAA semantic token (the design-token guarantee), not raw Tailwind:
  it "renders with the AAA semantic token" do
    render_inline(described_class.new)

    expect(page).to have_css("input.accent-interactive")
  end

  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(invalid: true))

    expect(page).to have_css("input[type='range'][aria-invalid='true']")
  end

  it "omits aria-invalid when not invalid" do
    render_inline(described_class.new)

    expect(page).not_to have_css("input[type='range'][aria-invalid]")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(describedby: "volume-help"))

    expect(page).to have_css("input[type='range'][aria-describedby='volume-help']")
  end

  it "omits aria-describedby by default" do
    render_inline(described_class.new)

    expect(page).not_to have_css("input[type='range'][aria-describedby]")
  end

  it "uses the explicit id attribute" do
    render_inline(described_class.new(id: "my_range"))

    expect(page).to have_css("input#my_range")
  end

  it "falls back to the name for the id" do
    render_inline(described_class.new(name: "post[volume]"))

    expect(page).to have_css("input#post_volume_")
  end

  it "always emits an id with neither id nor name" do
    render_inline(described_class.new)

    expect(page).to have_css("input[type='range'][id]")
  end
end
