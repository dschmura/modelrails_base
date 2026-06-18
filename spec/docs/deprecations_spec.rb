# frozen_string_literal: true

require "rails_helper"

# Guards docs/deprecations.md for the things the team agreed to track:
#
# 1. The known call-sites where `Workspace#personal?` leaks into presentation —
#    so future contributors can find them without grepping.
# 2. A "removal trigger" phrase — ensures the doc answers "when should we act?"
#    rather than just describing debt.
#
# This spec intentionally tests *content shape*, not wording, so minor prose
# edits don't break CI. Add a new assertion only when the team commits to
# tracking a new invariant in the doc.
RSpec.describe "docs/deprecations.md", type: :model do
  let(:doc_path) { Rails.root.join("docs/deprecations.md") }
  let(:content)  { doc_path.read }

  it "exists" do
    expect(doc_path).to exist
  end

  # The two active presentation-layer call-sites listed in the doc must remain
  # findable so contributors know exactly where to look when the removal
  # trigger fires. We match on the helper/file name, not the full line.
  # Note: _settings_sidebar_switcher was removed from both sidebars in
  # Phase 2c-1 Tasks 2+3 (header switcher supersedes it) — no longer tracked here.
  it "mentions settings_context_kind (settings_navigation_helper debt call-site)" do
    expect(content).to include("settings_context_kind")
  end

  it "mentions workspace_icon_for (workspace_helper debt call-site)" do
    expect(content).to include("workspace_icon_for")
  end

  # The doc must name a removal trigger so the debt is time-boxed to a
  # real event rather than left open-ended.
  it "contains a removal trigger phrase" do
    expect(content).to match(/removal trigger/i)
  end
end
