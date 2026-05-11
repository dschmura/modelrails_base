require "rails_helper"

# User-menu dropdown — desktop and mobile contexts. Renders the avatar
# button + dropdown items including the notifications-preferences link.
# This spec focuses on the unread-dot indicator on that link, which marks
# the preferences page as "new/changed" until the user dismisses the
# migration banner inside it. Pure CSS via Tailwind `after:` pseudo-element
# + a `data-unread-dot` hook so the assertion doesn't need to escape
# Tailwind colons in CSS selectors.
RSpec.describe "shared/_user_menu", type: :view do
  let(:user) { create(:user) }

  before do
    user.create_preferences!(timezone: "UTC") unless user.preferences
    # Current.user is delegated through Current.session (Rails 8 auth);
    # stub directly so we don't need a real session record.
    allow(Current).to receive(:user).and_return(user)
    # `authenticated?` lives on ApplicationController, not on ActionView::Base.
    # In a view spec, the view's helper proxy doesn't expose it — wrap stubs
    # in without_partial_double_verification so RSpec's verifying-doubles
    # gate doesn't reject the missing method.
    without_partial_double_verification do
      allow(view).to receive(:authenticated?).and_return(true)
    end
  end

  context "notification-preferences link unread dot" do
    it "marks the preferences link with data-unread-dot when banner has not been dismissed (desktop)" do
      user.preferences.update!(dismissed_notifications_redesign_banner_at: nil)

      render partial: "shared/user_menu", locals: { context: :desktop }

      expect(rendered).to have_css(
        %Q(a[href="#{edit_account_notification_preferences_path}"][data-unread-dot="true"]),
        visible: :all
      )
    end

    it "marks the preferences link with data-unread-dot when banner has not been dismissed (mobile)" do
      user.preferences.update!(dismissed_notifications_redesign_banner_at: nil)

      render partial: "shared/user_menu", locals: { context: :mobile }

      expect(rendered).to have_css(
        %Q(a[href="#{edit_account_notification_preferences_path}"][data-unread-dot="true"]),
        visible: :all
      )
    end

    it "omits data-unread-dot once the banner has been dismissed" do
      user.preferences.update!(dismissed_notifications_redesign_banner_at: 1.minute.ago)

      render partial: "shared/user_menu", locals: { context: :desktop }

      expect(rendered).to have_css(%Q(a[href="#{edit_account_notification_preferences_path}"]))
      expect(rendered).not_to have_css(
        %Q(a[href="#{edit_account_notification_preferences_path}"][data-unread-dot="true"]),
        visible: :all
      )
    end
  end
end
