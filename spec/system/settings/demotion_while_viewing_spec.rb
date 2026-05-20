require "rails_helper"

RSpec.describe "Settings hub — demotion while viewing", type: :system do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:sidebar_selector) { "aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']" }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    @member_ms = create(:membership, :admin, user: member, workspace: workspace)
    @viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
  end

  # The settings layout subscribes to the workspace stream (turbo_stream_from
  # Current.workspace) and Membership broadcasts via Broadcastable on update.
  # When an admin in another tab demotes this user, the broadcast fires a
  # refresh that Turbo morphs into the open tab — re-evaluating
  # render_nav_item_if_permitted against the new role. The Limits & Plan link is the
  # cleanest assertion target: it gates on Workspaces::SettingsPolicy#update?
  # (manage_settings), which Admin has and Viewer does not. Members link
  # gates on membership.present?, which doesn't flip across the demotion.
  it "re-renders the sidebar via Turbo morph when the user's role is changed in another tab" do
    sign_in_via_form(member)
    visit workspace_members_path(workspace)

    within(sidebar_selector) do
      expect(page).to have_link(I18n.t("settings.sidebar.items.limits_and_plan"))
    end

    # Simulate the "other tab" admin demoting this user. The after_update_commit
    # broadcast on Membership fires broadcast_refresh_to workspace, which the
    # current tab's turbo_stream_from picks up and morphs in.
    @member_ms.update!(role: @viewer_role)

    within(sidebar_selector) do
      expect(page).not_to have_link(I18n.t("settings.sidebar.items.limits_and_plan"), wait: 5)
    end
  end
end
