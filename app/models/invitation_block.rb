# "Invitations from inviter I to address E are not delivered." Email-keyed and
# account-independent: works for a decliner with no account, survives the address
# becoming a user, does not follow a user who changes address (PR 4 spec §2).
class InvitationBlock < ApplicationRecord
  belongs_to :inviter, class_name: "User"

  # Deliberately NOT Tenanted: an inviter-to-address relationship spans every
  # workspace the inviter can invite from (PR 4 spec §5).
  # Deliberately NOT Trackable: any activity row the inviter could read is a
  # block oracle (invariant I3); the system's record of a block is the block.
  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) }
  encrypts :email, deterministic: true, downcase: true
  validates :email, presence: true, format: { with: User::EMAIL_FORMAT },
            uniqueness: { scope: :inviter_id }
end
