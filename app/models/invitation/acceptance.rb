class Invitation < ApplicationRecord
  # Redeeming an invitation: one choke point, three shapes behind the polymorphic
  # target (workspace, project, client), and the address-bound consume path both
  # signup flows share.
  module Acceptance
    extend ActiveSupport::Concern

    included do
      validate :client_invite_targets_a_project
    end

    class_methods do
      # Both signup acceptance paths (PendingClaims#claim!, Authentication#claim_pending!) funnel here so their
      # semantics can't diverge: nil when the token matches nothing, NotAcceptable when it does but can't be accepted.
      def consume!(token:, user:, expected_email: nil)
        return if token.blank?

        invitation = find_by(token: token)
        return if invitation.nil?

        # Address-bound redemption: a leaked link can't be claimed from a different proven address;
        # nil-email magic links stay bearer by design. See /docs/developer/security.
        if invitation.email.present? && expected_email.present? &&
            !EmailNormalizer.equivalent?(invitation.email, expected_email)
          raise EmailMismatch
        end

        invitation.accept!(user)
        invitation
      end
    end

    def client_invite? = company_name.present?

    def accept!(user)
      transaction do
        lock!
        guard_acceptable!
        if client_invite?
          accept_client_invitation!(user)
        elsif invitable_type == "Project"
          accept_project_invitation!(user)
        else
          accept_workspace_invitation!(user)
        end

        update!(
          status: "accepted",
          accepted_by: user,
          accepted_at: Time.current
        )
      end
    end

    private

    # One choke point, one generic message on all three refusals — an invitee must not learn a workspace is locked.
    def guard_acceptable!
      raise NotAcceptable, "Invitation no longer acceptable" unless pending?
      raise NotAcceptable, "Invitation no longer acceptable" if expired?
      raise NotAcceptable, "Invitation no longer acceptable" unless resolved_workspace&.admittable?
    end

    def accept_client_invitation!(user)
      raise NotAcceptable, "Invitation no longer acceptable" unless invitable.kept?
      raise NotAcceptable, "Clientside is disabled for this project" unless invitable.clientside_enabled?

      access = invitable.client_accesses.find_by(user: user)
      if access&.discarded?
        access.undiscard!
      elsif access.nil?
        invitable.client_accesses.create!(user: user, company_name: company_name)
      end
      user.update!(onboarded_at: Time.current) unless user.onboarded?
    end

    def client_invite_targets_a_project
      return unless client_invite?
      errors.add(:base, :client_requires_project) if invitable_type != "Project"
    end

    def accept_workspace_invitation!(user)
      invitable.admit(user, role: role, granted_by: invited_by)
    end

    def accept_project_invitation!(user)
      # Checked first so a dead project never grants a workspace membership as a side effect.
      raise NotAcceptable, "Invitation no longer acceptable" unless invitable.kept?

      # :adopt — a project invite must tolerate an existing workspace member (see the "already a project member" spec).
      invitable.workspace.admit(user, role: role, granted_by: invited_by, on_existing: :adopt)

      if invitable.project_memberships.exists?(user: user)
        errors.add(:base, :already_project_member)
        raise ActiveRecord::RecordInvalid, self
      end
      invitable.project_memberships.create!(user: user, role: project_role || "editor")
    end
  end
end
