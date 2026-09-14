# "This user operates the instance." Deliberately NOT a Membership and NOT a
# Role: memberships.workspace_id is null: false and Role(workspace_id: nil)
# already means "system default template", so neither can carry an
# instance-level grant without changing what it means (panel 2026-09-14).
class Operatorship < ApplicationRecord
  include Discardable

  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true

  # STRICT audit grade (Trackable's vocabulary): the audit row commits with the
  # grant or neither does. Operatorship is a credential, like a passkey.
  def self.grant!(user:, granted_by: nil)
    transaction do
      create!(user: user, granted_by: granted_by).tap do |operatorship|
        ActivityLog.create!(
          action: "operatorship.granted", actor: granted_by, trackable: user,
          workspace: nil, visibility: "admin", metadata: { operatorship_id: operatorship.id }
        )
      end
    end
  end

  def revoke!(revoked_by: nil)
    transaction do
      discard!
      ActivityLog.create!(
        action: "operatorship.revoked", actor: revoked_by, trackable: user,
        workspace: nil, visibility: "admin", metadata: { operatorship_id: id }
      )
    end
    true
  end
end
