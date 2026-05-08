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

    describe "filter chips" do
      it "marks the All chip as current by default" do
        deliver_security_notification

        visit account_notifications_path

        within "[aria-label='#{I18n.t('notifications.index.filters_aria')}']" do
          expect(page).to have_link(
            I18n.t("notifications.index.filters.all"),
            href: account_notifications_path
          )
          all_chip = find_link(I18n.t("notifications.index.filters.all"))
          expect(all_chip["aria-current"]).to eq("page")
        end
      end

      it "filters to only unread when Unread chip is followed" do
        read_notification = deliver_security_notification
        read_notification.update!(read_at: Time.current)
        unread_notification = deliver_security_notification

        visit account_notifications_path
        click_link I18n.t("notifications.index.filters.unread")

        expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(unread_notification)}")
        expect(page).not_to have_css("##{ActionView::RecordIdentifier.dom_id(read_notification)}")
      end
    end
  end
end
