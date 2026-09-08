require "rails_helper"

# The switcher is workspace chrome: it heads the workspace sidebar rather than
# the global header. Two consequences this file pins down — it renders on a
# workspace page even for a user with a single workspace (it is the only place
# the workspace is named), and it is absent from pages that carry no workspace
# context at all.
RSpec.describe "Workspace switcher placement", type: :request do
  let(:user) { create(:user) }                                  # :personal default → 1 workspace
  before { sign_in(user) }

  def trigger_in(html)
    Nokogiri::HTML(html).at_css("#workspace-switcher-button")
  end

  it "renders on a workspace page even with a single workspace" do
    get workspace_path(user.workspaces.kept.sole)

    expect(trigger_in(response.body)).not_to be_nil
  end

  it "lists the user's other workspaces in its menu" do
    second = create(:workspace, name: "Zeta Org")
    create(:membership, :owner, user: user, workspace: second)

    get workspace_path(second)

    doc = Nokogiri::HTML(response.body)
    expect(trigger_in(response.body).text).to include("Zeta Org")
    expect(doc.at_css("#workspace-switcher-menu").text).to include("Zeta Org")
  end

  it "is absent from the workspaces index, which carries no workspace context" do
    get workspaces_path

    expect(trigger_in(response.body)).to be_nil
  end

  it "is absent from account settings, which carries no workspace context" do
    get edit_settings_profile_path

    expect(trigger_in(response.body)).to be_nil
  end
end
