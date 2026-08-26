require "rails_helper"

# `sign_in_via_form` is the setup funnel for 58 system spec files, so a defect
# in it fails an arbitrary spec that has nothing to do with authentication —
# which is how #846 surfaced, in a docs-mode-persistence spec.
#
# The defect was two writers to one slot. `MagicLinkToken.create_for_email`
# supersedes every prior unconsumed token for an address (a partial unique
# index enforces one), and the helper drove the app into minting one and then
# minted a second itself. Whenever the app's mint landed after the test's, the
# token the test was about to click was already dead — and because the session
# had begun, the callback's rejection redirected to root_path, producing the
# signed-in homepage carrying "invalid or has expired" that CI reported.
#
# This pins the property that makes that impossible rather than the symptom:
# ONE mint per sign-in. A returning form-POST prelude fails here, loudly, in a
# spec named for the contract — not intermittently, three days later, in
# somebody else's file.
RSpec.describe "sign_in_via_form contract", type: :system do
  let(:user) { create(:user) }

  it "mints exactly one magic-link token, so nothing can supersede it mid-flow" do
    expect { sign_in_via_form(user) }
      .to change { MagicLinkToken.where(email: user.email_address).count }.by(1)
  end

  it "leaves that token consumed, so it cannot be replayed" do
    sign_in_via_form(user)

    tokens = MagicLinkToken.where(email: user.email_address)
    expect(tokens.count).to eq(1)
    expect(tokens.first.consumed_at).to be_present
  end
end
