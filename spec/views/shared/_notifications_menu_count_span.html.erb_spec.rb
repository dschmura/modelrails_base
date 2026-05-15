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
end
