class ApplicationController < ActionController::Base
  include Authenticatable
  include Reauthenticatable
  include RequiresOnboarding
  include Pundit::Authorization
  include Toastable
  include Pagy::Method
  allow_browser versions: :modern

  stale_when_importmap_changes

  # Authenticated HTML must not be written to shared caches or the browser's
  # disk cache — it now carries the form-draft key meta (spec: key-surface
  # hardening). Trade-off accepted: this defeats HTML ETag revalidation for
  # signed-in users.
  after_action :prevent_authenticated_html_caching

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from Suspendable::SuspendedError, with: :workspace_locked
  rescue_from Workspace::NotAdmittableError, with: :not_admittable

  helper_method :signups_open?, :pending_join_workspace

  def signups_open?
    return @signups_open if defined?(@signups_open)

    @signups_open = SignupPolicy.allows_signup?(
      invitation_token: session[:pending_invitation_token],
      join_token: session[:pending_join_token]
    )
  end

  # A join token parked in the session (open-link Flow B) that resolves to a
  # workspace the signed-in user could join but isn't in yet. Surfaced as a
  # dismissible banner so a pre-existing user re-consents to the join instead of
  # being force-joined — the drive-by-join guard's other half. nil when there's
  # nothing actionable to offer.
  def pending_join_workspace
    return @pending_join_workspace if defined?(@pending_join_workspace)

    @pending_join_workspace = resolve_pending_join_workspace
  end

  private

  def resolve_pending_join_workspace
    return nil unless Current.user

    token = session[:pending_join_token]
    return nil if token.blank?

    workspace = WorkspaceJoinLink.find_active(token)&.workspace
    return nil unless workspace&.accepting_open_joins?
    return nil if workspace.memberships.kept.exists?(user: Current.user)

    workspace
  end

  # Backs Pundit's pundit_user and is consumed by mounted engines (e.g.
  # markdowndocs) — keep it even though app code should prefer Current.user.
  def current_user
    Current.user
  end

  # SEC-1: refuse to grant a role the actor doesn't outrank. The server is the
  # real gate; role selects render assignable_roles_for as defence + UX.
  def authorize_role_grant!(policy_record, role)
    return if policy(policy_record).may_grant?(role)

    log_blocked_role_grant(policy_record, role)
    raise Pundit::NotAuthorizedError
  end

  # G (SEC-1 follow-up): a blocked escalation attempt is itself a security
  # event — log the SPECIFIC denial to the admin feed (not every 403; generic
  # authorization failures stay unlogged). Best-effort, same contract as
  # Trackable#create_activity: tracking must never fail the request.
  def log_blocked_role_grant(policy_record, role)
    ActivityLog.create!(
      actor: Current.user,
      action: "membership.role_grant_blocked",
      trackable: policy_record.is_a?(ActiveRecord::Base) ? policy_record : nil,
      workspace: Current.workspace,
      visibility: "admin",
      metadata: { "attempted_role" => role.slug }
    )
  rescue StandardError => e
    Rails.logger.warn("Blocked-grant logging failed: #{e.class}: #{e.message}")
    Rails.error.report(e, handled: true, context: { action: "membership.role_grant_blocked" })
  end

  def assignable_roles_for(policy_record)
    Current.workspace.effective_roles.select { |role| policy(policy_record).may_grant?(role) }
  end

  def prevent_authenticated_html_caching
    return unless Current.user && request.format.html?

    response.headers["Cache-Control"] = "no-store"
  end

  def user_not_authorized
    destination = if Current.workspace.present?
      workspace_home = workspace_path(Current.workspace)
      # #931: answering a refusal at the workspace's OWN path with that same
      # path is a redirect loop, not an error page. GET, PATCH, PUT and DELETE
      # all share `/workspaces/:slug`, so a refused workspace update or destroy
      # lands on the index too — not only the GET this was written for. A
      # refusal at any other path still lands on the workspace.
      request.path == workspace_home ? workspaces_path : workspace_home
    else
      # url_from filters cross-origin referers (SEC-10): a forged Referer must
      # fall back to root, not make the error handler raise UnsafeRedirectError.
      url_from(request.referer) || root_path
    end
    redirect_to(destination, alert: t("errors.not_authorized"))
  end

  def record_not_found
    respond_to do |format|
      format.turbo_stream { render turbo_stream: error_toast(t("errors.not_found")), status: :not_found }
      format.html { redirect_to(url_from(request.referer) || root_path, alert: t("errors.not_found")) }
      format.json { render json: { error: t("errors.not_found") }, status: :not_found }
      format.any { head :not_found }
    end
  end

  def workspace_locked
    redirect_to workspaces_path, alert: t("workspaces.locked_notice")
  end

  # Generic, non-disclosing redirect for Workspace::NotAdmittableError — an
  # outsider following a join link/invitation must not learn whether the
  # workspace is archived, suspended, or deleted.
  def not_admittable
    redirect_to root_path, alert: t("workspaces.joins.invalid_or_revoked")
  end
end
