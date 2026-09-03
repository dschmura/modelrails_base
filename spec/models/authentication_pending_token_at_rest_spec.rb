# frozen_string_literal: true

require "rails_helper"

# #953: the parked invitation token (unverified-email OAuth signup) is the same
# bearer credential as invitations.token and was the second plaintext copy.
RSpec.describe Authentication, "pending invitation token at rest" do
  let(:invitation) { create(:invitation) }
  let(:authentication) { create(:authentication, pending_invitation_token: invitation.token) }

  it "is declared encrypted, deterministically" do
    expect(Authentication.encrypted_attributes).to include(:pending_invitation_token)
  end

  it "stores ciphertext and reads back the plaintext" do
    raw = Authentication.connection.select_value(
      Authentication.sanitize_sql([ "SELECT pending_invitation_token FROM authentications WHERE id = ?", authentication.id ])
    )

    expect(raw).not_to eq(invitation.token)
    expect(authentication.reload.pending_invitation_token).to eq(invitation.token)
  end
end
