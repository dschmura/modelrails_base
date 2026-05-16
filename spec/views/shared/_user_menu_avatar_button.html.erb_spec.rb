require "rails_helper"

RSpec.describe "shared/_user_menu_avatar_button.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Dave", last_name: "Chmura") }

  it "renders a button with the plain aria-label when there are no unread" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('aria-label="User menu for Dave Chmura"')
    expect(rendered).to include('id="user-menu-button"')
    expect(rendered).to include('aria-haspopup="true"')
    expect(rendered).to include('aria-expanded="false"')
  end

  it "includes the count and severity phrase in the aria-label when unread > 0" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to match(/aria-label="User menu for Dave Chmura\. 1 unread notification, including a security alert\."/)
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
