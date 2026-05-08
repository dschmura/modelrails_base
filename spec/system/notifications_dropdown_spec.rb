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

  # Deterministic delivery — sequential offsets keep every notification in
  # its own idempotency bucket without relying on `rand`. See
  # `project_flaky_tests_followup.md` for the rand-bucket-collision pattern
  # this avoids.
  def deliver_n_security_notifications(count, recipient: user)
    count.times do |i|
      travel_to(Time.current + ((i + 1) * 5).minutes) do
        PasswordChangedNotifier.with(record: recipient).deliver(recipient)
      end
    end
  end

  before do
    sign_in_via_form(user)
    # Sign-in dispatches a SignInFromNewDeviceNotifier; clear it so each
    # example starts from a known zero-unread baseline.
    user.notifications.update_all(read_at: Time.current)
  end

  describe "bell trigger in user menu" do
    it "renders an accessible bell button next to the avatar" do
      visit root_path

      expect(page).to have_css(
        "button[aria-label^='#{I18n.t('notifications.bell.label')}']",
        visible: :visible
      )
    end

    it "omits the unread badge when no notifications are unread" do
      visit root_path

      expect(page).not_to have_css("[data-notifications-bell-badge]", visible: :visible)
    end

    it "shows a numeric badge with the unread count" do
      deliver_n_security_notifications(3)

      visit root_path

      expect(page).to have_css(
        "[data-notifications-bell-badge]",
        text: "3",
        visible: :visible
      )
    end

    it "caps the badge text at 10+ when more than nine notifications are unread" do
      deliver_n_security_notifications(12)

      visit root_path

      expect(page).to have_css(
        "[data-notifications-bell-badge]",
        text: "10+",
        visible: :visible
      )
    end

    it "announces the count via aria-label" do
      deliver_n_security_notifications(2)

      visit root_path

      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["aria-label"]).to include("2")
    end
  end

  describe "dropdown panel open/close" do
    it "opens when the bell is clicked and toggles aria-expanded" do
      visit root_path

      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["aria-expanded"]).to eq("false")

      bell.click

      expect(page).to have_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )
      expect(bell["aria-expanded"]).to eq("true")
    end

    it "closes when Escape is pressed" do
      visit root_path
      bell = find("button[data-notifications-bell-trigger]")
      bell.click
      expect(page).to have_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )

      page.send_keys(:escape)

      expect(page).to have_no_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )
      expect(bell["aria-expanded"]).to eq("false")
    end
  end
end
