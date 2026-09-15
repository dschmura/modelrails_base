require "rails_helper"

RSpec.describe "Onboarding · team step", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:user) { create(:user, :with_zero_workspaces) }
  let(:workspace) { create(:workspace) }
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let!(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    end
  end
  let!(:project) { create(:project, workspace: workspace) }

  before do
    workspace.memberships.create!(user: user, role: owner_role)
    sign_in(user)
  end

  it "renders the invite form" do
    get new_onboarding_team_path
    expect(response).to have_http_status(:ok)
  end

  # A fork whose project noun is "team" (config/vocabulary.local.yml) must not
  # read Course · Team · Tools · Team: a fixed step label cannot be a word the
  # vocabulary can turn a noun into. (#1144)
  it "keeps the stepper's fixed labels distinct from the project noun" do
    renamed = Vocabulary.tokens.merge(project: "team", projects: "teams", Project: "Team", Projects: "Teams")
    allow(Vocabulary).to receive(:tokens).and_return(renamed)

    get new_onboarding_team_path

    labels = Nokogiri::HTML(response.body).css("ol[aria-label] li p").map { |p| p.text.strip }
    expect(labels.size).to eq(4)
    expect(labels).to eq(labels.uniq)
  end

  # Two realistic addresses as a placeholder read as values already typed; the
  # members page's field carries a hint and no placeholder. (#1144)
  it "hints the email field instead of pre-filling it with example addresses" do
    get new_onboarding_team_path

    html = Capybara.string(response.body)
    textarea = html.find("textarea[name='invitation[emails]']")
    expect(textarea[:placeholder]).to be_nil
    expect(html).to have_text(I18n.t("onboarding.teams.new.emails_help"))
  end

  it "sends invites, completes onboarding, and lands on the project" do
    expect {
      post onboarding_team_path, params: {
        invitation: { emails: "sam@example.com, lee@example.com", role_id: member_role.id }
      }
    }.to change(Invitation, :count).by(2)

    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end

  it "re-renders when no emails are provided" do
    post onboarding_team_path, params: { invitation: { emails: "", role_id: member_role.id } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.onboarded?).to be(false)
  end

  it "skipping (PATCH onboarding) completes onboarding without invites" do
    expect {
      patch onboarding_path
    }.not_to change(Invitation, :count)
    expect(user.reload.onboarded?).to be(true)
    expect(response).to redirect_to(workspace_project_path(workspace, project))
  end
end
