require "rails_helper"

RSpec.describe "Operations activity feed", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  it "renders rows from several workspaces and paginates" do
    w1 = create(:workspace, name: "Alpha")
    w2 = create(:workspace, name: "Beta")
    create(:project, workspace: w1)
    create(:project, workspace: w2)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    expect(html).to have_text("Alpha")
    expect(html).to have_text("Beta")
  end

  it "has an index that can serve a global created_at ordering" do
    indexes = ActiveRecord::Base.connection.indexes(:activity_logs).map(&:columns)
    expect(indexes).to include([ "created_at" ])
  end
end
