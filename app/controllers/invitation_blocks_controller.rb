class InvitationBlocksController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to root_path, alert: t("invitation_blocks.create.rate_limited") }

  def create
    @invitation = find_valid_invitation
    return unless @invitation

    @invitation.decline_and_block!
    redirect_to root_path, notice: t("invitation_blocks.create.success")
  rescue ActiveRecord::RecordInvalid
    # Only the raced decline! reaches here — block! absorbs its own signals —
    # and the block IS saved, so the copy claims the block, not the decline
    # (the race includes "already accepted"; PR 4 spec §8.1).
    redirect_to root_path, notice: t("invitation_blocks.create.already_processed")
  end

  private

  # Duplicated from InvitationDeclinesController on purpose: second copy — the
  # house rule extracts at the third (standards/code-style.md). The magic_link?
  # refusal is this endpoint's own: nothing to block for. Absolute key: shared
  # failure message with the decline flow.
  def find_valid_invitation
    invitation = Invitation.find_by(token: params[:token])

    if invitation.nil? || !invitation.pending? || invitation.expired? || invitation.magic_link?
      redirect_to root_path, alert: t("invitation_declines.invalid")
      return nil
    end

    invitation
  end
end
