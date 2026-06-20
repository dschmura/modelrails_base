# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client area", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) }
  let(:project) { access.project }

  before do
    access
    create(:resource, project: project, status: "published", shared_with_client: true, title: "Shared Doc")
    create(:resource, project: project, status: "published", shared_with_client: false, title: "Internal Doc")
    sign_in_via_form(client)
  end

  it "shows a client only the shared items, AAA in both themes" do
    visit clientside_project_path(project)
    expect(page).to have_link("Shared Doc")
    expect(page).to have_no_link("Internal Doc")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
  end
end
