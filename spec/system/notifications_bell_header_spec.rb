# frozen_string_literal: true

require "rails_helper"

# D1: notifications bell is a standalone header affordance. Sits to the
# left of the avatar on desktop (≥md) and to the left of the hamburger on
# mobile (<md). Replaces the old avatar-overlay bell (the bell glyph used
# to overlay the avatar button and required a dropdown-traversal to reach
# the triage page).
RSpec.describe "Notifications bell — standalone header link", type: :system, js: true do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  before do
    sign_in_via_form(user)
    # Signing in creates a SignInFromNewDeviceNotifier (severity :danger);
    # mark them read so each example controls its own unread state.
    user.notifications.where(read_at: nil).update_all(read_at: Time.current)
  end

  describe "desktop layout (≥md)" do
    it "renders the bell link as a sibling of the avatar inside the desktop right block" do
      visit root_path
      expect(page).to have_css("#notifications-bell-link")
      expect(page).to have_link(href: account_notifications_path)
    end

    it "routes to the notifications triage page when the bell is clicked" do
      visit root_path
      find("#notifications-bell-link").click
      expect(page).to have_current_path(account_notifications_path)
    end

    it "renders the bell label broadcast frame inside the bell link" do
      visit root_path
      expect(page).to have_css("turbo-frame#notifications_bell_label_frame", visible: :all)
      # The bell link itself is OUTSIDE the label frame (only the sr-only
      # span gets replaced on broadcast; the focusable link stays stable).
      expect(page).to have_no_css("turbo-frame#notifications_bell_label_frame #notifications-bell-link")
    end

    it "renders the bell indicator frame inside the bell link" do
      visit root_path
      expect(page).to have_css("turbo-frame#notifications_bell_indicator_frame", visible: :all)
    end

    it "renders no severity overlay when there are no unread notifications" do
      visit root_path
      expect(page).not_to have_css("[data-bell-severity]")
    end

    it "renders a danger overlay when a security notification is unread" do
      PasswordChangedNotifier.with(record: user).deliver(user)
      visit root_path
      expect(page).to have_css("[data-bell-severity='danger']")
      expect(page).to have_css(".text-danger")
    end

    it "renders a warning overlay for billing notifications" do
      workspace = create(:workspace)
      create(:membership, :owner, user: user, workspace: workspace)
      WorkspaceCapacityApproachingNotifier.with(
        record: workspace, metric: :members, current: 9, limit: 10
      ).deliver(user)
      visit root_path
      expect(page).to have_css("[data-bell-severity='warning']")
      expect(page).to have_css(".text-warning")
    end

    it "shows highest-severity color and aggregate count when mixed categories are unread" do
      # danger
      PasswordChangedNotifier.with(record: user).deliver(user)
      # success — WorkspaceMemberAddedNotifier.with(record: membership).deliver(user)
      success_workspace = create(:workspace)
      added_membership = create(:membership, user: user, workspace: success_workspace)
      WorkspaceMemberAddedNotifier.with(record: added_membership).deliver(user)

      visit root_path
      # Bell color convergence: highest severity (danger) wins.
      expect(page).to have_css("[data-bell-severity='danger']")
      # aria-label convergence: count reflects the full unread set (was the
      # "Surface 2" assertion in the retired avatar_indicator convergence spec).
      label_text = page.find("#notifications_bell_label", visible: :all).text(:all)
      expect(label_text).to include("2 unread")
    end

    it "does not render the obsolete notifications dropdown panel (regression guard)" do
      # Pre-D1 the unread bell hung off the avatar and clicking it opened a
      # notifications dropdown. D1 replaced that with this standalone bell link.
      # If a refactor regresses to the old pattern, this guard catches it.
      PasswordChangedNotifier.with(record: user).deliver(user)
      visit root_path
      expect(page).not_to have_css("#notifications-dropdown-panel")
      expect(page).not_to have_css("[data-controller~='notification-dropdown']")
    end

    it "live-updates the bell label and indicator when a notification arrives via broadcast" do
      visit root_path
      expect(page).not_to have_css("[data-bell-severity]")

      perform_enqueued_jobs do
        PasswordChangedNotifier.with(record: user).deliver(user)
      end

      expect(page).to have_css("[data-bell-severity='danger']", wait: 5)
      label_text = page.find("#notifications_bell_label", visible: :all).text(:all)
      expect(label_text).to include("1 unread")
      expect(label_text).to include("security alert")
    end

    it "keeps the bell link DOM node stable across broadcasts (only the label is replaced)" do
      visit root_path
      expect(page).not_to have_css("[data-bell-severity]")

      page.execute_script(<<~JS)
        document.getElementById("notifications-bell-link").setAttribute("data-stability-probe", "link-pre");
        document.getElementById("notifications_bell_label").setAttribute("data-stability-probe", "label-pre");
      JS

      perform_enqueued_jobs do
        PasswordChangedNotifier.with(record: user).deliver(user)
      end

      expect(page).to have_css(
        "#notifications_bell_label",
        visible: :all,
        text: "1 unread",
        wait: 5
      )
      # Label is replaced — probe disappears.
      expect(page.find("#notifications_bell_label", visible: :all)["data-stability-probe"]).to be_nil
      # Link is NOT replaced — probe persists.
      expect(page.find("#notifications-bell-link")["data-stability-probe"]).to eq("link-pre")
    end
  end

  describe "mobile layout (<md, 375x667)" do
    before do
      page.driver.with_playwright_page do |pw_page|
        pw_page.set_viewport_size(width: 375, height: 667)
      end
    end

    it "renders the bell link in the top header row, beside the hamburger" do
      visit root_path
      expect(page).to have_css("#notifications-bell-link")
      # Hamburger is also present in the same row
      expect(page).to have_css("[data-mobile-menu-target='button']")
    end

    it "routes to the notifications triage page when the bell is tapped" do
      visit root_path
      find("#notifications-bell-link").click
      expect(page).to have_current_path(account_notifications_path)
    end
  end
end
