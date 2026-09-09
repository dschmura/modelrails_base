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

  # The index used to be the one authenticated page without the switcher —
  # "the index IS the switcher". That left it the one page where the
  # affordance vanished. It now keeps the switcher in place, on phones, in an
  # "All workspaces" state: no workspace is current there, so the trigger
  # names the index and the menu marks that row current (#1090).
  describe "on the workspaces index (no current workspace)" do
    let!(:second) do
      ws = create(:workspace, name: "Zeta Org")
      create(:membership, :owner, user: user, workspace: ws)
      ws
    end

    it "renders the phone trigger in the All-workspaces state, with no role" do
      get workspaces_path
      doc = Nokogiri::HTML(response.body)

      trigger = doc.at_css("#workspace-switcher-button-mobile")
      expect(trigger).not_to be_nil, "no phone trigger on the index"
      expect(trigger.text).to include(I18n.t("navigation.all_workspaces"))
      expect(trigger.at_css("#workspace-identity-role-mobile")).to be_nil, "a role rendered with no workspace current"
      expect(doc.at_css("#workspace-switcher-button")).to be_nil, "the index has no sidebar; no desktop copy expected"
    end

    it "marks All workspaces current in the menu and still lists the workspaces" do
      get workspaces_path
      menu = Nokogiri::HTML(response.body).at_css("#workspace-switcher-menu-mobile")

      current = menu.css("a[aria-current]")
      expect(current.map { |a| a["href"] }).to eq([ workspaces_path ])
      expect(menu.css("a[role=menuitem]").map { |a| a["href"] }).to include(workspace_path(second))
    end

    it "puts no id on the page twice" do
      get workspaces_path
      ids = Nokogiri::HTML(response.body).css("[id]").map { |el| el["id"] }

      expect(ids.tally.select { |_, n| n > 1 }.keys).to be_empty
    end
  end

  it "is absent from account settings, which carries no workspace context" do
    get edit_settings_profile_path

    expect(trigger_in(response.body)).to be_nil
  end
end
