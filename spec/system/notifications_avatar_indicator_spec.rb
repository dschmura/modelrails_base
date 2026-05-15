require "rails_helper"

RSpec.describe "Notifications avatar indicator", type: :system do
  include ActiveJob::TestHelper

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

  before do
    sign_in_via_form(user)
    # Signing in creates a SignInFromNewDeviceNotifier (severity :danger) that
    # would pollute every example's baseline. Clear it so each example controls
    # its own unread state.
    user.notifications.where(read_at: nil).update_all(read_at: Time.current)
  end

  it "renders no bell overlay when there are no unread notifications" do
    visit root_path
    expect(page).not_to have_css('[data-bell-severity]')
  end

  it "renders a danger overlay when a security notification is unread" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit root_path
    expect(page).to have_css('[data-bell-severity="danger"]')
    expect(page).to have_css('.text-danger')
  end

  it "renders a warning overlay for billing notifications" do
    workspace = create(:workspace)
    create(:membership, :owner, user: user, workspace: workspace)
    WorkspaceCapacityApproachingNotifier.with(
      record: workspace, metric: :members, current: 9, limit: 10
    ).deliver(user)
    visit root_path
    expect(page).to have_css('[data-bell-severity="warning"]')
    expect(page).to have_css('.text-warning')
  end

  it "shows highest-severity color when mixed categories are unread" do
    # danger
    PasswordChangedNotifier.with(record: user).deliver(user)
    # success — added_user is the Membership.user, so deliver to that user
    success_workspace = create(:workspace)
    added_membership = create(:membership, user: user, workspace: success_workspace)
    WorkspaceMemberAddedNotifier.with(record: added_membership).deliver(user)

    visit root_path
    expect(page).to have_css('[data-bell-severity="danger"]')
  end

  it "does not render the obsolete notifications dropdown panel" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit root_path
    expect(page).not_to have_css('#notifications-dropdown-panel')
    expect(page).not_to have_css('[data-controller~="notification-dropdown"]')
  end

  it "opens the user menu (not a notifications dropdown) when the avatar is clicked" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    visit root_path
    # Wait for the bell broadcast to settle so the click doesn't race a frame swap
    expect(page).to have_css('[data-bell-severity]')
    find("#user-menu-button").click
    expect(page).to have_css('#user-menu', visible: :visible)
    expect(page).to have_text(I18n.t("navigation.notifications"))
    expect(page).to have_text("(1)")
  end

  it "shows '10+' in the menu when more than 9 unread" do
    11.times do |i|
      PasswordChangedNotifier.with(record: user, idempotency_key: "k_#{i}").deliver(user)
    end
    visit root_path
    expect(page).to have_css('[data-bell-severity]')
    find("#user-menu-button").click
    expect(page).to have_text("(10+)")
  end

  it "live-updates overlay and aria-label when a notification arrives via broadcast" do
    visit root_path
    expect(page).not_to have_css('[data-bell-severity]')

    perform_enqueued_jobs do
      PasswordChangedNotifier.with(record: user).deliver(user)
    end

    expect(page).to have_css('[data-bell-severity="danger"]', wait: 5)
    expect(page.find("#user-menu-button")["aria-label"]).to include("1 unread notification")
    expect(page.find("#user-menu-button")["aria-label"]).to include("a security alert")
  end
end
