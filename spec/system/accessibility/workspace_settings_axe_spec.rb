# frozen_string_literal: true

require "rails_helper"

# Task 10 of the workspace-nav-IA refactor: proves the four reshaped
# workspace-settings surfaces (Profile, Members, Limits & Plan, Invite) are
# axe-clean in both themes on their new shell placement (secondary sub-nav,
# breadcrumb, identity-bar link, tightened spacing).
#
# Per-spec axe runs AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook
# (see spec/support/playwright_accessibility.rb). Do not claim AAA from a
# local run — CI is the gate.
RSpec.describe "Workspace settings section — AAA", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme", max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in_via_form(user) }

  it "Profile settings page is axe-clean at AAA (both themes)" do
    visit edit_workspace_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on workspace profile: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "Members page is axe-clean at AAA (both themes)" do
    visit workspace_members_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on workspace members: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "Limits & Plan page is axe-clean at AAA (both themes)" do
    visit edit_workspace_settings_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on limits & plan: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "Invite screen is axe-clean at AAA (both themes)" do
    visit new_workspace_invitation_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on invite screen: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
