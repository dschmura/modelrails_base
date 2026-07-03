require "rails_helper"

RSpec.describe "Locked workspace gate", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }

  before do
    create(:membership, :owner, user: user, workspace: workspace)
    sign_in(user)
    workspace.suspend!
  end

  it "redirects workspace pages to the index with the locked notice" do
    get workspace_path(workspace)
    expect(response).to redirect_to(workspaces_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.locked_notice"))
  end

  it "gates nested workspace-scoped controllers too" do
    get workspace_projects_path(workspace)
    expect(response).to redirect_to(workspaces_path)
  end

  it "renders the index fine with a locked workspace present (nil-gate regression)" do
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "blocks the archive action (gate runs before the action)" do
    patch archive_workspace_path(workspace)
    expect(response).to redirect_to(workspaces_path)
    expect(workspace.reload).not_to be_archived
  end

  # Workspaces::JoinsController does not include WorkspaceScoped (it resolves
  # the workspace directly to serve unauthenticated visitors — see its own
  # docs), so the lock has to be enforced separately here. Outsiders following
  # a join link must not learn the workspace is locked: reuse the existing
  # invalid_or_revoked copy rather than locked_notice (privacy decision).
  describe "join links on a locked workspace" do
    let(:locked_workspace) { create(:workspace, personal: false, join_policy: "open_link", name: "Locked Co") }
    let(:owner) { create(:user) }
    let(:newcomer) { create(:user) }
    let!(:owner_role) {
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
      }
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      }
    }
    let(:link) { create(:workspace_join_link, workspace: locked_workspace, created_by: owner) }

    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      locked_workspace.memberships.create!(user: owner, role: owner_role)
      locked_workspace.suspend!
      sign_in(newcomer)
    end

    it "redirects the GET join page with the invalid_or_revoked flash (no locked disclosure)" do
      get workspace_join_path(locked_workspace, token: link.token)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
    end

    it "does not admit a new member on POST, and redirects with the invalid_or_revoked flash" do
      expect {
        post workspace_join_path(locked_workspace, token: link.token)
      }.not_to change(locked_workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
    end
  end
end
