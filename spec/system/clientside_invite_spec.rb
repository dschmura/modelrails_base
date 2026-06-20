# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client invite flow", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:owner) { create(:user) }
  let(:workspace) { owner.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: owner, clientside_enabled: true).tap do |p|
      p.project_memberships.create!(user: owner, role: "creator")
    end
  end

  # Confirms the team-owner path: the invite form renders AAA-clean and
  # a submitted client invite creates an invitation record.
  it "team owner opens the client invite form (AAA) and sends a client invite" do
    sign_in_via_form(owner)
    visit new_workspace_project_client_invitation_path(workspace, project)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on invite form: #{axe_violations_in_both_themes(axe_options).join("\n")}"

    fill_in I18n.t("clientside.invitations.new.email_label"), with: "dana@bigco.com"
    fill_in I18n.t("clientside.invitations.new.company_label"), with: "BigCo"
    click_button I18n.t("clientside.invitations.new.submit")
    # Wait for the redirect to the clientside edit page (Turbo navigates after redirect).
    expect(page).to have_text(I18n.t("clientside.invitations.sent"))

    invitation = Invitation.where(invitable: project).where.not(company_name: nil).last
    expect(invitation).to be_present
    expect(invitation.email).to eq("dana@bigco.com")
    expect(invitation.company_name).to eq("BigCo")
  end

  # Confirms the client accept path: the accept page renders AAA-clean
  # and the client framing (title heading + project name in body) is present.
  it "accept page renders AAA-clean for a client invite token" do
    invitation = Invitation.invite_client!(
      project: project,
      email: "dana@bigco.com",
      company_name: "BigCo",
      invited_by: owner
    )

    visit accept_invitation_path(token: invitation.token)

    # Assert client framing renders — these fail on a blank or 500 page.
    expect(page).to have_content(I18n.t("invitation_accepts.show.title"))
    expect(page).to have_content(project.name)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on accept page: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
