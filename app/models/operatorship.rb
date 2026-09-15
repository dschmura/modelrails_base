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

  # Idempotent: Discardable#discard! has no already-discarded guard, so a bare
  # call would push discarded_at forward and duplicate the audit row on a
  # second revoke! (double-submit, or two operators racing the same person) —
  # corrupting the one thing this credential-grade trail exists to get right.
  def revoke!(revoked_by: nil)
    return false if discarded?

    transaction do
      discard!
      ActivityLog.create!(
        action: "operatorship.revoked", actor: revoked_by, trackable: user,
        workspace: nil, visibility: "admin", metadata: { operatorship_id: id }
      )
    end
    true
  end

  # Guards, atomically: the last kept operatorship can't be revoked (`lock!`
  # before the count avoids a two-operators-race TOCTOU), and an operator can
  # never revoke their own row through here — checked in that order, so a
  # sole operator revoking themselves gets the more useful :last_operator
  # refusal instead of a generic self-revoke one. Returns which case fired,
  # not a boolean: a caller has to tell "already revoked" apart from "last
  # one" to avoid reporting a refusal for a rule that didn't apply. See
  # app/docs/developer/operations.md (How it stays safe) and
  # /docs/developer/architecture (Concurrency).
  def revoke_unless_last!(revoked_by: nil)
    transaction do
      lock!
      next :already_revoked if discarded?
      next :last_operator if Operatorship.kept.count <= 1
      next :self_revoke if revoked_by == user

      revoke!(revoked_by: revoked_by)
      :revoked
    end
  end
end
