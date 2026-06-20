require "rails_helper"

RSpec.describe "Client landing via email verification", type: :request do
  it "lands a verified client-only user in the client area" do
    project = create(:project, clientside_enabled: true)
    client = create(:user, :with_email_auth, :with_zero_workspaces)
    project.client_accesses.create!(user: client, company_name: "BigCo")
    sign_in(client)
    auth = client.authentications.email.first
    token = auth.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    expect(response).to redirect_to(clientside_projects_path)
  end

  it "lands a member on root" do
    user = create(:user, :with_email_auth)
    sign_in(user)
    auth = user.authentications.email.first
    token = auth.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    expect(response).to redirect_to(root_path)
  end
end
