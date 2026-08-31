require "rails_helper"

RSpec.describe "Project Invitations", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/projects/:project_slug/invitations/new to sign in" do
      get new_workspace_project_invitation_path(workspace_slug: "any-slug", project_slug: "any-project")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }
    let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
    let(:project) { create(:project, workspace: workspace, created_by: user) }
    let!(:creator_pm) { project.project_memberships.find_by!(user: user) }

    before do
      Current.workspace = workspace
      sign_in(user)
    end

    describe "GET new project invitation" do
      it "renders the invitation form" do
        get new_workspace_project_invitation_path(workspace, project)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST create project invitation" do
      it "creates an invitation for a non-workspace member" do
        expect {
          post workspace_project_invitations_path(workspace, project), params: {
            invitation: { email: "outsider@example.com", project_role: "editor" }
          }
        }.to change(Invitation, :count).by(1)
          .and have_enqueued_mail(InvitationMailer, :invite)
      end

      it "rejects creator role in project_role" do
        post workspace_project_invitations_path(workspace, project), params: {
          invitation: { email: "outsider@example.com", project_role: "creator" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects invalid email" do
        post workspace_project_invitations_path(workspace, project), params: {
          invitation: { email: "not-an-email", project_role: "editor" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      # A blank field is invalid input, not "no address": a nil email is a
      # bearer (magic-link) invitation, and a form submission must never mint one.
      it "rejects a blank email instead of creating a bearer invitation" do
        expect {
          post workspace_project_invitations_path(workspace, project), params: {
            invitation: { email: "  ", project_role: "editor" }
          }
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      # A ghost vacates the `pending_live` slot, so this second POST used to
      # succeed where the unblocked one hit the index with no uniqueness
      # validation to catch it — a 500 versus a success redirect, the widest
      # possible tell that a block exists (invariant I3).
      describe "a blocked re-invite is refused exactly like an unblocked one" do
        include ActiveJob::TestHelper

        def re_invite_outcome(email)
          2.times do |attempt|
            post workspace_project_invitations_path(workspace, project), params: {
              invitation: { email: email, project_role: "editor" }
            }
            # Performs the mailer guard, which stamps the blocked row. only:,
            # because the user factory also queues CheckGravatarJob (network I/O).
            perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) if attempt.zero?
          end
          [ response.status, flash[:alert], Invitation.where(email: email).count ]
        end

        it "returns the same status, flash and record count either way" do
          create(:invitation_block, inviter: user, email: "blocked@example.com")

          blocked = re_invite_outcome("blocked@example.com")
          unblocked = re_invite_outcome("open@example.com")

          expect(blocked).to eq(unblocked)
          expect(blocked).to eq(
            [ 422, I18n.t("workspaces.projects.invitations.create.already_invited"), 1 ]
          )
        end
      end
    end

    describe "accepting a project invitation" do
      let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
      let!(:invitation) do
        project.invitations.create!(
          email: "invitee@example.com",
          role: viewer_role,
          project_role: "editor",
          invited_by: user,
          expires_at: 7.days.from_now
        )
      end

      it "auto-adds invitee to workspace and project" do
        invitee = create(:user, email_address: "invitee@example.com")
        sign_in(invitee)
        post accept_invitation_path(token: invitation.token)
        expect(invitee.workspaces).to include(workspace)
        expect(invitee.projects).to include(project)
      end

      it "assigns the correct project role" do
        invitee = create(:user, email_address: "invitee@example.com")
        sign_in(invitee)
        post accept_invitation_path(token: invitation.token)
        pm = project.project_memberships.find_by(user: invitee)
        expect(pm).to be_editor
      end

      it "rejects acceptance of archived project invitation" do
        project.discard!
        invitee = create(:user, email_address: "invitee2@example.com")
        invitation2 = project.invitations.create!(
          email: "invitee2@example.com",
          role: viewer_role,
          project_role: "editor",
          invited_by: user,
          expires_at: 7.days.from_now
        )
        sign_in(invitee)
        post accept_invitation_path(token: invitation2.token)
        expect(response).to redirect_to(root_path)
      end
    end

    describe "authorization" do
      let(:editor) { create(:user) }
      let!(:editor_ws) { create(:membership, user: editor, workspace: workspace) }
      let!(:editor_pm) { create(:project_membership, project: project, user: editor) }

      it "denies editor from creating project invitations" do
        sign_in(editor)
        post workspace_project_invitations_path(workspace, project), params: {
          invitation: { email: "denied@example.com", project_role: "viewer" }
        }
        expect(response).to have_http_status(:redirect)
        expect(Invitation.where(email: "denied@example.com")).to be_empty
      end
    end
  end
end
