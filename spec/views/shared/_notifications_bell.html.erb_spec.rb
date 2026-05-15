require "rails_helper"

RSpec.describe "shared/_notifications_bell.html.erb", type: :view do
  let(:user) { create(:user) }

  it "renders an empty turbo-frame when there are no unread notifications" do
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('<turbo-frame id="notifications_bell_indicator_frame">')
    expect(rendered).not_to include('data-bell-severity')
  end

  it "renders a danger-colored bell when the highest severity is :danger" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('text-danger')
    expect(rendered).to include('data-bell-severity="danger"')
    expect(rendered).to include('motion-safe:animate-pulse-danger')
    expect(rendered).to include('aria-hidden="true"')
    # The chip is gone — the bell itself is the indicator.
    expect(rendered).not_to include('bg-danger')
  end

  it "renders a warning-colored bell without the pulse class" do
    workspace = create(:workspace)
    owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |role|
      role.name = "Owner"
      role.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
    create(:membership, user: user, workspace: workspace, role: owner_role)
    WorkspaceCapacityApproachingNotifier.with(
      record: workspace, metric: "members", current: 9, limit: 10
    ).deliver(user)

    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('text-warning')
    expect(rendered).to include('data-bell-severity="warning"')
    expect(rendered).not_to include('animate-pulse-danger')
  end

  it "renders an info-colored bell for account_access notifications" do
    invitation = create(:invitation, email: user.email_address)
    WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('text-info')
    expect(rendered).to include('data-bell-severity="info"')
    expect(rendered).not_to include('animate-pulse-danger')
  end

  it "renders a success-colored bell for workspace_activity notifications" do
    workspace = create(:workspace)
    membership = create(:membership, user: user, workspace: workspace)
    WorkspaceMemberAddedNotifier.with(record: membership).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('text-success')
    expect(rendered).to include('data-bell-severity="success"')
    expect(rendered).not_to include('animate-pulse-danger')
  end
end
