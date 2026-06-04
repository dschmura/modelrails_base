# frozen_string_literal: true

require "rails_helper"

# Proves the global `cn` change: ApplicationComponent#cn is backed by tailwind_merge,
# so a per-instance `class:` passthrough OVERRIDES the component's conflicting base
# utility instead of both being emitted (which would let CSS source-order decide).
#
# UI::ButtonComponent's primary base includes `rounded-md` (via FILLED); passing
# `class: "rounded-full"` must collapse to ONLY `rounded-full`. Against the old
# plain-join `cn` this would emit both `rounded-md rounded-full` and fail.
RSpec.describe "cn class override", type: :component do
  it "lets a passthrough class override the component's base utility" do
    render_inline(UI::ButtonComponent.new("X", variant: :primary, class: "rounded-full"))

    expect(page).to have_css("button.rounded-full")
    expect(page).not_to have_css("button.rounded-md")
  end
end
