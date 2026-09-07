# frozen_string_literal: true

require "rails_helper"

# #831/#822: the settings/sessions page carries two lists — active devices and
# recent account activity — and they have to read as one page. Every assertion
# here is geometry or a computed value the user can see (a stacked line box, a
# 20px row inset, a shared text left edge), never a Tailwind class name: the
# classes are the implementation, and a fork restyles them first.
RSpec.describe "Settings sessions — card convergence", type: :system do
  let(:user) { create(:user, first_name: "Sam", last_name: "Session") }

  before do
    sign_in_via_form(user)
    expect(page).to have_css("#user-menu-button")
    user.sessions.create!(user_agent: "Mozilla/5.0 (Windows NT 10.0) Firefox/130.0", ip_address: "10.0.0.8")
    create(:activity_log, :security, actor: user, action: "user.password_changed")
  end

  it "stacks an activity row's label above its timestamp at phone width" do
    with_viewport(320, 800) do
      visit settings_sessions_path
      expect(page).to have_css("[data-testid='account-activity-item']")

      stacked = page.evaluate_script(<<~JS)
        (() => {
          const row   = document.querySelector("[data-testid='account-activity-item']");
          const label = row.querySelector("span");
          const time  = row.querySelector("time");
          return label.getBoundingClientRect().bottom <= time.getBoundingClientRect().top + 1;
        })()
      JS

      expect(stacked).to be(true),
        "At 320px the activity label should sit ABOVE its timestamp, not beside it."
    end
  end

  it "gives an activity row the canonical card rhythm and hierarchy at desktop" do
    visit settings_sessions_path
    expect(page).to have_css("[data-testid='account-activity-item']")

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const row      = document.querySelector("[data-testid='account-activity-item']");
        const label    = row.querySelector("span");
        const heading  = document.querySelector("[data-testid='account-activity-item']")
                                 .closest("section").querySelector("h2");
        const device   = document.querySelector("[data-testid='device-list'] li p");
        const style    = getComputedStyle(row);
        const lstyle   = getComputedStyle(label);
        const dstyle   = getComputedStyle(device);
        return {
          paddingTop:    style.paddingTop,
          paddingBottom: style.paddingBottom,
          headingDelta:  Math.abs(label.getBoundingClientRect().left -
                                  heading.getBoundingClientRect().left),
          labelWeight:   lstyle.fontWeight,
          deviceWeight:  dstyle.fontWeight,
          labelColor:    lstyle.color,
          deviceColor:   dstyle.color
        };
      })()
    JS

    # 1 + 2: one rhythm for the whole card — the canonical preferences row and
    # this card's own header are both py-5, so a populated row cannot be py-4
    # while the empty state next to it is py-5.
    expect(metrics["paddingTop"]).to eq("20px")
    expect(metrics["paddingBottom"]).to eq("20px")
    # The label shares the card heading's text left edge (subpixel tolerance —
    # exact float equality on a rect is a flake waiting to happen).
    expect(metrics["headingDelta"]).to be <= 1
    # 4: the card's content is not lighter than the device list's content.
    expect(metrics["labelWeight"]).to eq(metrics["deviceWeight"])
    expect(metrics["labelColor"]).to eq(metrics["deviceColor"])
  end
end
