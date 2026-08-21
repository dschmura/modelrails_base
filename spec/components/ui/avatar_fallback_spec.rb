# frozen_string_literal: true

require "rails_helper"

# A 404 on the image src leaves a broken-image glyph — the one case `fallback:` did not
# cover, because it only stood in for a NIL src. Recovering needs an `error` handler, and
# CSP forbids inline `onerror`, so a controller swaps in the initials.
#
# The wrapper is only rendered when BOTH a src and a fallback are given: with a src alone
# there is nothing to fall back to, so those call sites keep their bare <img>.
RSpec.describe "UI::AvatarComponent image error fallback", type: :component do
  def avatar(**opts) = render_inline(UI::AvatarComponent.new(**opts))

  it "renders a bare img when there is no fallback to swap in" do
    avatar(src: "/a.png", aria_label: "Dave")

    expect(page).to have_css("img[src='/a.png']")
    expect(page).to have_no_css("[data-controller~=avatar]")
  end

  it "renders initials directly when there is no src" do
    avatar(fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("span", text: "DC")
    expect(page).to have_no_css("img")
  end

  it "wires the error handler when both a src and a fallback exist" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("[data-controller~=avatar] img[data-action~='error->avatar#showFallback']")
  end

  it "ships the initials alongside, hidden until the image fails" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    fallback = page.find("[data-avatar-target=fallback]", visible: :all)
    expect(fallback.text(:all)).to eq("DC")
    expect(fallback[:hidden]).to be_truthy
  end

  # The accessible name must not be announced twice by the img and the standby initials.
  it "names the avatar once" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("[aria-label='Dave']", count: 1, visible: :all)
  end
end
