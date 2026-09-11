require "rails_helper"

# The one backend customization in the app. Behavior is asserted against the
# real backend and real keys, not a stub: the failure modes this guards were
# found in a spike (the gem skips interpolation on value-less calls; a
# vocabulary that fills a caller's forgotten argument masks a bug).
RSpec.describe "Vocabulary interpolation", type: :config do
  before do
    I18n.backend.store_translations(:en, vocab_probe: {
      bare: "%{Workspace} not found.",
      mixed: "Join %{workspace_name}, your new %{workspace}.",
      counted: { one: "%{count} %{project}", other: "%{count} %{projects}" },
      plain: "No tokens here."
    })
  end

  after { I18n.backend.reload! }

  it "fills vocabulary tokens when the caller passes no values" do
    expect(I18n.t("vocab_probe.bare")).to eq("Workspace not found.")
  end

  it "fills them alongside the caller's own arguments" do
    expect(I18n.t("vocab_probe.mixed", workspace_name: "COMP 4999")).to eq("Join COMP 4999, your new workspace.")
  end

  it "fills them on every pluralization branch" do
    expect(I18n.t("vocab_probe.counted", count: 1)).to eq("1 project")
    expect(I18n.t("vocab_probe.counted", count: 3)).to eq("3 projects")
  end

  it "still raises when the caller forgets a name argument" do
    expect { I18n.t("vocab_probe.mixed") }.to raise_error(I18n::MissingInterpolationArgument, /workspace_name/)
  end

  it "lets a caller override a vocabulary token for one call" do
    expect(I18n.t("vocab_probe.bare", Workspace: "Cohort")).to eq("Cohort not found.")
  end

  it "reaches the view helper path" do
    expect(ApplicationController.helpers.t("vocab_probe.bare")).to eq("Workspace not found.")
  end

  it "leaves a token-free string alone" do
    expect(I18n.t("vocab_probe.plain")).to eq("No tokens here.")
  end
end
