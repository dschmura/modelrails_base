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

  # The dropdown controller's keydown handler doesn't fire reliably for
  # programmatic KeyboardEvent dispatch in Playwright's isolated context, so
  # we invoke the handler directly. Mirrors the pattern in user_menu_spec.rb.
  def send_dropdown_key(key)
    page.driver.with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (function() {
          var el = document.querySelector('[data-controller~="dropdown"]');
          var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'dropdown');
          if (c) c.handleKeydown(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
        })()
      JS
    end
  end

  it "updates the count inside an open menu without closing it or shifting focus" do
    visit root_path
    find("#user-menu-button").click
    expect(page).to have_css("#user-menu", visible: :visible)

    # Move focus from the first menu item (Profile) to Notifications (second
    # item) so we can verify focus retention on a non-default target. The
    # Notifications link's textContent prefix is stable even when the inline
    # count span re-renders.
    send_dropdown_key("ArrowDown")
    notifications_label = I18n.t("navigation.notifications")
    expect(
      page.evaluate_script("document.activeElement?.textContent?.trim()")
    ).to start_with(notifications_label)

    perform_enqueued_jobs do
      PasswordChangedNotifier.with(record: user).deliver(user)
    end

    # Menu stays open after the broadcast lands.
    expect(page).to have_css("#user-menu", visible: :visible, wait: 5)
    # Count text inside the menu (rendered in the notifications_menu_count_frame)
    # updates in-place.
    expect(page).to have_text("(1)", wait: 5)
    # Avatar overlay updates too (cross-check that the trio of broadcasts fired).
    expect(page).to have_css('[data-bell-severity="danger"]', wait: 5)
    # Focus stays on the Notifications menu item — the menu-count frame swap
    # happens INSIDE the link's child <turbo-frame>, not on the focused
    # ancestor. If a future refactor moves the frame upward (or replaces the
    # whole link), this assertion will catch the resulting focus loss.
    expect(
      page.evaluate_script("document.activeElement?.textContent?.trim()")
    ).to start_with(notifications_label)
  end
end
