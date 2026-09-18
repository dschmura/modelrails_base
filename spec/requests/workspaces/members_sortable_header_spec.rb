require "rails_helper"

# shared/_sortable_header used to hard-code data-turbo-frame="members_results",
# which made the partial unusable on any page without that frame (#1164). The
# members page now passes its frame explicitly; a caller passing nothing gets a
# plain link that targets whatever frame encloses it.
RSpec.describe "Sortable header frame local", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }

  before do
    create(:membership, :owner, user: user, workspace: workspace)
    sign_in(user)
  end

  it "targets the members frame because the members page passes frame: explicitly" do
    get workspace_members_path(workspace)
    link = Capybara.string(response.body).first(:link, I18n.t("workspaces.members.index.name"))
    expect(link["data-turbo-frame"]).to eq("members_results")
  end

  it "renders no frame target when the caller passes none" do
    html = ApplicationController.render(
      partial: "shared/sortable_header",
      locals: { title: "When", column: "created_at", current_sort: nil, current_direction: nil,
                url: ->(p) { "/x?#{p.to_query}" } }
    )
    link = Capybara.string(html).first(:link, "When")
    expect(link["data-turbo-frame"]).to be_nil
    expect(Capybara.string(html)).to have_css('th[scope="col"][aria-sort="none"]')
  end
end
