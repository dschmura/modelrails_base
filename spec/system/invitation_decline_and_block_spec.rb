require "rails_helper"

RSpec.describe "Invitation decline and block", type: :system do
  let(:inviter) { create(:user) }
  let(:invitation) { create(:invitation, invited_by: inviter) }

  it "opens the block dialog with the consequence as its description — and leaves it open for the axe audit (T21a)" do
    visit decline_invitation_path(token: invitation.token)

    # The non-client half of the copy branch T28 pins; without it, swapping the
    # two branches leaves only T28 red.
    expect(page).to have_content(
      I18n.t("invitation_declines.show.body",
             workspace: invitation.invitable.name, inviter: inviter.email_address)
    )
    expect(page).to have_button(
      I18n.t("invitation_declines.show.block_trigger", inviter: inviter.email_address)
    )
    click_button I18n.t("invitation_declines.show.block_trigger", inviter: inviter.email_address)

    expect(page).to have_css("dialog[open][aria-describedby]")
    described = page.find("dialog[open]")["aria-describedby"]
    expect(page.find(id: described).text).to include(
      I18n.t("invitation_declines.show.block_message",
             inviter: inviter.email_address, email: invitation.email)
    )
    # The dialog deliberately stays OPEN to the end (PR 4 spec §9 / T21), and
    # the AAA gate is asserted HERE: the suite's teardown audit never sees this
    # state, because `spec/support/capybara.rb` registers `reset_sessions!`
    # after the axe hook, so it runs first and the audit bails on about:blank.
    expect(axe_violations_in_both_themes).to be_empty
  end

  it "returns focus to the trigger on Escape (T21b)" do
    visit decline_invitation_path(token: invitation.token)
    trigger_text = I18n.t("invitation_declines.show.block_trigger", inviter: inviter.email_address)
    click_button trigger_text
    expect(page).to have_css("dialog[open]")

    cdp_press("Escape")
    expect(page).to have_no_css("dialog[open]")
    expect(page.evaluate_script("document.activeElement.textContent").strip).to eq(trigger_text)
  end

  # Scoped: `with_viewport`'s ensure restores the suite default, so a leaked
  # narrow viewport can't reframe later specs in this parallel worker. The axe
  # assertion lives INSIDE the block for the same reason — the suite-wide hook
  # runs after the restore and would audit the desktop DOM, leaving the 320px
  # state the one unaudited page state here.
  it "reflows at 320px with no horizontal scroll (T21c)", skip_axe_hook: true do
    with_viewport(320, 800) do
      visit decline_invitation_path(token: invitation.token)
      expect(page.evaluate_script(
        "document.documentElement.scrollWidth <= document.documentElement.clientWidth"
      )).to be(true)
      expect(axe_violations_in_both_themes).to be_empty
    end
  end

  it "confirming posts the block (T21d)" do
    visit decline_invitation_path(token: invitation.token)
    click_button I18n.t("invitation_declines.show.block_trigger", inviter: inviter.email_address)
    within("dialog[open]") do
      click_button I18n.t("invitation_declines.show.block_confirm")
    end
    expect(page).to have_content(I18n.t("invitation_blocks.create.success"))
    expect(invitation.reload).to be_declined
  end

  it "offers no block affordance on a magic-link invitation (anchored absence)" do
    bearer = create(:invitation, :magic_link, invited_by: inviter)
    visit decline_invitation_path(token: bearer.token)
    expect(page).to have_button(I18n.t("invitation_declines.show.confirm")) # positive anchor
    expect(page).to have_no_css("[data-controller='modal']")
  end

  it "renders the client branch — project and inviter, no workspace mislabel (T28)" do
    project = create(:project, clientside_enabled: true)
    client_invitation = create(:invitation, :client, invitable: project,
                               invited_by: inviter, email: "dana@bigco.com")
    visit decline_invitation_path(token: client_invitation.token)

    expect(page).to have_content(
      I18n.t("invitation_declines.show.client_body",
             inviter: inviter.email_address, project: project.name)
    )
    expect(page).to have_button(
      I18n.t("invitation_declines.show.block_trigger", inviter: inviter.email_address)
    )
    # Closed-state counterpart to T21a's audit, for the same reason.
    expect(axe_violations_in_both_themes).to be_empty
  end
end
