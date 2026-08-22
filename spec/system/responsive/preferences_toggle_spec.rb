# frozen_string_literal: true

require "rails_helper"

# W1-3 (2026-08-22 view-layer audit (internal)): at phone widths a
# preferences-row title rendered twice — once from _preferences_row, once
# from _toggle's own visible label — colliding visually with the row title.
# This is a composition defect wherever a card pairs shared/toggle with
# shared/preferences_row using the same string for both `label:` and
# `title:` — confirmed in both the notification-types card (security, and
# every other category) and the delivery-methods card (in-app, email). The
# redundant toggle label must be suppressed visually (sr-only) since the
# row already shows the title. shared/_quiet_hours_card.html.erb does NOT
# use _preferences_row (custom layout — see its own file comment) and its
# toggle label ("Enable quiet hours") doesn't duplicate the card heading
# ("Quiet hours"), so it's untouched — no collision exists there.
RSpec.describe "Preferences toggle label at narrow viewports", type: :system do
  let(:password) { "TogglePrefs#42!" }
  let(:user)     { create(:user, password: password) }

  before do
    user.create_preferences!(timezone: "America/New_York")
    sign_in_via_form(user)
  end

  # Cuprite's visible-text/visible? checks only look at
  # display/visibility/opacity, not clip-path — confirmed via a throwaway
  # probe spec — so they don't recognize Tailwind's clip-path-based
  # `sr-only` trick as hidden, and `have_text(count:)` can't tell the
  # genuinely-visible row title apart from the visually-suppressed toggle
  # label by text content alone. Assert on the DOM directly instead (the
  # same class the fix applies), the way T1 asserts computed style rather
  # than trusting a high-level matcher.
  #
  # Target each element by its structural selector rather than a generic
  # text-equality scan: a wildcard "*" scan over exact-text matches false-
  # positives on every wrapper element between the toggle's label span and
  # its <label> ancestor when the row has no help text (form/label/span.flex-col
  # all reduce to the same single text node) — caught rewriting this for the
  # delivery-methods sibling card, which has no help text (unlike security).
  def assert_title_rendered_once_visually(title)
    row_title = find("p.text-sm.font-semibold.text-text-heading", text: title, visible: :all)
    toggle_label = find("label span.text-sm.text-text-body", text: title, visible: :all)

    expect(row_title[:class]).not_to include("sr-only")
    expect(toggle_label[:class]).to include("sr-only"),
      "expected the toggle's label span to carry sr-only, got class=#{toggle_label[:class].inspect}"
  end

  it "shows each preference title exactly once at 375px" do
    with_viewport(375) do
      visit edit_settings_notification_preferences_path

      title = I18n.t("notifications.preferences.notification_types.items.security.title")
      card_title_id = "preferences-card-#{I18n.t("notifications.preferences.notification_types.heading").parameterize}-title"

      within(:xpath, "(//*[@id='#{card_title_id}']/ancestor::section)[1]") do
        assert_title_rendered_once_visually(title)
      end
    end
  end

  it "shows the delivery-methods sibling card's preference title exactly once at 375px" do
    with_viewport(375) do
      visit edit_settings_notification_preferences_path

      title = I18n.t("notifications.preferences.delivery_methods.items.in_app.title")
      card_title_id = "preferences-card-#{I18n.t("notifications.preferences.delivery_methods.heading").parameterize}-title"

      within(:xpath, "(//*[@id='#{card_title_id}']/ancestor::section)[1]") do
        assert_title_rendered_once_visually(title)
      end
    end
  end
end
