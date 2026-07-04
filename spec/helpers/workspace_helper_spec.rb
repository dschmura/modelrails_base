require "rails_helper"

RSpec.describe WorkspaceHelper, type: :helper do
  describe "#workspace_shell_nav_items" do
    before { allow(helper).to receive(:current_page?).and_return(false) }

    it "omits Settings for a personal workspace (2 items)" do
      ws = create(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(ws)
      labels = helper.workspace_shell_nav_items.map { |i| i[:label] }
      expect(labels).to eq([ I18n.t("workspaces.sidebar.overview"), I18n.t("workspaces.sidebar.projects") ])
    end

    it "includes Settings (active: false) for an org workspace (3 items)" do
      ws = create(:workspace, personal: false)
      allow(Current).to receive(:workspace).and_return(ws)
      items = helper.workspace_shell_nav_items
      expect(items.map { |i| i[:label] }).to include(I18n.t("workspaces.sidebar.settings"))
      expect(items.last[:active]).to be(false)
    end
  end
end
