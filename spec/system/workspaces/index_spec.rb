require "rails_helper"

RSpec.describe "Strong workspaces index", type: :system, js: true do
  let(:user) { create(:user, first_name: "Dave", last_name: "Hancock") }
  let(:current_workspace) { create(:workspace, name: "Recent") }
  let(:older_workspace) { create(:workspace, name: "Older") }

  let!(:current_membership) {
    create(:membership, :owner, user: user, workspace: current_workspace,
                                last_accessed_at: 2.minutes.ago)
  }
  let!(:older_membership) {
    create(:membership, user: user, workspace: older_workspace,
                        last_accessed_at: 3.days.ago)
  }
  # Seed a co-owner for current_workspace so user can leave it in later examples.
  let!(:co_owner) {
    other = create(:user)
    create(:membership, :owner, user: other, workspace: current_workspace)
  }

  before { sign_in_via_form(user) }

  describe "page structure" do
    it "renders the page title and the New workspace CTA" do
      visit workspaces_path
      expect(page).to have_selector("h1", text: I18n.t("workspaces.index.title"))
      expect(page).to have_link(I18n.t("workspaces.index.new_workspace"))
    end

    it "pins the most-recently-accessed workspace at the top with a CURRENT badge" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_text("Recent")
        # Badge uses `uppercase` CSS class — match case-insensitively against the I18n value.
        expect(page).to have_text(/#{Regexp.escape(I18n.t('workspaces.index.current_badge'))}/i)
      end
    end

    it "renders an 'Other workspaces' heading and the older workspace below" do
      visit workspaces_path
      # Heading uses `uppercase` CSS class — match case-insensitively against the I18n value.
      expect(page).to have_text(/#{Regexp.escape(I18n.t('workspaces.index.other_workspaces_heading'))}/i)
      others_section = page.find("[data-test='other-workspaces-list']")
      within(others_section) do
        expect(page).to have_text("Older")
      end
    end
  end
end
