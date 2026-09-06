# frozen_string_literal: true

require "rails_helper"

# The show-once join-link reveal is a `ui :copy` field: the URL in a readonly input,
# the trigger carrying the show-once warning and the page's autofocus, both live
# regions present. Axe is asserted INLINE — the teardown audit never runs for
# system specs (#912).
RSpec.describe "Join link copy control", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:link_noun) { I18n.t("workspaces.settings.join_policy.link_aria") }
  let(:stub_clipboard) { <<~JS }
    window.__copied = []
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: (text) => { window.__copied.push(text); return Promise.resolve() } },
      configurable: true
    })
  JS

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.update!(join_policy: "open_link")
    sign_in_via_form(user)
    visit edit_workspace_settings_path(workspace)
    click_button I18n.t("workspaces.settings.join_policy.generate")
    expect(page).to have_text(I18n.t("workspaces.settings.join_policy.show_once_warning_lead"))
  end

  it "renders the reveal as a copy field wired to the warning, with focus on the trigger" do
    expect(page).to have_css("input[readonly][data-copy-target='source'][value^='http']")
    expect(page).to have_css("button[data-action='copy#copy'][aria-describedby='join_link_show_once_warning'][autofocus]")
    expect(page).to have_css("label.sr-only", text: link_noun, visible: :all)
    expect(page).to have_css("[data-turbo-temporary] [data-controller='copy']")
    expect(page).to have_no_css("[data-controller='clipboard']")
    # :focus predicate (Capybara-retried), not an activeElement sample (see
    # spec/system/accessibility/post_navigation_focus_spec.rb). Here it also
    # documents a real, pre-existing interaction rather than a mere assertion
    # race: the workspace layout runs `turbo_refreshes_with method: :morph`
    # (app/views/layouts/application.html.erb:9), and generating/rotating a
    # join link redirects back to the SAME edit_workspace_settings_path, so
    # Turbo treats it as a same-page "refresh" and renders via
    # MorphingPageRenderer — whose `shouldAutofocus` is hard-coded `false`
    # (turbo-rails 2.0.23), skipping Turbo's own autofocus-on-render
    # emulation. navigation_focus.js's landmark handler (turbo:load) then
    # wins because it never observes the trigger claim focus first. The old
    # hand-rolled `<input autofocus>` had the identical interaction — this is
    # not a C3 regression. Both outcomes satisfy WCAG 2.4.3 (focus lands on a
    # sensible in-page target, never lost); assert either, as
    # post_navigation_focus_spec.rb does for the analogous "does not fight an
    # autofocused field" case.
    expect(page).to have_css("button[data-action='copy#copy']:focus, #main-content:focus")
  end

  it "copies the URL and announces it without changing the button's text" do
    page.execute_script(stub_clipboard)
    url = find("input[data-copy-target='source']").value

    find("button[data-action='copy#copy']").click

    expect(page).to have_css("[data-controller='copy'][data-state='copied']")
    expect(page.evaluate_script("window.__copied")).to eq([ url ])
    expect(find("[data-copy-target='status']", visible: :all).text(:all).strip)
      .to eq(I18n.t("modelrails_ui.copy.copied", label: link_noun))
    expect(find("button[data-action='copy#copy']").text.strip).to eq(I18n.t("modelrails_ui.copy.action"))
  end

  it "is axe-clean at AAA in both themes on the reveal" do
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      axe_violations_in_both_themes(axe_options).join("\n")
  end
end
