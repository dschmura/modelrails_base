require "rails_helper"

# The docs breadcrumb is the host's override of the markdowndocs gem partial;
# it renders through UI::Breadcrumb (W1 PR-F). Discriminators vs the old
# hand-rolled markup: slash separators (was chevron SVGs) and focus-ring links.
RSpec.describe "Docs breadcrumb", type: :request do
  it "renders through UI::Breadcrumb with slash separators and a current page" do
    get "/docs/developer/presets"
    expect(response).to have_http_status(:ok)

    nav = Capybara.string(response.body).find("nav[aria-label='Breadcrumb']")
    expect(nav).to have_css("ol a.focus-ring", minimum: 2)
    expect(nav).to have_css("[aria-current='page']")
    expect(nav).to have_css("span[aria-hidden='true']", text: "/", minimum: 2)
    expect(nav).to have_no_css("svg")
  end
end
