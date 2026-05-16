require "rails_helper"

RSpec.describe "shared/_user_menu_avatar_button.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Dave", last_name: "Chmura") }

  it "renders a button that delegates its accessible name via aria-labelledby" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('aria-labelledby="user_menu_button_label"')
    expect(rendered).to include('id="user-menu-button"')
    expect(rendered).to include('aria-haspopup="true"')
    expect(rendered).to include('aria-expanded="false"')
  end

  it "does NOT carry an aria-label directly on the button" do
    # aria-label moved to the sibling sr-only span so the button itself
    # stays stable across broadcasts. See _user_menu_avatar_button_label.
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).not_to match(/<button[^>]*\baria-label=/)
  end

  it "nests the avatar image inside the button" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('id="user_avatar_header"')
  end

  it "renders the bell overlay partial as a sibling of the avatar inside the button" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('notifications_bell_indicator_frame')
    expect(rendered).to include('text-danger')
    expect(rendered).to include('data-bell-severity="danger"')
  end
end
