require "rails_helper"

RSpec.describe SettingsNavigationHelper, type: :helper do
  describe "#settings_context_kind" do
    it "returns :personal when Current.workspace.personal? is true" do
      personal = build_stubbed(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(personal)
      expect(helper.settings_context_kind).to eq(:personal)
    end

    it "returns :org when Current.workspace.personal? is false" do
      org = build_stubbed(:workspace, personal: false)
      allow(Current).to receive(:workspace).and_return(org)
      expect(helper.settings_context_kind).to eq(:org)
    end

    it "returns :personal when Current.workspace is nil (safe default for unauthenticated edge)" do
      allow(Current).to receive(:workspace).and_return(nil)
      expect(helper.settings_context_kind).to eq(:personal)
    end
  end

  describe "#nav_item_if_permitted" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }

    before do
      allow(helper).to receive(:current_user).and_return(user)
      allow(Current).to receive(:user).and_return(user)
      allow(Current).to receive(:workspace).and_return(workspace)
    end

    it "yields when the policy permits the action" do
      allow(WorkspacePolicy).to receive(:new)
        .with(user, workspace).and_return(instance_double(WorkspacePolicy, edit?: true))

      output = helper.nav_item_if_permitted(workspace, action: :edit?) { "RENDERED" }
      expect(output).to eq("RENDERED")
    end

    it "returns nil when the policy denies the action" do
      allow(WorkspacePolicy).to receive(:new)
        .with(user, workspace).and_return(instance_double(WorkspacePolicy, edit?: false))

      output = helper.nav_item_if_permitted(workspace, action: :edit?) { "RENDERED" }
      expect(output).to be_nil
    end

    it "infers the policy class from the record" do
      membership = create(:membership, user: user, workspace: workspace)
      allow(MembershipPolicy).to receive(:new)
        .with(user, membership).and_return(instance_double(MembershipPolicy, index?: true))

      output = helper.nav_item_if_permitted(membership, action: :index?) { "RENDERED" }
      expect(output).to eq("RENDERED")
    end
  end
end
