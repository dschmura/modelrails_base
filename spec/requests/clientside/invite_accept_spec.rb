require "rails_helper"

RSpec.describe "Accepting a client invitation", type: :request do
  let(:project) { create(:project, clientside_enabled: true) }
  let(:inviter) { project.created_by }
  let(:invitation) do
    Invitation.invite_client!(project: project, email: "dana@bigco.com",
                              company_name: "BigCo", invited_by: inviter)
  end

  it "an existing user gets a ClientAccess and lands in the client area" do
    client = create(:user, :with_zero_workspaces, email_address: "dana@bigco.com")
    sign_in(client)
    post accept_invitation_path(token: invitation.token)
    expect(project.client?(client)).to be(true)
    expect(response).to redirect_to(clientside_project_path(project))
  end
end
