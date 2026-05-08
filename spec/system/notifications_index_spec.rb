require "rails_helper"

RSpec.describe "Notifications index page", type: :system do
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

  def deliver_security_notification(recipient = user)
    travel_to(Time.current + rand(1..1000).minutes) do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
    end
    recipient.notifications.reload.last
  end

  before { sign_in_via_form(user) }

  describe "GET /account/notifications" do
    it "renders the heading and a list row containing each notification's message" do
      notification = deliver_security_notification
      expected_message = I18n.t(
        "notifications.password_changed.message",
        user_name: user.first_name
      )

      visit account_notifications_path

      expect(page).to have_css("h1", text: I18n.t("notifications.index.heading"))
      within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
        expect(page).to have_text(expected_message)
      end
    end
  end
end
