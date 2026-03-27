require "rails_helper"

RSpec.describe "Documentation", type: :request do
  it "GET /docs renders successfully" do
    get "/docs"
    expect(response).to have_http_status(:ok)
  end
end
