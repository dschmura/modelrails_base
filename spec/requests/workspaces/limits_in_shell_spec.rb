require "rails_helper"

RSpec.describe "Limits & Plan in the workspace shell", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme", max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "renders in the shell with the secondary sub-nav and morph enabled" do
    get edit_workspace_settings_path(workspace)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#settings-aria-live")).to be_nil
    subnav = doc.at_css('nav[aria-label="' + I18n.t("settings.sidebar.strip_heading.workspace") + '"]')
    limits_current = subnav.css('a[aria-current="page"]').find { |a| a.text.include?(I18n.t("settings.sidebar.items.limits_and_plan")) }
    expect(limits_current).not_to be_nil
    # Same-URL save (#update redirects to edit_workspace_settings_path) will morph.
    meta = doc.at_css('meta[name="turbo-refresh-method"]')
    expect(meta && meta["content"]).to eq("morph")
  end
end
