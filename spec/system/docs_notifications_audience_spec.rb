require "rails_helper"

# End-to-end coverage of the audience-scoped notification docs:
#   - app/docs/user/notifications.md      → /docs/user/notifications
#   - app/docs/developer/notifications.md → /docs/developer/notifications
#
# Under path-based audience routing (markdowndocs ~> 0.9), each doc lives in
# its mode subdirectory and is served at a stable /docs/:mode/:slug URL. The
# mode switcher controls which variant appears on the /docs index, but both
# URLs are always directly accessible. These specs verify the docs render
# correctly at their scoped URLs.
RSpec.describe "Docs notifications audience filter", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  before do
    user.create_preferences!
    sign_in_via_form(user)
  end

  describe "user mode" do
    before { user.preferences.update!(docs_mode: "user") }

    it "renders user/notifications.md at its scoped URL" do
      visit "/docs/user/notifications"
      expect(page).to have_css("article", text: /Notifications/i)
      # Confirms the user-facing doc (not the technical reference) is shown
      expect(page).to have_no_css("article", text: /Notifications — Technical Reference/i)
    end
  end

  describe "developer mode" do
    before { user.preferences.update!(docs_mode: "developer") }

    it "renders developer/notifications.md at its scoped URL" do
      visit "/docs/developer/notifications"
      expect(page).to have_css("article", text: /Notifications — Technical Reference/i)
    end

    it "does not show the user-facing copy at the developer URL" do
      visit "/docs/developer/notifications"
      # The user doc intro uses "bell icon" phrasing; confirm it is absent
      expect(page).to have_no_css("article > p", text: /You'll find the bell icon/i)
    end
  end
end
