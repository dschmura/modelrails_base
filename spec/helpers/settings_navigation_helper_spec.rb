require "rails_helper"

RSpec.describe SettingsNavigationHelper, type: :helper do
  describe "#current_workspace_announcement_for_aria_live" do
    let(:user) { create(:user) }

    before do
      allow(Current).to receive(:user).and_return(user)
    end

    it "returns nil when Current.workspace is nil" do
      allow(Current).to receive(:workspace).and_return(nil)
      expect(helper.current_workspace_announcement_for_aria_live).to be_nil
    end

    it "returns nil when Current.workspace.personal? is true" do
      personal = build_stubbed(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(personal)
      expect(helper.current_workspace_announcement_for_aria_live).to be_nil
    end

    it "returns the full item list with workspace name and role for an Owner" do
      workspace = create(:workspace, name: "Acme Corp", personal: false)
      create(:membership, :owner, user: user, workspace: workspace)
      allow(Current).to receive(:workspace).and_return(workspace)

      result = helper.current_workspace_announcement_for_aria_live
      expect(result).to include("Acme Corp")
      expect(result).to include("Owner")
      expect(result).to include("Profile")
      expect(result).to include("Members")
      expect(result).to include("Limits & Plan")
    end

    it "includes Profile (manage_settings-gated) for an Admin alongside Members and Limits & Plan" do
      # Post route-consolidation, Profile is gated by Workspaces::ProfilePolicy
      # which checks manage_settings (held by Admin). Admins formerly edited
      # workspace identity via the branding route; ProfilePolicy preserves that
      # capability surface intentionally — see ProfilePolicy class comment.
      workspace = create(:workspace, name: "Beta LLC", personal: false)
      create(:membership, :admin, user: user, workspace: workspace)
      allow(Current).to receive(:workspace).and_return(workspace)

      result = helper.current_workspace_announcement_for_aria_live
      expect(result).to include("Beta LLC")
      expect(result).to include("Admin")
      expect(result).to include("Profile")
      expect(result).to include("Members")
      expect(result).to include("Limits & Plan")
    end

    it "falls back to the Member role label when no membership is found (defensive edge)" do
      workspace = create(:workspace, name: "Ghost Inc", personal: false)
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      allow(Current).to receive(:workspace).and_return(workspace)

      result = helper.current_workspace_announcement_for_aria_live
      expect(result).to include("Ghost Inc")
      expect(result).to include("Member")
    end
  end

  describe "#workspace_settings_nav_items" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
      allow(Current).to receive(:user).and_return(owner)
      allow(Current).to receive(:workspace).and_return(workspace)
      # current_page? is provided by the view context in a helper spec; stub it false.
      allow(helper).to receive(:current_page?).and_return(false)
    end

    it "returns Profile, Members, Limits & Plan for an owner" do
      labels = helper.workspace_settings_nav_items.map { |i| i[:label] }
      expect(labels).to eq([
        I18n.t("settings.sidebar.items.profile"),
        I18n.t("settings.sidebar.items.members"),
        I18n.t("settings.sidebar.items.limits_and_plan")
      ])
    end

    it "each item carries href + icon and gating is applied (no Limits & Plan for a member)" do
      member = create(:user)
      create(:membership, user: member, workspace: workspace) # non-owner
      allow(Current).to receive(:user).and_return(member)

      items = helper.workspace_settings_nav_items
      expect(items).to all(include(:href, :icon))
      labels = items.map { |i| i[:label] }
      expect(labels).not_to include(I18n.t("settings.sidebar.items.limits_and_plan"))
    end
  end

  describe "#identity_settings_nav_items" do
    before { allow(helper).to receive(:current_page?).and_return(false) }

    it "returns the five account items in order" do
      labels = helper.identity_settings_nav_items.map { |i| i[:label] }
      expect(labels).to eq([
        I18n.t("settings.sidebar.items.profile"),
        I18n.t("settings.sidebar.items.notifications"),
        I18n.t("settings.sidebar.items.security"),
        I18n.t("settings.sidebar.items.passkeys"),
        I18n.t("settings.sidebar.items.appearance")
      ])
    end
  end
end
