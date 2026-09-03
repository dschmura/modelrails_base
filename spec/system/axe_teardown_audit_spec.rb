# frozen_string_literal: true

require "rails_helper"

# Self-test for the teardown audit's always-on machinery (#912). The audit
# itself runs after every system example; what this file proves is the two
# things the after(:suite) gate in spec/support/axe_accessibility.rb relies
# on: the audit detects a planted violation, and the gate's bookkeeping sees
# an example that navigated. The gate's decision itself is a pure function,
# covered in spec/lib/axe_teardown_gate_spec.rb.
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

  # Turbo marks <html aria-busy="true"> for the length of a visit; the teardown
  # audit waits it out rather than auditing a page mid-render.
  it "waits for an in-flight Turbo visit to settle before auditing" do
    visit root_path
    page.execute_script(<<~JS)
      document.documentElement.setAttribute("aria-busy", "true");
      setTimeout(() => document.documentElement.removeAttribute("aria-busy"), 400);
    JS

    expect(wait_for_turbo_visit_to_settle).to be(true)
    expect(page.evaluate_script("document.documentElement.hasAttribute('aria-busy')")).to be(false)
  end

  it "gives up on a visit that never settles and lets the audit report it" do
    visit root_path
    page.execute_script("document.documentElement.setAttribute('aria-busy', 'true')")

    expect(wait_for_turbo_visit_to_settle(wait: 0.3)).to be(false)
    expect(axe_violations_in_both_themes.grep(/aria-allowed-attr/)).not_to be_empty

    page.execute_script("document.documentElement.removeAttribute('aria-busy')")
  end
end
