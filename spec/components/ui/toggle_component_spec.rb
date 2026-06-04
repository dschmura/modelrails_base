# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::ToggleComponent, type: :component do
  it "renders an unpressed toggle button by default" do
    render_inline(described_class.new("Bold"))

    expect(page).to have_css("button[type='button'][aria-pressed='false'][data-state='off']", text: "Bold")
  end

  it "renders the pressed state" do
    render_inline(described_class.new("Bold", pressed: true))

    expect(page).to have_css("button[type='button'][aria-pressed='true'][data-state='on']", text: "Bold")
  end

  it "keeps the toggle Stimulus wiring" do
    render_inline(described_class.new("Bold"))

    expect(page).to have_css("button[data-controller='toggle'][data-action='click->toggle#toggle']")
  end

  # AAA 2.5.5 target-size: every size must render a >=44px tall control.
  # h-11 = 44px (default/sm), h-12 = 48px (lg). Sub-44px heights are an AAA fail.
  it "renders the default size at the 44px floor" do
    render_inline(described_class.new("Bold"))

    expect(page).to have_css("button.h-11")
  end

  it "renders the sm size at the 44px floor" do
    render_inline(described_class.new("Bold", size: :sm))

    expect(page).to have_css("button.h-11")
  end

  it "renders the lg size at the 48px floor" do
    render_inline(described_class.new("Bold", size: :lg))

    expect(page).to have_css("button.h-12")
  end

  # Fail-loud size guard: an unknown size raises in development/test.
  it "raises on an unknown size" do
    expect {
      render_inline(described_class.new("Bold", size: :bogus))
    }.to raise_error(ArgumentError)
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind. Selected
  # (on) uses the tinted interactive-subtle surface — DISTINCT from the neutral
  # off-hover surface — so clicking to select gives immediate visible feedback.
  it "renders the selected state as a distinct tinted surface" do
    render_inline(described_class.new("Bold", pressed: true))

    expect(page).to have_css('button.data-\\[state\\=on\\]\\:bg-interactive-subtle')
    expect(page).to have_css('button.data-\\[state\\=on\\]\\:text-interactive')
  end

  # Hover is scoped to the OFF state so a selected toggle keeps its tinted look on
  # hover. Regression guard: the prior unscoped hover:bg-surface-sunken made the
  # hover surface identical to the selected surface.
  it "scopes the neutral hover to the off state" do
    render_inline(described_class.new("Bold"))

    expect(page).to have_css('button.data-\\[state\\=off\\]\\:hover\\:bg-surface-sunken')
    expect(page).not_to have_css('button.hover\\:bg-surface-sunken')
  end
end
