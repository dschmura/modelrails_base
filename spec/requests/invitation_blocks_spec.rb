require "rails_helper"

RSpec.describe "Invitation blocks", type: :request do
  let(:invitation) { create(:invitation) }

  describe "POST /invitations/:token/block" do
    it "declines, blocks, and confirms without echoing addresses" do
      post block_invitation_path(token: invitation.token)

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(I18n.t("invitation_blocks.create.success"))
      expect(invitation.reload).to be_declined
      expect(InvitationBlock.exists?(inviter_id: invitation.invited_by_id,
                                     email: invitation.email)).to be(true)
    end

    it "shows the shared invalid message for a bad token" do
      post block_invitation_path(token: "nope")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_declines.invalid"))
    end

    it "refuses a magic-link invitation the same way" do
      bearer = create(:invitation, :magic_link)
      post block_invitation_path(token: bearer.token)
      expect(flash[:alert]).to eq(I18n.t("invitation_declines.invalid"))
      expect(InvitationBlock.count).to eq(0)
    end

    it "shows the shared invalid message when the invitation was already accepted" do
      invitation.accept!(create(:user))
      post block_invitation_path(token: invitation.token)
      expect(flash[:alert]).to eq(I18n.t("invitation_declines.invalid"))
      # already non-pending at the filter — no block is created from a dead link
    end

    it "keeps the block on the in-flight race (filter passes, decline! loses)" do
      # Two-instance shape at the HTTP boundary: accept between GET and POST is
      # covered above; here the filter sees pending but decline! meets accepted.
      # allow_any_instance_of is a named smell, justified here: no fixture
      # ordering at the HTTP boundary can produce this interleaving — the
      # model-level race is pinned with real rows elsewhere (T9).
      allow_any_instance_of(Invitation).to receive(:decline!)
        .and_raise(ActiveRecord::RecordInvalid.new(invitation))
      post block_invitation_path(token: invitation.token)

      expect(flash[:notice]).to eq(I18n.t("invitation_blocks.create.already_processed"))
      expect(InvitationBlock.exists?(inviter_id: invitation.invited_by_id,
                                     email: invitation.email)).to be(true)
    end

    it "rate limits via the cache counter (T18)" do
      allow(Rails.cache).to receive(:increment).and_return(11)
      post block_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.create.rate_limited"))
    end
  end
end
