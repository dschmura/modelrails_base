require "rails_helper"

RSpec.describe "Workspace back-link navigation", type: :system do
  let(:user) { create(:user, first_name: "Owner", last_name: "User") }
  let(:workspace) { create(:workspace, name: "Acme Inc", max_members: 50) }
  let!(:owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_css("#user-menu-button")
  end

  let(:back_label) { I18n.t("navigation.back_to_workspace", workspace: workspace.name) }

  describe "on workspace shell pages" do
    # Members, Invitations, and Limits & Plan all moved off the settings
    # layout into the workspace shell (nav IA refactor Tasks 3-4).
    # shared/_workspace_back_link renders unconditionally for every shell
    # page except the workspace show itself — there's no settings-hub-style
    # sidebar/main "visual divorce" concern here (the old rationale for
    # hiding the back-link on the settings layout, per a Jason Fried-led
    # panel review), since the shell's own persistent primary sidebar +
    # identity bar already frame the page differently than the old hub did.
    it "shows the back-link on the members page" do
      visit workspace_members_path(workspace)
      expect(page).to have_link(back_label)
    end

    it "shows the back-link on the limits & plan page" do
      visit edit_workspace_settings_path(workspace)
      expect(page).to have_link(back_label)
    end
  end

  describe "on the workspace show page" do
    it "does not show the back-link (tautological — already there)" do
      visit workspace_path(workspace)
      expect(page).not_to have_link(back_label)
    end
  end
end
