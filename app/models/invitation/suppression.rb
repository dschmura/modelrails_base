# frozen_string_literal: true

# Delivery suppression for invitations whose invitee has blocked the inviter.
# First split of Invitation, per #915: the cohesive cluster PR 4 of the
# notifications arc added, moved here unchanged (comments travelled with the
# methods) when #951's block-confirmation token would have pushed the class
# over its length ratchet.
module Invitation::Suppression
  extend ActiveSupport::Concern

  included do
    scope :unsuppressed, -> { where(suppressed_at: nil) }
  end

  def blocked_by_invitee?
    has_invitee? && InvitationBlock.exists?(inviter_id: invited_by_id, email: email)
  end

  def deliverable? = has_invitee? && !blocked_by_invitee?

  def suppressed? = suppressed_at.present?

  # One suppressed mailer-delivery attempt: stamp (idempotent, collision-safe),
  # then record. Unexpected errors propagate BEFORE any audit row — the mailer
  # job retries and re-enters the guard (PR 4 spec §6.3).
  def suppress_delivery!(mailer_action:)
    stamp_suppression
    record_suppressed_delivery(mailer_action)
  end

  private

  # Callback-free on purpose: Trackable#track_update would publish this stamp
  # into the workspace activity feed as "Invitation updated" — a block oracle
  # (PR 4 spec §3, Departure 1 / invariant I4).
  def stamp_suppression
    update_column(:suppressed_at, Time.current) unless suppressed?
  rescue ActiveRecord::RecordNotUnique
    # A sibling ghost already holds the suppressed slot — correct end state
    # (Aaron V-1). update_columns wrote the cast value into @attributes and
    # cleared the dirty flag BEFORE the DB refused, so there is no recorded
    # change left to restore_attributes; reload takes value and clean state
    # back from the row, which is still live.
    reload
  end

  # Best-effort, admin-visibility, outside Trackable's callbacks — the same
  # shape as Membership#record_ownership_demotion; Trackable's header names
  # this writer. Metadata never carries the address (unencrypted JSON).
  def record_suppressed_delivery(mailer_action)
    ActivityLog.create!(
      actor: nil, action: "invitation.delivery_suppressed", trackable: self,
      workspace: resolved_workspace, visibility: "admin",
      metadata: { "mailer_action" => mailer_action.to_s }
    )
  rescue StandardError => e
    Rails.logger.warn("Activity tracking failed for Invitation##{id} (delivery_suppressed): #{e.message}")
    Rails.error.report(e, handled: true,
      context: { trackable: "Invitation##{id}", action: "invitation.delivery_suppressed" })
  end
end
