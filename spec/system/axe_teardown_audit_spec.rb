# frozen_string_literal: true

require "rails_helper"

# Self-test for the teardown audit's always-on machinery (#912). The audit
# itself runs after every system example; what this file proves is the two
# things the after(:suite) gate in spec/support/axe_accessibility.rb relies
# on: the audit detects a planted violation, and the gate's bookkeeping sees
# an example that navigated. The gate's own decision is a pure function,
# checked below without a browser.
RSpec.describe "AAA teardown audit", type: :system do
  it "catches a planted violation in both themes, and is clean again once it is gone" do
    visit root_path
    expect(axe_violations_in_both_themes).to be_empty

    page.execute_script(<<~JS)
      const img = document.createElement("img");
      img.id = "axe-probe";
      img.src = "data:image/gif;base64,R0lGODlhAQABAAAAACw=";
      document.body.appendChild(img);
    JS
    violations = axe_violations_in_both_themes
    expect(violations.grep(/image-alt/).size).to eq(2), violations.join("\n")

    page.execute_script("document.getElementById('axe-probe').remove()")
    expect(axe_violations_in_both_themes).to be_empty
  end

  it "records this example as having navigated, so the suite gate holds it to an audit" do
    visit root_path

    expect(AxeAccessibility::VISITED_EXAMPLES).to include(RSpec.current_example.id)
  end

  describe ".unaudited" do
    it "flags an example that navigated and has no :audited entry, whatever else the ledger says" do
      ledger  = { "a" => :audited, "b" => :blank, "c" => :blank }
      visited = Set["a", "b", "d"]

      expect(AxeAccessibility.unaudited(%w[a b c d], ledger: ledger, visited: visited)).to eq(%w[b d])
    end
  end
end
