# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ViewComponent previews (test host)", type: :request do
  it "serves an existing component preview" do
    get "/rails/view_components/ui/button_component/primary"
    expect(response).to have_http_status(:ok)
  end
end
