class InvitationBlock < ApplicationRecord
  belongs_to :inviter, class_name: "User"
  encrypts :email, deterministic: true, downcase: true
end
