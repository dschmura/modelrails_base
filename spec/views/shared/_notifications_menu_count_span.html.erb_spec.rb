require "rails_helper"

RSpec.describe "shared/_notifications_menu_count_span.html.erb", type: :view do
  let(:user) { create(:user) }

  it "renders empty when there are no unread notifications" do
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered.strip).to eq("")
  end

  it "renders the unread count when positive" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered).to include("(1)")
  end

  it "renders '10+' when unread exceeds 9" do
    11.times do |i|
      PasswordChangedNotifier.with(record: user, idempotency_key: "n_#{i}").deliver(user)
    end
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered).to include("(10+)")
  end

  it "renders the literal count for boundary value 9" do
    9.times do |i|
      PasswordChangedNotifier.with(record: user, idempotency_key: "b9_#{i}").deliver(user)
    end
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered).to include("(9)")
    expect(rendered).not_to include("10+")
  end

  it "renders '10+' at boundary value 10" do
    10.times do |i|
      PasswordChangedNotifier.with(record: user, idempotency_key: "b10_#{i}").deliver(user)
    end
    render partial: "shared/notifications_menu_count_span", locals: { user: user }
    expect(rendered).to include("(10+)")
  end

  it "uses a passed-in summary without re-querying" do
    expect(user).not_to receive(:unread_notification_breakdown)
    render partial: "shared/notifications_menu_count_span",
           locals: { user: user, summary: { count: 5, severity: :info } }
    expect(rendered).to include("(5)")
  end
end
