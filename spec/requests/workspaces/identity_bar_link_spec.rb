require "rails_helper"

RSpec.describe "Workspace identity bar name-link", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "links the workspace name to the Overview with an explicit accessible name" do
    get edit_workspace_path(workspace) # a non-Overview workspace page
    doc = Nokogiri::HTML(response.body)
    link = doc.at_css('a#workspace-name-heading') || doc.at_css('#workspace-name-heading a')
    expect(link).not_to be_nil
    expect(link["href"]).to eq(workspace_path(workspace))
    accessible_name = link["aria-label"].presence || link.text.strip
    expect(accessible_name).to be_present
  end

  it "keeps the name a link after the Profile-update broadcast replaces #workspace-name-heading" do
    patch workspace_path(workspace), params: { workspace: { name: "New Acme" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    doc = Nokogiri::HTML(response.body)
    link = doc.at_css('a#workspace-name-heading')
    expect(link).not_to be_nil, "expected the broadcast fragment to re-render #workspace-name-heading as a link, not a span"
    expect(link["href"]).to eq(workspace_path(workspace.reload))
  end
end
