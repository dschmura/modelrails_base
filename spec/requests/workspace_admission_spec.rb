require "rails_helper"

# Exercises ApplicationController's app-wide Workspace::NotAdmittableError
# rescue (not_admittable). The widened site-guards added in Task 5 reject
# before Workspace#admit is ever reached, so without this spec the rescue
# itself would be untested. Stubs #admit to force the error past a guard
# that otherwise passes, on an active/open-join workspace.
RSpec.describe "Workspace admission (not_admittable rescue)", type: :request do
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
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
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
    sign_in(newcomer)
    allow_any_instance_of(Workspace).to receive(:admit).and_raise(Workspace::NotAdmittableError)
  end

  it "redirects to root_path with the generic invalid_or_revoked flash, never disclosing lifecycle state" do
    post workspace_join_path(workspace, token: link.token)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
    expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
  end
end
