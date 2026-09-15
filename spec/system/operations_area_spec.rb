# frozen_string_literal: true

require "rails_helper"

# The WCAG 2.2 AAA gate over the whole instance-operations area, both themes.
#
# C1 (task-16 ledger correction): never pass a literal noun as a vocabulary
# interpolation — `I18n.t(key, workspace: "workspace")` would WIN over the
# backend's own injection (config/initializers/vocabulary.rb merges the
# caller's options over Vocabulary.tokens) and silently stop discriminating
# in a fork that renamed the noun. Every I18n.t call below passes no noun
# keyword and lets the backend supply %{workspace}/%{workspaces}/etc.
#
# The operator is built with :with_zero_workspaces so the operations area's
# own workspace list starts genuinely empty — the default trait onboards a
# personal workspace, which would make "no workspaces yet" unreachable.
RSpec.describe "Operations area", type: :system do
  let(:operator) { create(:user, :with_zero_workspaces).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in_via_form(operator) }

  it "lists workspaces, empty then populated, with the area banner, AAA in both themes" do
    visit operations_workspaces_path
    expect(page).to have_text(I18n.t("operations.area.banner"))
    expect(page).to have_text(I18n.t("operations.workspaces.index.empty"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    owner = create(:user, first_name: "Olive", last_name: "Owner")
    workspace = create(:workspace, name: "Acme Robotics")
    create(:membership, :owner, user: owner, workspace: workspace)

    visit operations_workspaces_path
    expect(page).to have_text("Acme Robotics")
    expect(page).to have_text("Olive Owner")
    expect(page).to have_text(I18n.t("lifecycle_status.active"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Covers both lock states so the lock control AND the unlock control are
  # each audited (C2/C3), plus the status badge's rendered aria-label (C4b).
  # No `click_link` from the index here: operations/workspaces/_row.html.erb
  # renders the workspace name as plain text, not a link — there is no
  # in-app path from the list to a workspace's show page today. Visiting the
  # show route directly is the only way in; not an axe finding (nothing is a
  # broken link, there's simply no link), so left as-is and reported.
  it "shows a workspace, locks and unlocks it, auditing both states and the status badge, AAA in both themes" do
    owner = create(:user, first_name: "Olive", last_name: "Owner")
    workspace = create(:workspace, name: "Acme Robotics")
    create(:membership, :owner, user: owner, workspace: workspace)

    visit operations_workspace_path(workspace)
    expect(page).to have_text(owner.full_name)
    expect(page).to have_css(
      "[aria-label='#{I18n.t('operations.workspaces.show.status_prefix')}: #{I18n.t('lifecycle_status.active')}']"
    )
    expect(page).to have_button(I18n.t("operations.workspaces.show.suspend"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Lock control: button_to with data-turbo-confirm on the form (C5).
    accept_confirm { click_button I18n.t("operations.workspaces.show.suspend") }
    expect(page).to have_text(I18n.t("operations.workspaces.suspensions.create.success"))
    expect(workspace.reload).to be_suspended
    expect(page).to have_css(
      "[aria-label='#{I18n.t('operations.workspaces.show.status_prefix')}: #{I18n.t('lifecycle_status.suspended')}']"
    )
    expect(page).to have_button(I18n.t("operations.workspaces.show.unsuspend"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Unlock control: no confirm on this form (view has no data-turbo-confirm
    # on the unsuspend button_to), so a plain click_button is correct here.
    click_button I18n.t("operations.workspaces.show.unsuspend")
    expect(page).to have_text(I18n.t("operations.workspaces.suspensions.destroy.success"))
    expect(workspace.reload).not_to be_suspended
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "looks up users by email — no query, a match, and no match, AAA in both themes" do
    target = create(:user, email_address: "target@example.com", first_name: "Tess", last_name: "Target")

    visit operations_users_path
    expect(page).to have_no_text(target.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    fill_in I18n.t("operations.users.index.search_label"), with: target.email_address
    click_button I18n.t("operations.users.index.search")
    expect(page).to have_link(target.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    fill_in I18n.t("operations.users.index.search_label"), with: "nobody@example.com"
    click_button I18n.t("operations.users.index.search")
    expect(page).to have_text(I18n.t("operations.users.index.no_match"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Covers the Unlock button (locked-account branch) and the Suspend-access
  # button (C2/C3) — neither had ever been through the axe gate before this
  # arc's Tasks 13-14. The target's own onboarding membership supplies a
  # non-empty memberships list for free.
  it "shows a locked user and audits the Unlock and Suspend-access controls, AAA in both themes" do
    target = create(:user, first_name: "Tess", last_name: "Target")
    5.times { target.register_failed_login! }

    visit operations_user_path(target)
    locked_dd = page.find(:xpath,
      "//dt[normalize-space(text())='#{I18n.t('operations.users.show.locked')}']/following-sibling::dd[1]")
    expect(locked_dd.text).to eq(I18n.t("operations.affirmative"))
    expect(page).to have_button(I18n.t("operations.users.show.unlock"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Unlock control: no confirm on this form.
    click_button I18n.t("operations.users.show.unlock")
    expect(page).to have_text(I18n.t("operations.users.locks.destroy.success"))
    expect(target.reload).not_to be_locked
    expect(page).to have_no_button(I18n.t("operations.users.show.unlock"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Suspend-access control: button_to with data-turbo-confirm on the form.
    accept_confirm { click_button I18n.t("operations.users.show.suspend") }
    expect(page).to have_text(I18n.t("operations.users.suspensions.create.success"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Covers the grant form and the revoke button (C2/C3) — neither had ever
  # been through the axe gate before this arc's Tasks 13-14.
  it "grants and revokes an operator from the roster, AAA in both themes" do
    grantee = create(:user, first_name: "Sam", last_name: "Second")

    visit operations_operatorships_path
    expect(page).to have_text(operator.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    fill_in I18n.t("operations.operatorships.index.grant_label"), with: grantee.email_address
    click_button I18n.t("operations.operatorships.index.grant")
    expect(page).to have_text(I18n.t("operations.operatorships.create.success"))
    expect(grantee.reload).to be_operator
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Revoke control: button_to with data-turbo-confirm on the form (C5).
    # Two identically-labelled "Revoke" buttons now exist on the roster, so
    # the click is scoped to the grantee's own row to disambiguate.
    within("li", text: grantee.full_name) do
      accept_confirm { click_button I18n.t("operations.operatorships.index.revoke") }
    end
    expect(page).to have_text(I18n.t("operations.operatorships.destroy.success"))
    expect(grantee.reload).not_to be_operator
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # The paginated state has never been audited (no example has ever crossed a
  # page boundary on this feed with an axe assertion attached). 25 distinct
  # workspaces mirrors spec/requests/operations/activity_logs_spec.rb's own
  # pagination example — each plain `create(:workspace, ...)` writes one
  # workspace-visible "workspace.created" row, crossing Pagy's 20-item limit.
  it "shows the cross-workspace activity feed, including its paginated state, AAA in both themes" do
    25.times { |i| create(:workspace, name: format("WS %02d", i)) }

    visit operations_activity_logs_path
    expect(page).to have_css("nav.series-nav")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    click_link "2"
    expect(page).to have_css('[aria-current="page"]', text: "2")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "creates a workspace via the form, clean and its 422 error state, AAA in both themes" do
    visit new_operations_workspace_path
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # A malformed email is blocked client-side by the native `type="email"`
    # input before it ever reaches the server (#1117, filed not fixed here);
    # a BLANK one is not, since the builder strips `required` — this is the
    # only way a real browser reaches the server-rendered 422.
    fill_in I18n.t("operations.workspaces.new.name"), with: "New Co"
    click_button I18n.t("operations.workspaces.new.submit")
    expect(page).to have_text(I18n.t("activerecord.errors.models.workspace.attributes.owner_email.invalid"))
    expect(Workspace.find_by(name: "New Co")).to be_nil
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end
end
