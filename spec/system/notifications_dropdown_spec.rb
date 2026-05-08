require "rails_helper"

RSpec.describe "Notifications bell + dropdown", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  before { sign_in_via_form(user) }

  describe "bell trigger in user menu" do
    it "renders an accessible bell button next to the avatar" do
      visit root_path

      expect(page).to have_css(
        "button[aria-label='#{I18n.t('notifications.bell.label')}']",
        visible: :visible
      )
    end
  end
end
