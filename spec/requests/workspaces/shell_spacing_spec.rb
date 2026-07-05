require "rails_helper"

RSpec.describe "Workspace shell spacing hooks", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "pads the identity bar from the header/sidebar edges" do
    get workspace_path(workspace)
    doc = Nokogiri::HTML(response.body)
    bar = doc.at_css("#workspace_logo_show").ancestors("div").first
    expect(bar["class"]).to include("pt-4")
  end
end
