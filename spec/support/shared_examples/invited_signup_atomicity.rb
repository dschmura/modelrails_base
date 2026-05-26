RSpec.shared_examples "an invited signup path that consumes invitations" do
  it "creates the user, consumes the invitation, and adds workspace membership" do
    invitation = create(:invitation, invitable: workspace, email: signup_email)
    post accept_invitation_path(token: invitation.token)
    expect(response).to have_http_status(:found).or have_http_status(:see_other)

    expect { perform_signup }.to change(User, :count).by(1)

    expect(invitation.reload).to be_accepted
    new_user = User.find_by(email_address: signup_email)
    expect(new_user).to be_present
    expect(new_user.workspaces).to include(workspace)
  end

  it "does NOT consume the invitation if signup fails (validation)" do
    invitation = create(:invitation, invitable: workspace, email: signup_email)
    post accept_invitation_path(token: invitation.token)

    expect { perform_failing_signup }.not_to change(User, :count)
    expect(invitation.reload).to be_pending
  end
end
