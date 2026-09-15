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

  # Fix round 1, item 1: the panel's last-operator guard used to be a bare
  # `Operatorship.kept.count <= 1` read in the controller, outside any
  # transaction — two operators revoking two DIFFERENT rows could both pass
  # that read and leave zero. Same shape as Membership#reactivate!'s guard
  # (/docs/developer/architecture, Concurrency): BEGIN IMMEDIATE takes the
  # writer lock before the transaction's first read, so `lock!` (forcing a
  # fresh re-read) + the count check here are genuine check-then-act, not a
  # TOCTOU window. `rails operators:revoke` (break-glass) keeps calling plain
  # `revoke!`, not this, so it can still remove the last operator.
  # Returns which of the three things happened, not a boolean: "already
  # revoked" and "this is the last one" are different answers, and a caller
  # that cannot tell them apart reports a refusal for a rule that did not
  # apply. lock! before the count is what makes the guard atomic — see
  # /docs/developer/architecture (Concurrency).
  # :self_revoke, not a silent allow: an operator revoking their own
  # operatorship would redirect straight into require_operator's 404, the
  # success flash never rendered. Checked AFTER :last_operator, not before —
  # require_operator means the sole kept operator revoking themselves is the
  # only way :last_operator is ever reachable, and that refusal's
  # break-glass advice is the true and actionable one; "ask another
  # operator" would be advice for an operator who doesn't exist.
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
