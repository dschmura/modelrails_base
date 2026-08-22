# frozen_string_literal: true

require "rails_helper"

# W1-1 (2026-08-22 view-layer audit (internal)): at tablet/phone widths the
# members table's trailing columns — including every row's action links —
# were clipped unreachable by an overflow-hidden wrapper. The wrapper must
# scroll horizontally instead.
RSpec.describe "Members table at narrow viewports", type: :system do
  let(:user) { create(:user, first_name: "Owner", last_name: "User", password: "SecureP@ssw0rd123!") }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let!(:alice) { create(:user, first_name: "Alice", last_name: "Anderson") }
  let!(:alice_membership) { create(:membership, :admin, user: alice, workspace: workspace) }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.create_for_email(user.email_address)
    visit magic_link_callback_path(token: token)
    click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")
    expect(page).to have_css("#user-menu-button")
  end

  it "keeps row actions reachable at 768px via horizontal scroll" do
    with_viewport(768) do
      visit workspace_members_path(workspace)

      wrapper = find(:xpath, "//table[@aria-label]/..")
      overflow_x = page.evaluate_script(
        "getComputedStyle(arguments[0]).overflowX", wrapper
      )
      expect(overflow_x).to eq("auto")

      # The overflow-x assertion above is the regression discriminator:
      # programmatic scrollIntoView scrolls even overflow-hidden containers,
      # and Cuprite's visible? ignores ancestor clipping. This block
      # sanity-checks that a real last-column row action exists and scrolls
      # into view — tbody-scoped so it can't match a thead sort link.
      action = first("tbody td:last-child a, tbody td:last-child button", minimum: 1, visible: :all)
      page.execute_script("arguments[0].scrollIntoView({inline: 'end'})", action)
      expect(action).to be_visible
    end
  end
end
