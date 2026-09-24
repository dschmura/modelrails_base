# frozen_string_literal: true

require "rails_helper"

# A Lexxy body is form-associated, so recover() restores it; only lexxy:change was
# missing as a save trigger (#479). Real forms, not the harness.
RSpec.describe "Form drafts on a Lexxy-backed resource form", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let(:title_label) { I18n.t("workspaces.projects.resources.new.title_label") }
  let(:draft_key) { "project_#{project.id}:new_resource:document" }

  before { sign_in_via_form(user) }

  def type_into_editor(text)
    find("lexxy-editor [contenteditable='true']").click
    page.driver.browser.keyboard.type(text)
  end

  def status_region
    find('[data-form-draft-target="status"]', visible: :all)
  end

  it "saves the rich text body and restores it into the editor" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Kickoff notes"
    type_into_editor("Agenda for the kickoff")

    wait_for_draft(draft_key)

    # ARMED TRIPWIRE: the body must be in the blob and unreadable.
    blob = page.evaluate_script(
      "localStorage.getItem(#{draft_storage_key(user, draft_key).to_json})"
    )
    expect(blob).to be_present
    expect(blob).not_to include("Agenda for the kickoff")

    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_text(I18n.t("form_draft.notice"))
    click_button I18n.t("form_draft.recover")

    expect(page).to have_field(title_label, with: "Kickoff notes")
    expect(page).to have_css("lexxy-editor [contenteditable='true']",
      text: "Agenda for the kickoff")
  end

  # Without data-form-draft-ignore the hidden type field makes every restore partial.
  it "announces a whole restore, not a partial one" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Kickoff notes"
    type_into_editor("Agenda for the kickoff")
    wait_for_draft(draft_key)

    visit new_workspace_project_resource_path(workspace, project)
    click_button I18n.t("form_draft.recover")

    # Exactly two: the toolbar's named <select> no longer counts (modelrails_ui#262).
    expect(status_region).to have_text(
      I18n.t("form_draft.restored_other", count: 2), wait: 3
    )
    expect(status_region).to have_no_text("could not be restored")
  end

  # The editor's own initialisation must not count as a change.
  it "offers nothing for a form the user never touched" do
    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_css("lexxy-editor [contenteditable='true']")

    sleep 1 # longer than the 300ms save debounce

    expect(page).to have_no_text(I18n.t("form_draft.notice"))
    expect(
      page.evaluate_script("Object.keys(localStorage).filter(k => k.startsWith('draft:')).length")
    ).to eq(0)
  end

  # The edit form reaches the same storage key by the form id instead.
  it "recovers a draft on the edit form" do
    resource = create(:resource, project: project, created_by: user, title: "Original title")

    visit edit_workspace_project_resource_path(workspace, project, resource)
    fill_in I18n.t("workspaces.projects.resources.edit.title_label"), with: "Revised title"
    type_into_editor("A second pass")
    wait_for_draft("resource_#{resource.id}")

    visit edit_workspace_project_resource_path(workspace, project, resource)
    click_button I18n.t("form_draft.recover")

    expect(page).to have_field(
      I18n.t("workspaces.projects.resources.edit.title_label"), with: "Revised title"
    )
    expect(page).to have_css("lexxy-editor [contenteditable='true']", text: "A second pass")
  end

  # Ends with the chip revealed, since axe's teardown audit reads the final DOM.
  it "shows the revealed notice accessibly on the resource form" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Axe state"
    wait_for_draft(draft_key)

    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_text(I18n.t("form_draft.notice"))
  end

  it "clears the draft once the document is created" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Kickoff notes"
    type_into_editor("Agenda for the kickoff")
    wait_for_draft(draft_key)

    click_button I18n.t("workspaces.projects.resources.new.submit")
    expect(page).to have_text(I18n.t("workspaces.projects.resources.create.success"))

    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_css("lexxy-editor [contenteditable='true']")
    expect(page).to have_no_text(I18n.t("form_draft.notice"))
  end
end
