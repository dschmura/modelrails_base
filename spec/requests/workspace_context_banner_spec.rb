require "rails_helper"

RSpec.describe "Workspace context banner", type: :request do
  let(:user) { create(:user) }                       # :personal → 1 workspace
  before { sign_in(user) }

  it "is absent with a single workspace" do
    get workspace_path(user.workspaces.first)
    expect(response.body).not_to include("workspace-context-banner")
  end

  it "shows 'You're in [name]' when the user has 2+ workspaces" do
    org = create(:workspace)
    create(:membership, :owner, user: user, workspace: org)
    get workspace_path(org)
    expect(response.body).to include("workspace-context-banner")
    expect(response.body).to include(CGI.escapeHTML(org.name))
  end
end
