require "rails_helper"

RSpec.describe "Project tools settings", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user)
  end

  before { sign_in(user) }

  it "renders the toggle form" do
    get edit_workspace_project_tools_path(workspace, project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Docs &amp; Files")
  end

  # #737: tool rows render through the FormBuilder's checkbox — one ≥44px
  # label-wrapped target per row (2.5.5; the raw markup had none) with the
  # tool description as describedby-wired help, not a bare styled span.
  it "renders each tool as a builder checkbox row with a 44px target and wired description" do
    get edit_workspace_project_tools_path(workspace, project)
    page = Capybara.string(response.body)

    expect(page).to have_css("label.min-h-11 input[type='checkbox'][name='project[enabled_tools][]']", minimum: 1)
    docs_input = page.find("input[type='checkbox'][value='docs']")
    describedby = docs_input["aria-describedby"]
    expect(describedby).to be_present
    expect(page.find("##{describedby.split.first}").text).to be_present
  end

  it "updates enabled_tools, intersected with toggleable keys" do
    patch workspace_project_tools_path(workspace, project),
      params: { project: { enabled_tools: [ "docs", "bogus" ] } }
    expect(project.reload.enabled_tools).to eq([ "docs" ])
    expect(response).to redirect_to(edit_workspace_project_tools_path(workspace, project))
  end

  it "treats an absent checkbox group as all-off" do
    patch workspace_project_tools_path(workspace, project), params: { project: {} }
    expect(project.reload.enabled_tools).to eq([])
  end

  # Pundit wiring: a workspace member who does not hold the :creator
  # project-membership role has no update? permission. Proves authorize is
  # actually invoked — removing authorize from the controller would let
  # these requests succeed.
  describe "authorization: non-managing member is denied" do
    let(:viewer) { create(:user) }

    before do
      # Give the viewer a workspace membership (member role — no manage_projects).
      workspace.memberships.create!(
        user: viewer,
        role: Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member"; r.permissions = {} }
      )
      # Give the viewer a project membership as a viewer, not a creator.
      project.project_memberships.create!(user: viewer, role: "viewer")
      sign_in(viewer)
    end

    it "GET edit redirects with not_authorized flash" do
      get edit_workspace_project_tools_path(workspace, project)
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end

    it "PATCH update redirects and leaves enabled_tools unchanged" do
      original_tools = project.reload.enabled_tools.dup
      patch workspace_project_tools_path(workspace, project),
        params: { project: { enabled_tools: [] } }
      expect(response).to have_http_status(:redirect)
      expect(project.reload.enabled_tools).to eq(original_tools)
    end
  end
end
