# frozen_string_literal: true

require "rails_helper"

# The operations activity ledger in a real browser: the filter band applying
# into the results frame on change, the custom-range popover, the pivot out of
# a row's details, the rows-per-page control — each audited at WCAG 2.2 AAA in
# both themes.
#
# Every I18n.t call below passes no vocabulary noun keyword (workspace:,
# project:) — the backend injects %{workspace}/%{project}/etc itself, and a
# caller's literal would win over it and stop discriminating in a fork that
# renamed the noun. See /docs/developer/i18n (Vocabulary).
#
# :with_zero_workspaces keeps the operator out of the feed's own rows, so
# every assertion below is about the fixtures this file created.
RSpec.describe "Operations activity ledger", type: :system do
  let(:operator) { create(:user, :with_zero_workspaces).tap { |u| Operatorship.grant!(user: u) } }
  let!(:acme) { create(:workspace, name: "Acme Robotics") }
  let!(:beta) { create(:workspace, name: "Beta Works") }
  let!(:priya) { create(:user, first_name: "Priya", last_name: "Nair") }
  # A deterministic `membership.created` row — the positive control the kind
  # filter is measured against.
  let!(:priya_membership) { create(:membership, user: priya, workspace: acme) }

  before do
    acting_as(priya) { plan_named(acme, "Launch plan") }
    plan_named(beta, "Beta plan")
    sign_in_via_form(operator)
  end

  def within_results(&) = within("turbo-frame#activity_results", &)

  # A `project.created` row names nothing the page can show: Trackable writes
  # no metadata for a creation and the sentence is "created the <project>".
  # A RENAME does — its `changes` metadata carries the name, which the details
  # <dl> renders — so a plan is created and then renamed. Same handle the
  # request specs use (spec/requests/operations/activity_logs_filters_spec.rb).
  def plan_named(workspace, name)
    create(:project, workspace: workspace).update!(name: name)
  end

  # Acting AS someone is a session, not an assignment: Current.user delegates
  # to Current.session (spec/models/activity_log_filters_spec.rb's pattern).
  def acting_as(user)
    Current.session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    yield
  ensure
    Current.session = nil
  end

  # The rename row, addressed the way the page addresses it — workspace column
  # plus the sentence. The project's NAME cannot be the locator: it lives
  # inside the closed <details>, which is exactly what opening the row proves.
  def rename_row
    find("tbody tr", text: /Acme Robotics.*#{Regexp.escape(I18n.t("activity.actions.project.updated"))}/m)
  end

  # The combobox's text input carries neither id nor name — both land on the
  # wrapper <div> and on the hidden field — and this suite does not set
  # Capybara.enable_aria_label, so `fill_in` has no locator to reach it by.
  # Its accessible name is the `label:` the component puts on `aria-label`,
  # which is what this addresses it by (and therefore asserts).
  def workspace_combobox
    find("input[role=combobox][aria-label='#{I18n.t("operations.activity_logs.index.filters.workspace_label")}']")
  end

  it "renders the default window AAA-clean in both themes, with an open details row" do
    visit operations_activity_logs_path
    within_results { expect(page).to have_css("tbody tr", minimum: 2) }

    rename_row.find("summary").click

    # The rename's `changes` metadata — the one per-record handle the ledger
    # puts on the page, and proof the opened row is the one addressed above.
    expect(page).to have_css("details[open] dd", text: "Launch plan")
    expect(page).to have_css("details[open] dd",
      text: I18n.t("operations.activity_logs.index.details.only_person", email: priya.email_address))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "applies a select change inside the frame, advances the URL, keeps focus, and announces the count" do
    visit operations_activity_logs_path
    # Positive control: the sentence the kind filter must remove is on the
    # unfiltered page first, so its later absence measures the filter.
    within_results { expect(page).to have_text(I18n.t("activity.actions.membership.created")) }

    # Cuprite's `select` only DISPATCHES synthetic focus/blur events at the
    # <select> — it never moves document.activeElement, which stays on <body>.
    # A real pointer or Tab lands focus on the control before the change, so
    # this puts it there; otherwise the assertion below would measure the
    # driver (and navigation_focus.js's correct "focus is parked" fallback)
    # instead of the frame swap.
    cdp_execute("document.getElementById('kind').focus()")
    select I18n.t("activity.kinds.project"), from: "kind"

    within_results { expect(page).to have_css("h2", text: I18n.t("activity.kinds.project")) }
    expect(page).to have_current_path(/kind=project/)
    # The filter form sits OUTSIDE the frame precisely so the swap never takes
    # focus off the control that caused it.
    expect(page.evaluate_script("document.activeElement.id")).to eq("kind")
    expect(page).to have_css("#activity_results_status", text: I18n.t("activity.kinds.project"), visible: :all)
    within_results { expect(page).to have_no_text(I18n.t("activity.actions.membership.created")) }
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "narrows by workspace through the combobox without an Apply button" do
    visit operations_activity_logs_path
    # Every control applies on change; the only submit buttons on the page are
    # the range band's and the popover's, all of which carry name="range".
    expect(page).to have_no_css("form button[type=submit]:not([name=range])")
    within_results do
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_link("Beta Works")
    end

    workspace_combobox.click
    cdp_browser.keyboard.type("Acme")
    find("[role=option]", text: "Acme Robotics").click

    within_results do
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_no_text("Beta Works")
    end
    expect(page).to have_current_path(/workspace=#{Regexp.escape(acme.slug)}/)
  end

  it "switches the range with one click and accepts a custom range from the popover" do
    visit operations_activity_logs_path
    click_button I18n.t("operations.activity_logs.index.ranges.all")
    expect(page).to have_current_path(/range=all/)
    within_results { expect(page).to have_css("h2", text: I18n.t("operations.activity_logs.index.ranges.all")) }

    click_button I18n.t("operations.activity_logs.index.ranges.popover_label")
    fill_in "from", with: "2026-09-03"
    fill_in "to", with: Date.current.iso8601
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    click_button I18n.t("operations.activity_logs.index.ranges.use")
    expect(page).to have_current_path(/range=custom/)
    expect(page).to have_current_path(/from=2026-09-03/)
  end

  it "pivots into one person from a row's details and shows the empty state when nothing matches" do
    visit operations_activity_logs_path
    within_results { expect(page).to have_link("Beta Works") }

    rename_row.find("summary").click
    within("details[open]") do
      click_link I18n.t("operations.activity_logs.index.details.only_person", email: priya.email_address)
    end

    within_results do
      expect(page).to have_link("Acme Robotics")
      expect(page).to have_no_text("Beta Works")
    end
    expect(page).to have_current_path(/person=#{Regexp.escape(CGI.escape(priya.email_address))}/)

    visit operations_activity_logs_path(person: "nobody@example.com")
    within_results { expect(page).to have_text(I18n.t("operations.activity_logs.index.empty")) }
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "changes rows per page from the footer" do
    visit operations_activity_logs_path
    within_results { click_link "25" }
    expect(page).to have_current_path(/rows=25/)
    within_results { expect(page).to have_css("nav a[aria-current='true']", text: "25") }
  end
end
