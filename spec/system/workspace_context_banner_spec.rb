# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspace context banner accessibility", type: :system do
  # The banner renders ONLY when the signed-in user belongs to 2+ workspaces.
  # :personal factory gives the user one workspace; we create a second org workspace
  # and add an :owner membership to reach the switcher_workspaces.size > 1 threshold.
  let(:user) { create(:user) }
  let!(:org)  do
    ws = create(:workspace)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  before { sign_in_via_form(user) }

  it "renders the banner and passes AAA in light and dark themes" do
    visit workspace_path(org)

    # Guard: if this fails, the 2-workspace setup is broken — the banner won't render.
    expect(page).to have_css("#workspace-context-banner")

    scope = [ "#workspace-context-banner" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
