# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dialog copyable artifact", type: :request do
  %w[basic with_form confirm_destructive dont_no_title].each do |scenario|
    it "renders the #{scenario} preview scenario" do
      get "/rails/view_components/ui/dialog_component/#{scenario}"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("dialog")).to be_present
    end
  end

  it "renders a complete, self-contained dialog (wrapper + trigger + dialog)" do
    get "/rails/view_components/ui/dialog_component/basic"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    wrapper = doc.at_css('[data-controller="modal"]')
    expect(wrapper).to be_present, "expected a data-controller=\"modal\" wrapper"

    trigger = wrapper.at_css("button")
    expect(trigger).to be_present, "expected a trigger button inside the modal wrapper"
    expect(trigger.text).to include("Open dialog")
    # the component wires the open action on the slot wrapper:
    expect(wrapper.at_css('[data-action*="modal#open"]')).to be_present

    dialog = wrapper.at_css('dialog[role="dialog"]')
    expect(dialog["aria-modal"]).to eq("true")
    expect(dialog["aria-labelledby"]).to be_present
  end
end
