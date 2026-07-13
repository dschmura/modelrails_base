require "rails_helper"

RSpec.describe "Form draft round trip", type: :system do
  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  it "saves an encrypted draft, offers recovery, and restores every archetype" do
    visit "/draft_harness"

    fill_in "Title", with: "Drafted title"
    fill_in "Notes", with: "Long notes"
    check "Published"
    check "Ruby"
    check "Hotwire"
    choose "High"
    select "alpha", from: "Categories"
    select "gamma", from: "Categories"
    fill_in "Secret", with: "do-not-save"
    fill_in "Password", with: "never-save"

    # ARMED TRIPWIRE (panel finding): a dark feature (no key, no subtle
    # crypto) passes every negative assertion — prove the blob exists.
    wait_for_draft("harness-main")
    blob = page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json})")
    expect(blob).to be_present
    expect(blob).not_to include("Drafted title") # actually encrypted

    visit "/draft_harness" # leave + return (revisit re-renders clean form)
    within("#harness-main") do
      expect(page).to have_text(I18n.t("form_draft.notice"))
      click_button I18n.t("form_draft.recover")
      # Retrying barrier: recover() is async — let it finish before the
      # non-retrying find_field reads below.
      expect(page).to have_field("Title", with: "Drafted title")
      expect(find_field("Title").value).to eq("Drafted title")
      expect(find_field("Notes").value).to eq("Long notes")
      expect(find_field("Published")).to be_checked
      expect(find_field("Ruby")).to be_checked
      expect(find_field("Hotwire")).to be_checked
      expect(find_field("Rails")).not_to be_checked
      expect(find_field("High")).to be_checked
      expect(page).to have_select("Categories", selected: %w[alpha gamma])
      expect(find_field("Secret").value).to be_blank    # data-form-draft-ignore
      expect(find_field("Password").value).to be_blank  # passwords never saved
    end

    within("#harness-main") do
      expect(find('[data-form-draft-target="status"]', visible: :all, text: "Draft restored")).to be_present
    end
    expect(page).to have_selector("#harness-main input:focus, #harness-main textarea:focus")
  end

  it "flushes immediately on navigation (no 300ms data-loss window)" do
    visit "/draft_harness"
    fill_in "Title", with: "Typed then navigated"
    visit "/draft_harness" # turbo:before-visit must flush the pending save
    within("#harness-main") { expect(page).to have_text(I18n.t("form_draft.notice")) }
  end

  it "dispatches input/change on recovered fields (sibling resync contract)" do
    visit "/draft_harness"
    fill_in "Title", with: "Events"
    wait_for_draft("harness-main")
    visit "/draft_harness"
    page.execute_script(<<~JS)
      window.eventLog = [];
      document.querySelector("#harness-main [name='draft[title]']")
        .addEventListener("change", () => window.eventLog.push("change"));
    JS
    within("#harness-main") { click_button I18n.t("form_draft.recover") }
    expect(page.evaluate_script("window.eventLog")).to include("change")
  end

  it "discards on request and announces it" do
    visit "/draft_harness"
    fill_in "Title", with: "Discard me"
    wait_for_draft("harness-main")
    visit "/draft_harness"
    within("#harness-main") { click_button I18n.t("form_draft.discard") }
    expect(page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json}) === null")).to be(true)
    within("#harness-main") do
      expect(find('[data-form-draft-target="status"]', visible: :all, text: I18n.t("form_draft.discarded"))).to be_present
    end
    expect(page).to have_selector("#harness-main [data-form-draft-target='notice']", visible: :hidden)
  end

  # Axe teardown audits the FINAL DOM (CI-only AAA): end revealed.
  it "shows the revealed notice accessibly" do
    visit "/draft_harness"
    fill_in "Title", with: "Axe state"
    wait_for_draft("harness-main")
    visit "/draft_harness"
    within("#harness-main") { expect(page).to have_text(I18n.t("form_draft.notice")) }
    # example intentionally ends with the chip visible for the axe sweep
  end
end
