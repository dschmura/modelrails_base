require "rails_helper"

# One validation path, and it is the server's (#1117).
#
# UI::FormBuilder already never emits native `required`, so a blank submit
# reaches the server and renders the error summary. But `email_field` renders
# `type="email"`, and a browser validates that type natively -- so a MALFORMED
# value was blocked with the browser's own transient bubble and never reached
# the server. The blank branch of a format validation was reachable and the
# malformed branch was not, in a real browser; request specs passed because
# they bypass the browser.
#
# A system spec, not a request spec, because the whole point is what a browser
# does before a request exists.
RSpec.describe "Form validation path", type: :system do
  let(:operator) { create(:user, :with_zero_workspaces).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in_via_form(operator) }

  it "sends a malformed email to the server, which answers with its own error summary" do
    visit new_operations_workspace_path

    fill_in I18n.t("operations.workspaces.new.name"), with: "New Co"
    fill_in I18n.t("operations.workspaces.new.owner_email"), with: "not-an-email"
    click_button I18n.t("operations.workspaces.new.submit")

    # The server's answer, not the browser's: the summary exists only in a
    # rendered 422, and aria-invalid is wired by the builder, not the browser.
    expect(page).to have_text(I18n.t("activerecord.errors.models.workspace.attributes.owner_email.invalid"))
    field = find_field(I18n.t("operations.workspaces.new.owner_email"), with: "not-an-email")
    expect(field["aria-invalid"]).to eq("true")
    expect(Workspace.find_by(name: "New Co")).to be_nil
  end
end
