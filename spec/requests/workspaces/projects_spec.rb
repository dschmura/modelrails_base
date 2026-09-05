require "rails_helper"

RSpec.describe "Workspace Projects", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/projects to sign in" do
      get workspace_projects_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }
    let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before do
      Current.workspace = workspace
      sign_in(user)
    end

    describe "GET /workspaces/:workspace_slug/projects" do
      it "lists projects" do
        project = create(:project, workspace: workspace, created_by: user)
        get workspace_projects_path(workspace)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(project.name))
      end

      # #687: the index listed every kept project to any workspace member,
      # while ProjectPolicy#show? requires project membership — rows most
      # members could only bounce off. The scope: members see their projects;
      # workspace managers (who already hold lifecycle powers) see all.
      describe "index visibility (ProjectPolicy::Scope)" do
        let(:plain_member) { create(:user) }
        let!(:plain_membership) { create(:membership, user: plain_member, workspace: workspace) }
        let!(:mine) { create(:project, workspace: workspace, created_by: plain_member, name: "Mine Alone") }
        let!(:not_mine) { create(:project, workspace: workspace, created_by: user, name: "Somebody Elses") }

        it "shows a plain member only the projects they belong to" do
          sign_in(plain_member)
          get workspace_projects_path(workspace)

          expect(response.body).to include("Mine Alone")
          expect(response.body).not_to include(CGI.escapeHTML("Somebody Elses"))
        end

        it "shows a workspace manager every project" do
          get workspace_projects_path(workspace) # `user` is the owner

          expect(response.body).to include("Mine Alone")
          expect(response.body).to include(CGI.escapeHTML("Somebody Elses"))
        end

        it "scopes the archived section the same way" do
          not_mine.archive!
          sign_in(plain_member)
          get workspace_projects_path(workspace)

          expect(response.body).not_to include(CGI.escapeHTML("Somebody Elses"))
        end
      end

      it "renders the project initials through the avatar component" do
        project = create(:project, workspace: workspace, created_by: user)
        get workspace_projects_path(workspace)
        html = Capybara.string(response.body)
        # Scoped to the project card: the layout's workspace switcher renders the
        # same avatar markup (same size, substring-matchable initials), so an
        # unscoped, non-exact assertion can pass with the card's avatar deleted.
        card = html.find("a[href='#{workspace_project_path(workspace, project)}']")
        expect(card).to have_css("span.w-10.h-10[aria-hidden='true']", exact_text: project.initials)
        # The initials are aria-hidden, so the adjacent name is the card's whole
        # accessible name — assert it directly.
        expect(card).to have_text(project.name)
      end

      it "renders an attached logo through the component's recovery pair" do
        project = create(:project, workspace: workspace, created_by: user)
        project.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png",
          content_type: "image/png"
        )

        get workspace_projects_path(workspace)

        html = Capybara.string(response.body)
        card = html.find("a[href='#{workspace_project_path(workspace, project)}']")
        expect(card).to have_css(
          "[data-controller='avatar'] img[aria-hidden='true'][src*='/rails/active_storage/']"
        )
        expect(card).to have_css("span[data-avatar-target='fallback']", visible: :hidden)
      end

      # Regression guard: the avatar consolidation (PR-C) checks
      # project.logo.attached? per row, which loads logo_attachment per
      # project unless the index query eager-loads it. Bullet.raise fails
      # this example mid-request on any eager-load shape regression; the
      # single-row examples above can't trip Bullet's threshold-based
      # detector, so the multi-row fixture is what gives the guard teeth
      # (same mechanism as the workspaces#index guard).
      it "renders without N+1 queries (regression guard)" do
        projects = (1..3).map do |i|
          project = create(:project, workspace: workspace, created_by: user, name: "Project #{i}")
          project
        end

        get workspace_projects_path(workspace)

        expect(response).to have_http_status(:ok)
        projects.each do |project|
          expect(response.body).to include(CGI.escapeHTML(project.name))
        end
      end
    end

    describe "GET /workspaces/:workspace_slug/projects/new" do
      it "renders the new form" do
        get new_workspace_project_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /workspaces/:workspace_slug/projects" do
      it "creates a project and assigns creator role" do
        expect {
          post workspace_projects_path(workspace), params: { project: { name: "New Project" } }
        }.to change(Project, :count).by(1)

        project = Project.find_by!(name: "New Project")
        pm = project.project_memberships.find_by(user: user)
        expect(pm).to be_creator
      end

      it "enforces max_projects" do
        workspace.update!(max_projects: 1)
        create(:project, workspace: workspace, created_by: user)
        post workspace_projects_path(workspace), params: { project: { name: "Over Limit" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "GET /workspaces/:workspace_slug/projects/:slug" do
      let(:project) { create(:project, workspace: workspace, created_by: user) }

      it "shows the project" do
        get workspace_project_path(workspace, project)
        expect(response).to have_http_status(:ok)
      end

      # #746 (2.4.9 Link Purpose, AAA): a links-list rotor shows this link out
      # of context — "Edit" alone names no object. Literal string on purpose:
      # an I18n.t assertion would move with a wrong locale edit.
      it "names the edit link with its object for out-of-context reading" do
        get workspace_project_path(workspace, project)
        page = Capybara.string(response.body)
        expect(page).to have_link("Edit project", href: edit_workspace_project_path(workspace, project))
        expect(page).to have_no_link("Edit", exact: true)
      end

      it "renders the header initials through the avatar component" do
        get workspace_project_path(workspace, project)
        html = Capybara.string(response.body)
        expect(html).to have_css("span.w-16.h-16[aria-hidden='true']", exact_text: project.initials)
        # The initials are aria-hidden; the h1 carries the accessible name.
        expect(html).to have_css("h1", text: project.name)
      end

      it "denies non-project-members" do
        other = create(:user)
        create(:membership, user: other, workspace: workspace)
        sign_in(other)
        get workspace_project_path(workspace, project)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/projects/:slug" do
      let(:project) { create(:project, workspace: workspace, created_by: user) }

      it "updates the project" do
        patch workspace_project_path(workspace, project), params: { project: { name: "Updated" } }
        expect(project.reload.name).to eq("Updated")
      end
    end

    describe "DELETE /workspaces/:workspace_slug/projects/:slug" do
      let(:project) { create(:project, workspace: workspace, created_by: user) }

      it "soft deletes the project" do
        delete workspace_project_path(workspace, project)
        expect(project.reload).to be_discarded
      end
    end

    # Archive/restore moved to spec/requests/workspaces/projects/archivals_spec.rb with the resource (#1007).

    describe "GET /workspaces/:workspace_slug/projects/:slug/edit" do
      let(:project) { create(:project, workspace: workspace, created_by: user) }

      it "renders the edit form" do
        get edit_workspace_project_path(workspace, project)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /workspaces/:workspace_slug/projects with invalid params" do
      it "returns unprocessable entity for blank name" do
        post workspace_projects_path(workspace), params: { project: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/projects/:slug with invalid params" do
      let(:project) { create(:project, workspace: workspace, created_by: user) }

      it "returns unprocessable entity for blank name" do
        patch workspace_project_path(workspace, project), params: { project: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "GET /workspaces/:workspace_slug/projects/:slug with nonexistent slug" do
      it "redirects to projects list" do
        get workspace_project_path(workspace, "nonexistent-slug")
        expect(response).to redirect_to(workspace_projects_path(workspace))
      end
    end

    describe "discarded projects" do
      let(:project) { create(:project, workspace: workspace, created_by: user) }
      before do
        project.discard!
      end

      it "are excluded from show" do
        get workspace_project_path(workspace, project)
        expect(response).to redirect_to(workspace_projects_path(workspace))
      end
    end
  end
end
