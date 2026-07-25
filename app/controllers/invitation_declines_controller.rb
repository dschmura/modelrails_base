class InvitationDeclinesController < ApplicationController
  allow_unauthenticated_access

  def show
    @invitation = find_valid_invitation
    nil unless @invitation
  end

  def create
    @invitation = find_valid_invitation
    return unless @invitation

    @invitation.decline!
    redirect_to root_path, notice: t(".success")
  end

  private

  def find_valid_invitation
    invitation = Invitation.find_by(token: params[:token])

    # Controller-scoped key (invitation_declines.invalid) — shared by #show and
    # #create via lazy lookup's controller-scope fallback. See the note in
    # InvitationAcceptsController#find_valid_invitation.
    if invitation.nil? || !invitation.pending? || invitation.expired?
      redirect_to root_path, alert: t(".invalid")
      return nil
    end

    invitation
  end
end
