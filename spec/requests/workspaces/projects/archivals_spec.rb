require "rails_helper"

# Archive is a state, so it is a singular resource: POST archives, DELETE
# restores. Replaced the PATCH :archive / :unarchive member actions (#1007).
RSpec.describe "Project Archival", type: :request do
  describe "unauthenticated access" do
    it "redirects POST /workspaces/:workspace_slug/projects/:slug/archival to sign in" do
      post workspace_project_archival_path(workspace_slug: "any-slug", project_slug: "any-project")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }
    let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
    let(:project) { create(:project, workspace: workspace, created_by: user) }

    before do
      Current.workspace = workspace
      sign_in(user)
    end

    describe "POST /workspaces/:workspace_slug/projects/:slug/archival" do
      it "archives the project and redirects to the projects index" do
        post workspace_project_archival_path(workspace, project)
        expect(project.reload).to be_archived
        expect(response).to redirect_to(workspace_projects_path(workspace))
        expect(flash[:notice]).to eq(I18n.t("workspaces.projects.archivals.create.success"))
      end

      it "denies a project member who cannot manage the workspace" do
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        create(:project_membership, user: member, project: project)
        sign_in(member)
        post workspace_project_archival_path(workspace, project)
        expect(project.reload).not_to be_archived
      end
    end

    describe "DELETE /workspaces/:workspace_slug/projects/:slug/archival" do
      it "restores an archived project and redirects to it" do
        project.archive!
        delete workspace_project_archival_path(workspace, project)
        expect(project.reload).not_to be_archived
        expect(response).to redirect_to(workspace_project_path(workspace, project))
        expect(flash[:notice]).to eq(I18n.t("workspaces.projects.archivals.destroy.success"))
      end
    end
  end
end
