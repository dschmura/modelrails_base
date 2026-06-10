# frozen_string_literal: true

require "rails_helper"

# Smoke test: the interactive playgrounds render without error in the preview host.
# Playgrounds render inline via @param-driven methods, so the gem's template-backed
# test excludes them — this is their only automated coverage. Guards the new
# playgrounds (sheet/device_mockup/stepper) and the two-axis refresh (button/badge:
# their default `cell` must be a proven variant/tone pair, not a fail-loud raise).
RSpec.describe "Component playgrounds render", type: :system do
  def visit_playground(component)
    visit "/rails/view_components/ui/#{component}_component/playground"
  end

  it "button playground renders a proven cell" do
    visit_playground("button")
    expect(page).to have_button("Button")
  end

  it "badge playground renders a proven cell" do
    visit_playground("badge")
    expect(page).to have_text("Badge")
  end

  it "stepper playground renders" do
    visit_playground("stepper")
    expect(page).to have_css("ol[aria-label]", visible: :all)
  end

  it "sheet playground renders" do
    visit_playground("sheet")
    expect(page).to have_css("dialog", visible: :all)
  end

  it "device_mockup playground renders" do
    visit_playground("device_mockup")
    expect(page).to have_text("Screen content")
  end
end
