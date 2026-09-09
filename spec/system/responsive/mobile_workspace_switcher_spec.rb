# frozen_string_literal: true

require "rails_helper"

# System spec: the workspace switcher on a phone.
#
# The desktop switcher heads the sidebar, which is display:none below md. The
# same switcher renders a second time above the section tabs — with its own
# id suffix, because the sidebar copy is hidden, not absent, and unsuffixed it
# would duplicate every id (#1077). It replaced the inline list that used to
# live in the hamburger; the hamburger is global chrome only now.
#
# Escape is dispatched to the menu controller directly, as the desktop spec
# does — programmatic KeyboardEvent dispatch does not reach main-world
# Stimulus listeners from the driver's context.
RSpec.describe "Mobile workspace switcher — content column", type: :system, js: true do
  let(:user) { create(:user) }
  let!(:second_workspace) do
    ws = create(:workspace, max_members: 50)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  def send_mobile_switcher_key(key)
    cdp_execute(<<~JS)
      (function() {
        var el = document.querySelector('#workspace-switcher-button-mobile').closest('[data-controller~="menu"]');
        var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'menu');
        if (c) c.navigate(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
      })()
    JS
  end

  before do
    sign_in_via_form(user)
    cdp_resize(375, 667)
    user.reload
    # Start on the personal workspace so selecting `second_workspace` is a
    # real navigation rather than a click that lands where we already are.
    visit workspace_path(user.personal_workspace)
  end

  it "is reachable without opening the hamburger, and lists both workspaces" do
    expect(page).to have_css("[data-mobile-menu-target=button][aria-expanded=false]")

    button = find("#workspace-switcher-button-mobile")
    expect(button["aria-expanded"]).to eq("false")
    button.click
    expect(button["aria-expanded"]).to eq("true")

    within("#workspace-switcher-menu-mobile") do
      expect(page).to have_link(user.personal_workspace.name, href: workspace_path(user.personal_workspace))
      expect(page).to have_link(second_workspace.name, href: workspace_path(second_workspace))
      expect(page).to have_link(I18n.t("navigation.all_workspaces"), href: workspaces_path)
    end
  end

  it "navigates to the selected workspace" do
    find("#workspace-switcher-button-mobile").click

    within("#workspace-switcher-menu-mobile") do
      click_link second_workspace.name
    end

    expect(page).to have_current_path(workspace_path(second_workspace))
  end

  it "closes on Escape" do
    find("#workspace-switcher-button-mobile").click
    expect(find("#workspace-switcher-button-mobile")["aria-expanded"]).to eq("true")

    send_mobile_switcher_key("Escape")

    expect(find("#workspace-switcher-button-mobile")["aria-expanded"]).to eq("false")
    expect(page).to have_no_css("#workspace-switcher-menu-mobile", visible: :visible)
  end
end
