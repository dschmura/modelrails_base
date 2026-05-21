require "rails_helper"

RSpec.describe "shared/_notifications_bell_link.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Dave", last_name: "Chmura") }

  it "renders an <a> linking to the account notifications path" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to match(%r{<a[^>]*\bhref="#{Regexp.escape(account_notifications_path)}"})
  end

  it "carries an id of notifications-bell-link for system spec hooks" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to include('id="notifications-bell-link"')
  end

  it "delegates its accessible name via aria-labelledby to the sr-only label" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to include('aria-labelledby="notifications_bell_label"')
    expect(rendered).to include('id="notifications_bell_label"')
    expect(rendered).to include('class="sr-only"')
  end

  it "renders the sr-only label inside the broadcast frame (notifications_bell_label_frame)" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to include('id="notifications_bell_label_frame"')
  end

  it "renders the bell indicator frame inside the link (for severity overlay broadcasts)" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to include('notifications_bell_indicator_frame')
  end

  it "applies the AAA touch-target utility class" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to match(%r{<a[^>]*\bclass="[^"]*btn-touch-target})
  end

  it "applies the AAA focus ring (ring-2, ring-offset-2, ring-interactive-focus)" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to match(/focus:ring-2/)
    expect(rendered).to match(/focus:ring-offset-2/)
    expect(rendered).to match(/focus:ring-interactive-focus/)
  end

  it "renders the bell icon inside the link" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    # The bell icon is rendered via the IconHelper; assert a SVG is present.
    expect(rendered).to match(/<svg\b/)
  end

  it "announces 'Notifications' when there are no unread notifications" do
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to include("Notifications")
    expect(rendered).not_to include("unread")
  end

  it "announces unread count + severity phrase when unread > 0" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/notifications_bell_link", locals: { user: user }
    expect(rendered).to match(/1 unread.*security alert/)
  end

  it "accepts a pre-computed summary local and does not re-query" do
    summary = { count: 2, severity: :warning }
    expect(user).not_to receive(:unread_notification_breakdown)
    render partial: "shared/notifications_bell_link",
           locals: { user: user, summary: summary }
    expect(rendered).to include("2 unread")
  end
end
