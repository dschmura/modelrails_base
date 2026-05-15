require "rails_helper"

RSpec.describe "shared/_notifications_bell.html.erb", type: :view do
  let(:user) { create(:user) }

  it "renders an empty turbo-frame when there are no unread notifications" do
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('<turbo-frame id="notifications_bell_indicator_frame">')
    expect(rendered).not_to include('<span')
  end

  it "renders a danger-colored bell when the highest severity is :danger" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-danger')
    expect(rendered).to include('text-danger-icon')
    expect(rendered).to include('data-bell-severity="danger"')
    expect(rendered).to include('motion-safe:animate-pulse-danger')
    expect(rendered).to include('aria-hidden="true"')
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
    expect(rendered).to include('bg-warning')
    expect(rendered).to include('text-warning-icon')
    expect(rendered).not_to include('animate-pulse-danger')
  end

  it "renders an info-colored bell for account_access notifications" do
    invitation = create(:invitation, email: user.email_address)
    WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-info')
    expect(rendered).to include('text-info-icon')
  end

  it "renders a success-colored bell for workspace_activity notifications" do
    workspace = create(:workspace)
    membership = create(:membership, user: user, workspace: workspace)
    WorkspaceMemberAddedNotifier.with(record: membership).deliver(user)
    render partial: "shared/notifications_bell", locals: { user: user }
    expect(rendered).to include('bg-success')
    expect(rendered).to include('text-success-icon')
  end
end
