require "rails_helper"

# Regression guard for GHSA-xr9x-r78c-5hrm's breaking change. Action Text
# attachments carry no content-type allowlist (unlike avatars and logos), so a
# BMP/ICO/PSD can reach a document body. app/views/active_storage/blobs/_blob
# .html.erb links the variant as an <img>; processing is lazy, so the page
# itself still returns 200 and the Vips::Error lands on the representation
# request — a broken image plus a 500 in the log on every view. Rendering the
# file-chip branch instead is what keeps that off the page.
RSpec.describe "Document with a blocked-loader attachment", type: :request do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let!(:creator_pm) { project.project_memberships.find_by!(user: user) }
  let(:document) { create(:document) }
  let!(:resource) { create(:resource, project: project, created_by: user, resourceable: document) }

  before do
    Current.workspace = workspace
    Current.project = project
    sign_in(user)
  end

  def attach_to_document(fixture, content_type)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join("spec/fixtures/files", fixture).open,
      filename: fixture,
      content_type: content_type
    )
    document.update!(
      body: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>)
    )
  end

  def rendered_figure
    get workspace_project_resource_path(workspace, project, resource)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css("figure.attachment")
  end

  it "renders a blocked-loader attachment as a file chip, with no image to fetch" do
    attach_to_document("unfuzzed.bmp", "image/bmp")

    figure = rendered_figure

    expect(figure["class"]).to include("attachment--file")
    expect(figure.at_css("img")).to be_nil
  end

  it "still previews an attachment libvips can safely transform" do
    attach_to_document("avatar.png", "image/png")

    figure = rendered_figure

    expect(figure["class"]).to include("attachment--preview")
    expect(figure.at_css("img")).to be_present
  end
end
